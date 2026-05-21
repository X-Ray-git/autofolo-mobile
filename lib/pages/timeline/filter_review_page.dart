import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/auto_filter_worker.dart';
import '../../services/local_article_db_service.dart';
import '../../services/read_sync_service.dart';
import '../../utils/storage.dart';
import '../timeline/timeline_controller.dart';
import '../widgets/article_card.dart';

class FilterReviewPage extends StatefulWidget {
  const FilterReviewPage({super.key});

  @override
  State<FilterReviewPage> createState() => _FilterReviewPageState();
}

class _FilterReviewPageState extends State<FilterReviewPage> {
  final _articles = <ArticleModel>[].obs;
  final Set<String> _seenIds = {};

  @override
  void initState() {
    super.initState();
    _loadArticles();
    // 每隔 2 秒检查是否有新结果
    ever(AutoFilterWorker.doneCount, (_) => _checkNewArticles());
  }

  void _loadArticles() {
    final all = LocalArticleDbService.readAllArticles()
        .where((a) => a.isRejectedByAi && !a.isRead)
        .toList();
    for (final a in all) {
      _seenIds.add(a.entryId);
    }
    _articles.value = all;
  }

  void _checkNewArticles() {
    final all = LocalArticleDbService.readAllArticles()
        .where((a) => a.isRejectedByAi && !a.isRead)
        .toList();
    final newOnes = all.where((a) => !_seenIds.contains(a.entryId)).toList();
    if (newOnes.isEmpty) return;
    for (final a in newOnes) {
      _seenIds.add(a.entryId);
    }
    _articles.addAll(newOnes);
  }

  void _keep(ArticleModel article) {
    AutoFilterWorker.unReject(article.entryId);
    AutoFilterWorker.unReject(article.entryId);
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
    }
    setState(() => _articles.removeWhere((a) => a.entryId == article.entryId));
  }

  void _reject(ArticleModel article) {
    // 标记已审核，防止重判
    LocalArticleDbService.upsertOne(ArticleModel(
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
      isRejectedByAi: article.isRejectedByAi,
      filterReason: article.filterReason,
      filterReviewed: true,
    ));
    // 标已读
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsReadLocal(article.entryId);
    } else {
      GStorage.readStatus.put(article.entryId, true);
      LocalArticleDbService.setReadState(article.entryId, true);
    }
    ReadSyncService.enqueue(article.entryId,
        isInbox: article.category == 'inbox');
    setState(() => _articles.removeWhere((a) => a.entryId == article.entryId));
  }

  void _rejectAll() {
    for (final a in List.from(_articles)) {
      _reject(a);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final q = AutoFilterWorker.queuedCount.value;
          final p = AutoFilterWorker.processingCount.value;
          final hasActivity = q > 0 || p > 0;
          if (hasActivity) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('审核'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '判定中 ${q + p}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          }
          return Obx(() => Text('审核 (${_articles.length})'));
        }),
        actions: [
          if (_articles.isNotEmpty)
            TextButton(
              onPressed: _rejectAll,
              child: const Text('全部确认'),
            ),
        ],
      ),
      body: Obx(() => _articles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 48, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('暂无待审核文章',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  Obx(() {
                    final q = AutoFilterWorker.queuedCount.value;
                    final p = AutoFilterWorker.processingCount.value;
                    if (q > 0 || p > 0) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('AI 判定中: $q 排队, $p 处理中',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                ],
              ),
            )
          : Column(
              children: [
                // 进度条
                Obx(() {
                  final q = AutoFilterWorker.queuedCount.value;
                  final p = AutoFilterWorker.processingCount.value;
                  if (q == 0 && p == 0) return const SizedBox.shrink();
                  return LinearProgressIndicator(
                    value: p > 0 ? null : 0,
                    minHeight: 2,
                  );
                }),
                Expanded(
                  child: ListView.builder(
                    itemCount: _articles.length,
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return Dismissible(
                        key: ValueKey(article.entryId),
                        direction: DismissDirection.horizontal,
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            // 右滑 = 保留
                            _keep(article);
                          } else {
                            // 左滑 = 拒绝
                            _reject(article);
                          }
                          return false; // 手动管理移除
                        },
                        background: Container(
                          color: Colors.green.withValues(alpha: 0.3),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 24),
                          child: const Icon(Icons.undo, color: Colors.green),
                        ),
                        secondaryBackground: Container(
                          color: Colors.grey.withValues(alpha: 0.3),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline,
                              color: Colors.grey),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                              child: ArticleCard(
                                article: article,
                                showFeedTitle: true,
                                onTap: () {
                                  Get.toNamed(Routes.article, arguments: {
                                    'article': article,
                                    'sequence': _articles,
                                    'index': index,
                                  });
                                },
                              ),
                            ),
                            // 拒绝原因标签
                            if (article.filterReason != null &&
                                article.filterReason!.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                    12, 0, 12, 8),
                                child: Text(
                                  'AI 判定: ${article.filterReason}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
