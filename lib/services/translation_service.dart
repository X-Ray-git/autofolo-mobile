import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'llm_config.dart';

enum TranslationStatus { idle, pending, done, error }

class TranslationRecord {
  final TranslationStatus status;
  final String? translatedTitle;
  final String? translatedContent;
  final String? errorMessage;
  final int updatedAt;

  const TranslationRecord({
    required this.status,
    this.translatedTitle,
    this.translatedContent,
    this.errorMessage,
    required this.updatedAt,
  });

  bool get isPending => status == TranslationStatus.pending;
  bool get isTranslated => status == TranslationStatus.done;

  TranslationRecord copyWith({
    TranslationStatus? status,
    String? translatedTitle,
    String? translatedContent,
    String? errorMessage,
    int? updatedAt,
  }) {
    return TranslationRecord(
      status: status ?? this.status,
      translatedTitle: translatedTitle ?? this.translatedTitle,
      translatedContent: translatedContent ?? this.translatedContent,
      errorMessage: errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'translatedTitle': translatedTitle,
    'translatedContent': translatedContent,
    'errorMessage': errorMessage,
    'updatedAt': updatedAt,
  };

  factory TranslationRecord.fromJson(Map<dynamic, dynamic> json) {
    final statusName = json['status'] as String? ?? TranslationStatus.done.name;
    final status = TranslationStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => TranslationStatus.done,
    );
    return TranslationRecord(
      status: status,
      translatedTitle: json['translatedTitle'] as String?,
      translatedContent: json['translatedContent'] as String?,
      errorMessage: json['errorMessage'] as String?,
      updatedAt:
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

abstract final class TranslationService {
  static const String _apiBase = 'https://api.deepseek.com';
  static const Duration _timeout = Duration(seconds: 300);

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _apiBase,
    connectTimeout: _timeout,
    receiveTimeout: _timeout,
    sendTimeout: _timeout,
  ));

  static final RxMap<String, TranslationRecord> _records =
      <String, TranslationRecord>{}.obs;
  static final Map<String, Future<TranslationRecord>> _inFlight = {};
  static bool _hydrated = false;
  static String? _apiKey;

  static void setApiKey(String key) => _apiKey = key.trim();

  static String? getApiKey() =>
      _apiKey ?? (GStorage.setting.get('deepseek_api_key') as String?);

  static void ensureHydrated() {
    if (_hydrated) return;
    final box = GStorage.translations;
    var staleCount = 0;
    for (final key in box.keys.cast<String>()) {
      final value = box.get(key);
      if (value is Map) {
        final record = TranslationRecord.fromJson(
          value.cast<dynamic, dynamic>(),
        );
        // 清理残留的 pending 状态（App 被杀/崩溃导致）
        if (record.status == TranslationStatus.pending) {
          staleCount++;
          box.delete(key); // 从磁盘移除旧版残留，后续 pending 不再落盘
          _records[key] = record.copyWith(
            status: TranslationStatus.idle,
          );
        } else {
          _records[key] = record;
        }
      } else if (value is String && value.isNotEmpty) {
        _records[key] = TranslationRecord(
          status: TranslationStatus.done,
          translatedContent: _cleanTranslatedContent(value),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
    if (staleCount > 0) {
      debugPrint('[Translation] 清理了 $staleCount 条残留 pending 记录');
    }
    _hydrated = true;
  }

  static TranslationRecord? recordOf(String entryId) {
    ensureHydrated();
    return _records[entryId];
  }

  static TranslationStatus statusOf(String entryId) {
    return recordOf(entryId)?.status ?? TranslationStatus.idle;
  }

  static bool isPending(String entryId) =>
      statusOf(entryId) == TranslationStatus.pending;

  static bool hasTranslation(String entryId) =>
      statusOf(entryId) == TranslationStatus.done;

  /// 标记为 pending（自动翻译入队时用，让卡片立即显示翻译中）
  static void markPending(String entryId) {
    ensureHydrated();
    if (_records.containsKey(entryId) && _records[entryId]!.isTranslated) {
      return; // 已翻译的不覆盖
    }
    _records[entryId] = TranslationRecord(
      status: TranslationStatus.pending,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    // pending 不落盘 — 瞬态，重启后无需恢复
  }

  static String displayTitleFor(ArticleModel article) {
    final record = recordOf(article.entryId);
    final translated = record?.translatedTitle?.trim();
    if (translated != null && translated.isNotEmpty) {
      return translated;
    }
    return article.title;
  }

  static String? translatedContentFor(String entryId) {
    final record = recordOf(entryId);
    return record?.translatedContent;
  }

  static Future<TranslationRecord> translateArticle(
    ArticleModel article, {
    String targetLang = '简体中文',
    String? overrideContent,
  }) {
    ensureHydrated();
    final existing = _inFlight[article.entryId];
    if (existing != null) return existing;

    final future = _translateArticleInternal(article, targetLang, overrideContent);
    _inFlight[article.entryId] = future;
    future.whenComplete(() {
      _inFlight.remove(article.entryId);
    });
    return future;
  }

  static Future<TranslationRecord> _translateArticleInternal(
    ArticleModel article,
    String targetLang,
    String? overrideContent,
  ) async {
    final apiKey = getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('DeepSeek API key not configured');
    }

    final previous = recordOf(article.entryId);
    // pending 只写内存，不落盘
    _records[article.entryId] = (previous ??
            TranslationRecord(
              status: TranslationStatus.idle,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ))
        .copyWith(
          status: TranslationStatus.pending,
          errorMessage: null,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );

    final htmlContent = ArticleContentUtils.normalizeHtmlForEntry(
      article.entryId,
      overrideContent ?? article.content ?? '',
    );
    // 正文过大时分块翻译，避免 LLM 输出畸形 JSON
    const chunkThreshold = 35 * 1024;
    if (htmlContent.length > chunkThreshold) {
      return _translateInChunks(article, targetLang, htmlContent);
    }
    if (htmlContent.isEmpty) {
      final record = TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: '文章内容为空，无法翻译',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(article.entryId, record);
      return record;
    }

    final prompt =
        '''
你是一个专业的文章翻译助手。请将下面文章翻译成$targetLang。

要求：
1. 只返回 JSON，不要返回 markdown、解释或代码块
2. JSON 结构必须是：{"translated_title":"...","translated_html":"..."}
3. translated_title 为翻译后的标题
4. translated_html 必须保留所有 HTML 标签、结构、属性、空白和排版
5. 只翻译可见文本，不要改动任何 HTML 标签

标题：
${article.title}

HTML：
<html>$htmlContent</html>
''';

    try {
      _dio.options.headers['Authorization'] = 'Bearer $apiKey';
      _dio.options.headers['Content-Type'] = 'application/json';

      final llmConfig = LlmConfig.loadTranslate();
      final requestBody = <String, dynamic>{
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'response_format': {'type': 'json_object'},
        'stream': false,
        ...llmConfig.toRequestBody(),
      };

      final response = await _dio.post(
        '/chat/completions',
        data: requestBody,
      );

      final content = _extractMessageContent(response.data);
      if (content == null || content.trim().isEmpty) {
        throw StateError('DeepSeek returned an empty translation result');
      }

      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(_normalizeJsonPayload(content))
            as Map<String, dynamic>;
      } on FormatException {
        final recovered = _extractJsonObject(content);
        if (recovered != null) {
          parsed = recovered;
        } else {
          rethrow;
        }
      }
      final translatedTitle =
          (parsed['translated_title'] ?? parsed['title'] ?? '')
              .toString()
              .trim();
      final translatedHtml =
          (parsed['translated_html'] ?? parsed['content'] ?? '')
              .toString()
              .trim();

      if (translatedHtml.isEmpty) {
        throw StateError('DeepSeek translation result missing translated_html');
      }

      final record = TranslationRecord(
        status: TranslationStatus.done,
        translatedTitle: translatedTitle.isEmpty ? null : translatedTitle,
        translatedContent: _cleanTranslatedContent(translatedHtml),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(article.entryId, record);
      return record;
    } on DioException catch (e) {
      final error = e.message ?? 'DeepSeek request failed';
      _restoreAfterFailure(article.entryId, previous, error);
      return TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: error,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } on FormatException catch (e) {
      _restoreAfterFailure(article.entryId, previous, e.message);
      return TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: e.message,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } on StateError catch (e) {
      _restoreAfterFailure(article.entryId, previous, e.message);
      return TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: e.message,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      _restoreAfterFailure(article.entryId, previous, e.toString());
      return TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: e.toString(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  // ─── 分块翻译 ──────────────────────────────────

  static const int _chunkSize = 12 * 1024; // 每块 ≤12KB

  /// 分块翻译大文章：按段落边界切成小块，并行请求 LLM，拼接结果
  static Future<TranslationRecord> _translateInChunks(
    ArticleModel article,
    String targetLang,
    String htmlContent,
  ) async {
    final apiKey = getApiKey()!;
    final chunks = _splitHtmlIntoChunks(htmlContent);
    debugPrint('[Translation] 🧩 ${article.entryId}: 切分为 ${chunks.length} 块');

    final llmConfig = LlmConfig.loadTranslate();
    final futures = List<Future<_ChunkResult>>.generate(chunks.length, (i) {
      return _translateOneChunk(
        i: i,
        total: chunks.length,
        chunkHtml: chunks[i],
        articleTitle: article.title,
        apiKey: apiKey,
        targetLang: targetLang,
        llmConfig: llmConfig,
      );
    });

    final results = await Future.wait(futures);

    final parts = <String>[];
    final titleParts = <String>[];
    var hasError = false;
    for (final r in results) {
      if (r.error != null) {
        debugPrint('[Translation] 🧩 块 ${r.index}/${chunks.length} ❌ ${r.error}');
        hasError = true;
        parts.add('');
      } else {
        parts.add(r.html!);
        if (r.title != null) titleParts.add(r.title!);
      }
    }

    final translatedTitle = titleParts.isEmpty ? null : titleParts.join(' ').trim();

    if (hasError) {
      final record = TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: '分块翻译部分失败',
        translatedContent: parts.join(''),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(article.entryId, record);
      return record;
    }

    final combinedHtml = parts.join('');
    final record = TranslationRecord(
      status: TranslationStatus.done,
      translatedTitle: (translatedTitle?.isNotEmpty == true)
          ? translatedTitle
          : null,
      translatedContent: _cleanTranslatedContent(combinedHtml),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _writeRecord(article.entryId, record);
    return record;
  }

  static Future<_ChunkResult> _translateOneChunk({
    required int i,
    required int total,
    required String chunkHtml,
    required String articleTitle,
    required String apiKey,
    required String targetLang,
    required LlmConfig llmConfig,
  }) async {
    final isFirst = i == 0;
    final prompt = isFirst
        ? '''
你是一个专业的文章翻译助手。请将下面文章片段翻译成$targetLang。这是文章的第 1/$total 段。

要求：
1. 只返回 JSON，不要返回 markdown、解释或代码块
2. JSON 结构必须是：{"translated_title":"...","translated_html":"..."}
3. translated_title 为翻译后的标题
4. translated_html 必须保留所有 HTML 标签、结构、属性、空白和排版
5. 只翻译可见文本，不要改动任何 HTML 标签

标题：
$articleTitle

HTML：
<html>$chunkHtml</html>
'''
        : '''
你是一个专业的文章翻译助手。请将下面文章片段翻译成$targetLang。这是文章的第 ${i + 1}/$total 段。

要求：
1. 只返回 JSON，不要返回 markdown、解释或代码块
2. JSON 结构必须是：{"translated_html":"..."}
3. 必须保留所有 HTML 标签、结构、属性、空白和排版
4. 只翻译可见文本，不要改动任何 HTML 标签

HTML：
<html>$chunkHtml</html>
''';

    try {
      // 每个并发请求用独立 header，避免共享 Dio 实例的状态竞争
      final options = Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'messages': [{'role': 'user', 'content': prompt}],
          'response_format': {'type': 'json_object'},
          'stream': false,
          ...llmConfig.toRequestBody(),
        },
        options: options,
      );

      final content = _extractMessageContent(response.data);
      if (content == null || content.trim().isEmpty) {
        return _ChunkResult(i, error: '空响应');
      }

      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(_normalizeJsonPayload(content))
            as Map<String, dynamic>;
      } on FormatException {
        final recovered = _extractJsonObject(content);
        if (recovered != null) {
          parsed = recovered;
        } else {
          return _ChunkResult(i, error: 'JSON 解析失败');
        }
      }

      final title = isFirst
          ? (parsed['translated_title'] ?? '').toString().trim()
          : null;
      final html = (parsed['translated_html'] ?? '').toString().trim();
      if (html.isEmpty) {
        return _ChunkResult(i, error: '缺少 translated_html');
      }
      return _ChunkResult(i, title: (title?.isNotEmpty == true) ? title : null, html: html);
    } catch (e) {
      return _ChunkResult(i, error: e.toString());
    }
  }

  /// 按段落边界切割 HTML，每块 ≤ _chunkSize
  static List<String> _splitHtmlIntoChunks(String html) {
    final chunks = <String>[];
    final buf = StringBuffer();
    var i = 0;

    while (i < html.length) {
      // 找下一个段落起始标签 <p>, <h1>-<h6>, <li>, <blockquote>, <div
      final nextBlock = _findNextBlockTag(html, i + 1);
      final segmentEnd = nextBlock > i ? nextBlock : html.length;
      final segment = html.substring(i, segmentEnd);

      if (buf.length + segment.length > _chunkSize && buf.isNotEmpty) {
        chunks.add(buf.toString());
        buf.clear();
      }
      buf.write(segment);
      i = segmentEnd;
    }

    if (buf.isNotEmpty) chunks.add(buf.toString());
    return chunks;
  }

  static int _findNextBlockTag(String html, int from) {
    // 匹配 from 之后下一个块级标签的起始位置
    final pattern = RegExp(r'<(p|h[1-6]|li|blockquote|div|ul|ol|table)\b[^>]*>');
    final idx = html.indexOf(pattern, from);
    return idx;
  }

  // ─── JSON 解析辅助 ───────────────────────────

  static void deleteTranslation(String entryId) {
    ensureHydrated();
    _records.remove(entryId);
    GStorage.translations.delete(entryId);
  }

  static void _restoreAfterFailure(
    String entryId,
    TranslationRecord? previous,
    String errorMessage,
  ) {
    if (previous != null) {
      _writeRecord(
        entryId,
        previous.copyWith(
          status: previous.isTranslated
              ? TranslationStatus.done
              : TranslationStatus.idle,
          errorMessage: errorMessage,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else {
      final record = TranslationRecord(
        status: TranslationStatus.error,
        errorMessage: errorMessage,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(entryId, record);
    }
  }

  static void _writeRecord(String entryId, TranslationRecord record) {
    ensureHydrated();
    _records[entryId] = record;
    GStorage.translations.put(entryId, record.toJson());
  }

  static String _cleanTranslatedContent(String raw) {
    var content = raw.trim();
    if (content.startsWith('```')) {
      content = content.replaceFirst(RegExp(r'^```[a-zA-Z0-9]*\s*'), '');
      content = content.replaceFirst(RegExp(r'\s*```$'), '');
    }
    if (content.startsWith('<html>') && content.endsWith('</html>')) {
      content = content.substring(6, content.length - 7).trim();
    }
    return content;
  }

  static String _normalizeJsonPayload(String raw) {
    var content = raw.trim();
    // 去掉 markdown 代码块包裹
    if (content.startsWith('```')) {
      content = content.replaceFirst(RegExp(r'^```[a-zA-Z0-9]*\s*'), '');
      content = content.replaceFirst(RegExp(r'\s*```$'), '');
    }
    // 去掉首尾非 JSON 文本（模型有时在 JSON 前后附加说明文字）
    final firstBrace = content.indexOf('{');
    final lastBrace = content.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      content = content.substring(firstBrace, lastBrace + 1);
    }
    return content;
  }

  /// JSON 解析失败时的恢复：尝试找最外层的 { } 对象
  static Map<String, dynamic>? _extractJsonObject(String raw) {
    final first = raw.indexOf('{');
    final last = raw.lastIndexOf('}');
    if (first < 0 || last <= first) return null;
    try {
      return jsonDecode(raw.substring(first, last + 1))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String? _extractMessageContent(dynamic data) {
    final choices = data is Map<String, dynamic> ? data['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content is String) {
            return content;
          }
        }
      }
    }
    return null;
  }
}

// ─── 分块翻译结果 ─────────────────────────────

final class _ChunkResult {
  final int index;
  final String? title;
  final String? html;
  final String? error;
  _ChunkResult(this.index, {this.title, this.html, this.error});
}
