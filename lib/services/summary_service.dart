import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'llm_config.dart';

enum SummaryStatus { idle, pending, done, error }

class SummaryRecord {
  final SummaryStatus status;
  final String? summaryText;
  final String? errorMessage;
  final int updatedAt;

  const SummaryRecord({
    required this.status,
    this.summaryText,
    this.errorMessage,
    required this.updatedAt,
  });

  bool get isPending => status == SummaryStatus.pending;
  bool get isSummarized => status == SummaryStatus.done;

  SummaryRecord copyWith({
    SummaryStatus? status,
    String? summaryText,
    String? errorMessage,
    int? updatedAt,
  }) {
    return SummaryRecord(
      status: status ?? this.status,
      summaryText: summaryText ?? this.summaryText,
      errorMessage: errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'summaryText': summaryText,
    'errorMessage': errorMessage,
    'updatedAt': updatedAt,
  };

  factory SummaryRecord.fromJson(Map<dynamic, dynamic> json) {
    final statusName = json['status'] as String? ?? SummaryStatus.done.name;
    final status = SummaryStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => SummaryStatus.done,
    );
    return SummaryRecord(
      status: status,
      summaryText: json['summaryText'] as String?,
      errorMessage: json['errorMessage'] as String?,
      updatedAt:
          json['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

abstract final class SummaryService {
  static const String _apiBase = 'https://api.deepseek.com';
  static const Duration _timeout = Duration(seconds: 300);

  static final RxMap<String, SummaryRecord> _records =
      <String, SummaryRecord>{}.obs;
  static final Map<String, Future<SummaryRecord>> _inFlight = {};
  static bool _hydrated = false;
  static String? _apiKey;

  static void setApiKey(String key) => _apiKey = key.trim();

  static String? getApiKey() =>
      _apiKey ?? (GStorage.setting.get('deepseek_api_key') as String?);

  static void ensureHydrated() {
    if (_hydrated) return;
    final box = GStorage.summaries;
    for (final key in box.keys.cast<String>()) {
      final value = box.get(key);
      if (value is Map) {
        _records[key] = SummaryRecord.fromJson(value.cast<dynamic, dynamic>());
      } else if (value is String && value.isNotEmpty) {
        _records[key] = SummaryRecord(
          status: SummaryStatus.done,
          summaryText: value,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
    }
    _hydrated = true;
  }

  static SummaryRecord? recordOf(String entryId) {
    ensureHydrated();
    return _records[entryId];
  }

  static SummaryStatus statusOf(String entryId) {
    return recordOf(entryId)?.status ?? SummaryStatus.idle;
  }

  static bool isPending(String entryId) =>
      statusOf(entryId) == SummaryStatus.pending;

  static bool hasSummary(String entryId) =>
      statusOf(entryId) == SummaryStatus.done;

  static String? summaryFor(String entryId) {
    final record = recordOf(entryId);
    return record?.summaryText;
  }

  static Future<SummaryRecord> summarizeArticle(
    ArticleModel article, {
    String targetLang = '简体中文',
  }) {
    ensureHydrated();
    final existing = _inFlight[article.entryId];
    if (existing != null) return existing;

    final future = _summarizeArticleInternal(article, targetLang);
    _inFlight[article.entryId] = future;
    future.whenComplete(() {
      _inFlight.remove(article.entryId);
    });
    return future;
  }

  static Future<SummaryRecord> _summarizeArticleInternal(
    ArticleModel article,
    String targetLang,
  ) async {
    final apiKey = getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('DeepSeek API key not configured');
    }

    final previous = recordOf(article.entryId);
    _writeRecord(
      article.entryId,
      (previous ??
              SummaryRecord(
                status: SummaryStatus.idle,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              ))
          .copyWith(
            status: SummaryStatus.pending,
            errorMessage: null,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
    );

    final htmlContent = ArticleContentUtils.normalizeHtml(
      article.content ?? '',
    );
    if (htmlContent.isEmpty) {
      final record = SummaryRecord(
        status: SummaryStatus.error,
        errorMessage: '文章内容为空，无法生成摘要',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(article.entryId, record);
      return record;
    }

    final prompt =
        '''
你是一个专业的文章摘要助手。请用$targetLang生成一个简洁的文章摘要。

要求：
1. 只返回 JSON，不要返回 markdown、解释或代码块
2. JSON 结构必须是：{"summary":"..."}
3. summary 是一句话或最多两句话的摘要，控制在 100~300 字之间
4. 摘要应该抓住文章的核心观点和重要信息

标题：
${article.title}

HTML：
<html>$htmlContent</html>
''';

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: _apiBase,
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          sendTimeout: _timeout,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final llmConfig = LlmConfig.loadSummary();
      final requestBody = <String, dynamic>{
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'response_format': {'type': 'json_object'},
        'stream': false,
        ...llmConfig.toRequestBody(),
      };

      final response = await dio.post(
        '/chat/completions',
        data: requestBody,
      );

      final content = _extractMessageContent(response.data);
      if (content == null || content.trim().isEmpty) {
        throw StateError('DeepSeek returned an empty summary result');
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
      final summaryText = (parsed['summary'] ?? '').toString().trim();

      if (summaryText.isEmpty) {
        throw StateError('DeepSeek summary result missing summary field');
      }

      final record = SummaryRecord(
        status: SummaryStatus.done,
        summaryText: summaryText,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(article.entryId, record);
      return record;
    } on DioException catch (e) {
      final error = e.message ?? 'DeepSeek request failed';
      _restoreAfterFailure(article.entryId, previous, error);
      return SummaryRecord(
        status: SummaryStatus.error,
        errorMessage: error,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } on FormatException catch (e) {
      _restoreAfterFailure(article.entryId, previous, e.message);
      return SummaryRecord(
        status: SummaryStatus.error,
        errorMessage: e.message,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } on StateError catch (e) {
      _restoreAfterFailure(article.entryId, previous, e.message);
      return SummaryRecord(
        status: SummaryStatus.error,
        errorMessage: e.message,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  static void deleteSummary(String entryId) {
    ensureHydrated();
    _records.remove(entryId);
    GStorage.summaries.delete(entryId);
  }

  static void _restoreAfterFailure(
    String entryId,
    SummaryRecord? previous,
    String errorMessage,
  ) {
    if (previous != null) {
      _writeRecord(
        entryId,
        previous.copyWith(
          status: previous.isSummarized
              ? SummaryStatus.done
              : SummaryStatus.idle,
          errorMessage: errorMessage,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else {
      final record = SummaryRecord(
        status: SummaryStatus.error,
        errorMessage: errorMessage,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _writeRecord(entryId, record);
    }
  }

  static void _writeRecord(String entryId, SummaryRecord record) {
    ensureHydrated();
    _records[entryId] = record;
    GStorage.summaries.put(entryId, record.toJson());
  }

  static String? _extractMessageContent(dynamic data) {
    if (data is! Map) return null;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    final firstChoice = choices.first as Map<String, dynamic>?;
    if (firstChoice == null) return null;
    final message = firstChoice['message'];
    if (message is! Map) return null;
    return message['content'] as String?;
  }

  static String _normalizeJsonPayload(String raw) {
    var content = raw.trim();
    if (content.startsWith('```json')) {
      content = content
          .replaceFirst(RegExp(r'^```json\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    } else if (content.startsWith('```')) {
      content = content
          .replaceFirst(RegExp(r'^```\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final firstBrace = content.indexOf('{');
    final lastBrace = content.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      content = content.substring(firstBrace, lastBrace + 1);
    }
    return content;
  }

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
}
