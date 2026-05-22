import 'dart:ui';
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
    // 注册增量推送回调
    AutoFilterWorker.onRejected = (entryId, title, reason) {
      if (!mounted) return;
      if (_seenIds.contains(entryId)) return;
      _seenIds.add(entryId);
      // 从 DB 或内存中获取完整 article
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

  // 恢复 (Keep)
  void _keep(ArticleModel article) {
    ArticleStateNotifier.tick(article.entryId);
    AutoFilterWorker.unReject(article.entryId);
    AutoFilterWorker.unReject(article.entryId); // 冗余调用以确保状态更新
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
    }
    setState(() => _articles.removeWhere((a) => a.entryId == article.entryId));
  }

  // 彻底拒绝 (Reject)
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
    ArticleStateNotifier.tick(article.entryId);
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
        centerTitle: true,
        backgroundColor: cs.surface.withValues(alpha: 0.7),
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: const Text('垃圾拦截'),
        actions: [
          Obx(() {
            final q = AutoFilterWorker.queuedCount.value;
            final p = AutoFilterWorker.processingCount.value;
            if (q == 0 && p == 0) return const SizedBox.shrink();
            
            return Center(
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '判定中 ${q + p}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
      body: Obx(() => _articles.isEmpty
          ? _buildEmptyState(cs)
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
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  );
                }),
                Expanded(
                  child: ListView.builder(
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
                            // 右滑 = 恢复 (Keep)
                            _keep(article);
                          } else {
                            // 左滑 = 彻底拒绝 (Reject)
                            _reject(article);
                          }
                          return false; // 手动管理数组移除并利用 setState 刷新
                        },
                        // 右滑背景（恢复文章）
                        background: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              color: const Color(0xFF10B981), // 生机绿
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 24),
                              child: const Icon(Icons.restore_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                        ),
                        // 左滑背景（彻底删除）
                        secondaryBackground: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              color: cs.error, // 警告红
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                        ),
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
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  // 统一的优雅空状态
  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shield_outlined,
                size: 56,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '非常清爽',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前没有待审核的垃圾文章\nAI 过滤系统正在默默守护你的阅读流',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            Obx(() {
              final q = AutoFilterWorker.queuedCount.value;
              final p = AutoFilterWorker.processingCount.value;
              if (q > 0 || p > 0) {
                return Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '后台正在判定: $q 排队, $p 处理中',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }
}