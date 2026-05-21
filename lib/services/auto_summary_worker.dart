import 'dart:async';

import '../models/article.dart';
import 'llm_config.dart';
import 'summary_service.dart';

/// 后台自动摘要任务队列 — 并行处理
abstract final class AutoSummaryWorker {
  static final _queue = <ArticleModel>[];
  static Timer? _processingTimer;
  static bool _isProcessing = false;
  static const Duration _processingInterval = Duration(milliseconds: 500);

  static int get _concurrency => LlmConfig.loadSummary().concurrency;

  /// 排队文章自动摘要（对所有未摘要的文章）
  static void enqueueIfNeeded(ArticleModel article) {
    if (article.entryId.isEmpty) return;
    if (SummaryService.hasSummary(article.entryId)) return;
    final content = (article.content ?? '').trim();
    if (content.isEmpty) return;

    if (!_queue.any((a) => a.entryId == article.entryId)) {
      _queue.add(article);
    }

    _ensureProcessing();
  }

  /// 排队多篇文章
  static void enqueueIfNeededMany(List<ArticleModel> articles) {
    for (final article in articles) {
      enqueueIfNeeded(article);
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
      final batch = <ArticleModel>[];
      for (int i = 0; i < _concurrency && _queue.isNotEmpty; i++) {
        batch.add(_queue.removeAt(0));
      }

      await Future.wait(
        batch.map((article) => _summarizeArticle(article)),
      );
    } finally {
      _isProcessing = false;

      if (_queue.isEmpty) {
        _processingTimer?.cancel();
        _processingTimer = null;
      }
    }
  }

  static Future<void> _summarizeArticle(ArticleModel article) async {
    try {
      await SummaryService.summarizeArticle(article);
    } catch (e) {
      // 静默处理
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
