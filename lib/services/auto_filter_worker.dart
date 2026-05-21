import 'dart:async';
import 'package:get/get.dart';

import '../models/article.dart';
import '../utils/storage.dart';
import 'article_filter_service.dart';
import 'article_state_notifier.dart';
import 'llm_config.dart';
import 'local_article_db_service.dart';

/// 后台 AI 过滤任务队列 — 并行判定
abstract final class AutoFilterWorker {
  static final _queue = <ArticleModel>[];
  static Timer? _processingTimer;
  static bool _isProcessing = false;
  static const Duration _processingInterval = Duration(milliseconds: 500);

  static int get _concurrency => LlmConfig.loadFilter().concurrency;

  /// 队列中剩余
  static final queuedCount = 0.obs;
  /// 正在处理中
  static final processingCount = 0.obs;
  /// 已完成（含成功和失败）
  static final doneCount = 0.obs;

  /// 增量回调：审核页在前台时直接推送被拒文章
  static void Function(String entryId, String title, String reason)? onRejected;

  /// 排队文章 AI 过滤
  static void enqueue(ArticleModel article) {
    if (article.entryId.isEmpty) return;
    final local = GStorage.articleDb.get(article.entryId);
    if (local is Map) {
      if (local['filterReviewed'] == true) return;
      if (local['isRejectedByAi'] == true) return;
    }
    if (article.isRejectedByAi) return;
    if (article.filterReviewed) return;
    if (article.isRead) return;
    if (article.content == null || article.content!.trim().isEmpty) return;
    if (!_queue.any((a) => a.entryId == article.entryId)) {
      _queue.add(article);
      queuedCount.value = _queue.length;
    }

    _ensureProcessing();
  }

  static void enqueueMany(List<ArticleModel> articles) {
    for (final a in articles) {
      enqueue(a);
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

      processingCount.value = batch.length;
      queuedCount.value = _queue.length;
      doneCount.value = 0;

      await Future.wait(
        batch.map((article) => _filterArticle(article)),
      );
    } finally {
      _isProcessing = false;
      processingCount.value = 0;
      queuedCount.value = _queue.length;

      if (_queue.isEmpty) {
        _processingTimer?.cancel();
        _processingTimer = null;
      }
    }
  }

  static Future<void> _filterArticle(ArticleModel article) async {
    try {
      if (article.isRead) return; // 处理前再检查一次
      final result = await ArticleFilterService.filterArticle(article);
      if (article.isRead) return; // 处理中可能被标已读

      if (result.shouldReject) {
        final updated = ArticleModel(
          entryId: article.entryId,
          feedId: article.feedId,
          feedTitle: article.feedTitle,
          feedImage: article.feedImage,
          title: article.title,
          url: article.url,
          content: article.content,
          publishedAt: article.publishedAt,
          isRead: article.isRead,
          category: article.category,
          subscriptionCategory: article.subscriptionCategory,
          author: article.author,
          imageUrl: article.imageUrl,
          isRejectedByAi: true,
          filterReason: result.reason,
          filterReviewed: article.filterReviewed,
        );
        LocalArticleDbService.upsertOne(updated);
        ArticleStateNotifier.tick(article.entryId);
        // 增量推送：审核页在前台时直接追加
        onRejected?.call(article.entryId, article.title, result.reason);
      } else {
        // AI 判定保留 → 标记已审核，避免重复入队
        if (article.filterReviewed) return;
        final raw = GStorage.articleDb.get(article.entryId);
        if (raw is Map) {
          raw['filterReviewed'] = true;
          raw['isRejectedByAi'] = false;
          GStorage.articleDb.put(article.entryId, raw);
          // Kept
        }
      }
    } catch (e) {
      // Failed silently
    } finally {
      doneCount.value++;
    }
  }

  static int get queueSize => _queue.length;

  static void cancelProcessing() {
    _processingTimer?.cancel();
    _processingTimer = null;
    _queue.clear();
    _isProcessing = false;
    queuedCount.value = 0;
    processingCount.value = 0;
    doneCount.value = 0;
  }

  /// 清除单篇文章的过滤状态（用户捞回）
  static void unReject(String entryId) {
    if (entryId.isEmpty) return;
    final raw = GStorage.articleDb.get(entryId);
    if (raw is! Map) return;
    // 直接写 DB，绕过 upsertMany 的 OR 合并逻辑
    raw['isRejectedByAi'] = false;
    raw['filterReason'] = null;
    raw['filterReviewed'] = true;
    GStorage.articleDb.put(entryId, raw);
    ArticleStateNotifier.tick(entryId);
  }
}
