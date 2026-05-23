import 'dart:async';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'local_article_db_service.dart';
import 'feed_readability_settings_service.dart';
import 'auto_filter_worker.dart';
import 'auto_translation_worker.dart';
import 'auto_summary_worker.dart';

abstract final class AutoReadabilityWorker {
  static final _queue = <ArticleModel>[];
  static bool _isRunning = false;

  /// 最大并发请求数
  static const int _concurrency = 3;

  /// 入队一篇文章
  static void enqueueOne(ArticleModel article) {
    if (article.isRead) return;
    _queue.add(article);
    _startProcessingIfNeeded();
  }

  /// 批量入队
  static void enqueueMany(List<ArticleModel> articles) {
    final unread = articles.where((a) => !a.isRead).toList();
    if (unread.isEmpty) return;
    _queue.addAll(unread);
    _startProcessingIfNeeded();
  }

  static void _startProcessingIfNeeded() {
    if (_isRunning || _queue.isEmpty) return;
    _isRunning = true;
    unawaited(_processQueue());
  }

  static Future<void> _processQueue() async {
    while (_queue.isNotEmpty) {
      final count = _queue.length > _concurrency ? _concurrency : _queue.length;
      final batch = _queue.sublist(0, count);
      _queue.removeRange(0, count);

      await Future.wait(batch.map((article) => _processArticle(article)));
    }

    _isRunning = false;
    // 双重检查
    if (_queue.isNotEmpty) {
      _startProcessingIfNeeded();
    }
  }

  static Future<void> _processArticle(ArticleModel article) async {
    ArticleModel processedArticle = article;

    // 检查是否需要去抓取长文
    final rawContent = article.content ?? '';
    final htmlContent = ArticleContentUtils.normalizeHtmlForEntry(article.entryId, rawContent);
    final isManualForced = FeedReadabilitySettingsService.isAutoReadabilityEnabled(article.feedId);

    // 防重复拉取标记
    final hasFetchedKey = 'readability_fetched_${article.entryId}';
    final hasFetched = GStorage.setting.get(hasFetchedKey) == true;

    // 如果未抓取过，且（开启了手动强制拉取，或者正文过短），且有原始链接，尝试抓取 Readability 长文
    if (!hasFetched && (isManualForced || htmlContent.length < 500) && article.url.isNotEmpty) {
      // 立即打上标记，防止无论成功失败都反复重试
      GStorage.setting.put(hasFetchedKey, true);
      try {
        final response = await Dio().get(article.url);
        final document = html_parser.parse(response.data.toString());
        final node = ArticleContentUtils.getReadabilityContent(document);
        if (node != null) {
          final newHtml = node.outerHtml;
          // 只有当抓取到的长文确实比摘要长时，才替换并入库
          if (newHtml.length > rawContent.length) {
             processedArticle = ArticleModel(
              entryId: article.entryId,
              feedId: article.feedId,
              feedTitle: article.feedTitle,
              feedImage: article.feedImage,
              title: article.title,
              url: article.url,
              content: newHtml, // 替换长文
              publishedAt: article.publishedAt,
              isRead: article.isRead,
              category: article.category,
              subscriptionCategory: article.subscriptionCategory,
              author: article.author,
              imageUrl: article.imageUrl,
              isRejectedByAi: article.isRejectedByAi,
              filterReason: article.filterReason,
              filterReviewed: article.filterReviewed,
            );
            // 将包含长文的新文章存入本地数据库
            LocalArticleDbService.upsertOne(processedArticle);
            
            // 清除之前的缓存，保证后续 AI 用到最新的解析内容
            ArticleContentUtils.clearCacheForEntry(article.entryId);
          }
        }
      } catch (_) {
        // 静默失败，沿用原有的短文
      }
    }

    // 处理完正文后（无论是否成功抓取长文），流转到下游 AI 过滤、翻译和摘要 Worker
    AutoFilterWorker.enqueue(processedArticle);
    AutoTranslationWorker.enqueueIfEnabled(processedArticle);
    AutoSummaryWorker.enqueueIfNeeded(processedArticle);
  }
}
