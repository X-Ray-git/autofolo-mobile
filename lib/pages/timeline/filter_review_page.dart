import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../services/auto_filter_worker.dart';
import '../../services/article_state_notifier.dart';
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
    AutoFilterWorker.onRejected = (entryId, title, reason) {
      if (!mounted) return;
      if (_seenIds.contains(entryId)) return;
      _seenIds.add(entryId);
      final raw = GStorage.articleDb.get(entryId);
      if (raw is Map) {
        final article = ArticleModel.fromCache(Map<String, dynamic>.from(raw));
        if (article.isRejectedByAi && !article.isRead) {
          _articles.add(article);
        }
      }
    };
  }

  @override
  void deactivate() {
    AutoFilterWorker.onRejected = null;
    super.deactivate();
  }

  @override
  void dispose() {
    AutoFilterWorker.onRejected = null;
    super.dispose();
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

  void _keep(ArticleModel article) {
    ArticleStateNotifier.tick(article.entryId);
    AutoFilterWorker.unReject(article.entryId);
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
    }
    setState(() => _articles.removeWhere((a) => a.entryId == article.entryId));
  }

  void _reject(ArticleModel article) {
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
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsReadLocal(article.entryId);
    } else {
      GStorage.readStatus.put(article.entryId, true);
      LocalArticleDbService.setReadState(article.entryId, true);
    }
    ReadSyncService.enqueue(article.entryId,
        isInbox: article.category == 'inbox');
    ArticleStateNotifier.tick(article.entryId);
    setState(() => _articles.removeWhere((a) => a.entryId == article.entryId));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5),
        ),
        title: Obx(() {
          final humanCount = _articles.length;
          final q = AutoFilterWorker.queuedCount.value;
          final p = AutoFilterWorker.processingCount.value;
          final llmActive = q > 0 || p > 0;
          final llmCount = q + p;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('垃圾拦截',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (humanCount > 0 || llmActive)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (humanCount > 0) ...[
                        Icon(Icons.touch_app, size: 12, color: cs.primary),
                        const SizedBox(width: 4),
                        Text('$humanCount 篇待处理',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: cs.primary)),
                      ],
                      if (humanCount > 0 && llmActive)
                        Text('  ·  ',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      if (llmActive) ...[
                        SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.onSurfaceVariant)),
                        const SizedBox(width: 4),
                        Text('$llmCount 篇判定中',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
            ],
          );
        }),
      ),
      body: Obx(() {
        final humanCount = _articles.length;
        final q = AutoFilterWorker.queuedCount.value;
        final p = AutoFilterWorker.processingCount.value;
        final llmActive = q > 0 || p > 0;

        return Column(
          children: [
            Expanded(
              child: _articles.isEmpty
                  ? _buildEmptyState(cs, llmActive: llmActive, llmCount: q + p)
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        top: 6,
                        bottom: 16 + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: _articles.length,
                      itemBuilder: (context, index) {
                        final article = _articles[index];
                        return Dismissible(
                          key: ValueKey(article.entryId),
                          direction: DismissDirection.horizontal,
                          dismissThresholds: const {
                            DismissDirection.startToEnd: 0.35,
                            DismissDirection.endToStart: 0.35,
                          },
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.startToEnd) {
                              _keep(article);
                            } else {
                              _reject(article);
                            }
                            return false;
                          },
                          background: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                color: const Color(0xFF10B981),
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 24),
                                child: const Icon(Icons.restore_rounded,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                          secondaryBackground: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                color: cs.error,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                child: const Icon(Icons.delete_sweep_rounded,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                          child: ArticleCard(
                            article: article,
                            showFeedTitle: true,
                            showSummary: true,
                            onTap: () {
                              Get.toNamed(Routes.article, arguments: {
                                'article': article,
                                'sequence': _articles,
                                'index': index,
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildEmptyState(ColorScheme cs,
      {required bool llmActive, required int llmCount}) {
    final bool allDone = !llmActive;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: allDone
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : cs.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              allDone ? Icons.check_circle_outline : Icons.shield_outlined,
              size: 56,
              color: allDone ? const Color(0xFF10B981) : cs.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(allDone ? '处理完毕' : '暂无待处理内容',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          if (llmActive)
            _LlmPill(cs: cs, count: llmCount)
          else
            Text(
                allDone
                    ? '所有文章已审核，阅读流保持清爽'
                    : 'AI 过滤系统正在默默守护你的阅读流',
                style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                    height: 1.6),
                textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ── 状态药片行 ──────────
class _LlmPill extends StatelessWidget {
  final ColorScheme cs;
  final int count;

  const _LlmPill({required this.cs, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: cs.onSurfaceVariant)),
        const SizedBox(width: 6),
        Text('$count 篇判定中',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
