import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/article.dart';
import 'llm_config.dart';
import 'translation_service.dart';
import 'feed_translation_settings_service.dart';

/// 后台自动翻译任务队列 — 并行处理
abstract final class AutoTranslationWorker {
  static final _queue = <ArticleModel>[];
  static Timer? _processingTimer;
  static bool _isProcessing = false;
  static const Duration _processingInterval = Duration(milliseconds: 500);

  static int get _concurrency => LlmConfig.loadTranslate().concurrency;

  /// 排队文章自动翻译（如果该feed启用了自动翻译）
  static void enqueueIfEnabled(ArticleModel article) {
    if (article.feedId.isEmpty) return;
    if (TranslationService.hasTranslation(article.entryId)) return;
    if (TranslationService.isPending(article.entryId)) return;
    final content = (article.content ?? '').trim();
    if (content.isEmpty) return;
    if (!FeedTranslationSettingsService.isAutoTranslateEnabled(
      article.feedId,
    )) {
      return;
    }

    if (!_queue.any((a) => a.entryId == article.entryId)) {
      _queue.add(article);
      // 写入 pending 状态，让列表卡片立即显示翻译中动画
      TranslationService.ensureHydrated();
      if (!TranslationService.hasTranslation(article.entryId)) {
        TranslationService.markPending(article.entryId);
      }
      debugPrint('[AutoTranslation] enqueued: ${article.title}');
    }

    _ensureProcessing();
  }

  /// 排队多篇文章
  static void enqueueIfEnabledMany(List<ArticleModel> articles) {
    for (final article in articles) {
      enqueueIfEnabled(article);
    }
  }

  static void _ensureProcessing() {
    if (_processingTimer != null && _processingTimer!.isActive) return;
    _processingTimer = Timer.periodic(
      _processingInterval,
      (_) => _processNext(),
    );
  }

  static Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    try {
      // 一次取最多 _concurrency 篇，用 Future.wait 并行翻译
      final batch = <ArticleModel>[];
      for (int i = 0; i < _concurrency && _queue.isNotEmpty; i++) {
        batch.add(_queue.removeAt(0));
      }

      await Future.wait(
        batch.map((article) => _translateArticle(article)),
      );
    } finally {
      _isProcessing = false;

      if (_queue.isEmpty) {
        _processingTimer?.cancel();
        _processingTimer = null;
      }
    }
  }

  static Future<void> _translateArticle(ArticleModel article) async {
    try {
      await TranslationService.translateArticle(article, targetLang: '简体中文');
      debugPrint('[AutoTranslation] Done: ${article.title}');
    } catch (e) {
      debugPrint('[AutoTranslation] Failed: ${article.title}: $e');
    }
  }

  static int get queueSize => _queue.length;

  static void cancelProcessing() {
    _processingTimer?.cancel();
    _processingTimer = null;
    _queue.clear();
    _isProcessing = false;
  }
}
