import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/constants/constants.dart';
import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../models/feed.dart';
import '../../router/app_pages.dart';
import '../../utils/source_taxonomy.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/refresh_indicator.dart' as custom_refresh;
import '../../services/account_service.dart';
import '../../services/article_image_service.dart';
import '../../services/content_cache_service.dart';
import '../../services/local_article_db_service.dart';
import '../../services/auto_translation_worker.dart';
import '../../services/auto_summary_worker.dart';
import '../../services/auto_filter_worker.dart';
import '../../services/article_state_notifier.dart';
import '../../services/read_sync_service.dart';
import '../../services/feed_translation_settings_service.dart';
import '../../utils/storage.dart';
import '../widgets/article_card.dart';
import '../timeline/timeline_controller.dart';
import '../subscriptions/subscriptions_controller.dart';

/// Feed 详情控制器 — 按订阅源或分类或 view 筛选文章
class FeedDetailController extends GetxController {
  final loadingState = Rx<LoadingState<List<ArticleModel>>>(const Loading());

  late final String feedTitle;
  late final String? filterFeedId;
  late final String? filterCategory;
  late final int? filterView;
  late final String? feedImage;
  late final String _cacheScope;
  final Map<String, FeedModel> _feedMap = {};
  bool _feedsLoaded = false;
  bool _isRefreshingRecentRead = false;

  final articles = <ArticleModel>[].obs;
  final isAutoTranslateEnabled = false.obs;
  final readFilter = 0.obs; // 0=未读, 1=全部, 2=已读
  final allArticles = <ArticleModel>[].obs; // 全量（含已读）

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>;
    filterFeedId = args['feedId'] as String?;
    filterCategory = args['category'] as String?;
    filterView = args['view'] as int?;
    feedImage = args['feedImage'] as String?;
    feedTitle =
        (args['feedTitle'] as String?) ??
        (args['categoryName'] as String?) ??
        (args['viewName'] as String?) ??
        '';
    _cacheScope = filterFeedId ??
        'category:${filterCategory ?? 'view:${filterView ?? 'all'}'}';
    refreshAutoTranslateStatus();
    loadData();
    ever(ArticleStateNotifier.version, (_) => _refreshFromLocal());
  }

  void _applyFilter() {
    switch (readFilter.value) {
      case 0:
        articles.value = allArticles.where((a) => !a.isRead && !a.isRejectedByAi).toList();
      case 1:
        articles.value = allArticles.where((a) => !a.isRejectedByAi).toList();
      case 2:
        articles.value = allArticles.where((a) => a.isRead && !a.isRejectedByAi).toList();
    }
  }

  void _refreshFromLocal() {
    final eid = ArticleStateNotifier.lastEntryId;
    if (eid == null) return;
    // 增量：读单篇
    final raw = GStorage.articleDb.get(eid);
    if (raw is! Map) return;
    final article = ArticleModel.fromCache(Map<String, dynamic>.from(raw));
    if (!_matchesScope(article)) return;

    // 替换或移除列表中的该篇
    final idx = articles.indexWhere((a) => a.entryId == eid);
    if (article.isRead) {
      if (idx >= 0) articles.removeAt(idx);
    } else {
      final merged = _mergeLocalReadState([article]).first;
      // 同步更新 allArticles
      final ai = allArticles.indexWhere((a) => a.entryId == eid);
      if (ai >= 0) {
        allArticles[ai] = merged;
        allArticles.refresh();
      } else {
        allArticles.add(merged);
      }
      _applyFilter();
    }
  }

  void refreshAutoTranslateStatus() {
    final feedId = filterFeedId;
    if (feedId == null || feedId.isEmpty) {
      isAutoTranslateEnabled.value = false;
      return;
    }
    isAutoTranslateEnabled.value =
        FeedTranslationSettingsService.isAutoTranslateEnabled(feedId);
  }

  Future<void> loadData() async {
    if (!AccountService.instance.isLoggedIn.value) {
      loadingState.value = const LoadError('请先在“设置”页配置 Folo Token');
      articles.clear();
      return;
    }

    unawaited(ReadSyncService.syncPendingReads());
    final localSnapshot = _buildInitialLocalSnapshot();
    final memorySnapshot = _buildInitialTimelineSnapshot();
    final initialSnapshot = localSnapshot.isNotEmpty
        ? localSnapshot
        : memorySnapshot;
    final hasInitialContent = initialSnapshot.isNotEmpty;
    if (hasInitialContent) {
      articles.value = initialSnapshot;
      loadingState.value = Success(initialSnapshot);
    }

    final cachedArticles = ContentCacheService.readFeedDetailArticles(
      _cacheScope,
    );
    if (!hasInitialContent && cachedArticles.isNotEmpty) {
      final mergedCached = _mergeLocalReadState(cachedArticles);
      allArticles.value = mergedCached;
      _applyFilter();
      loadingState.value = Success(articles.toList());
    } else if (!hasInitialContent && cachedArticles.isEmpty) {
      if (_hasAnyLocalScopeData() || _isTimelineSnapshotReady()) {
        articles.clear();
        loadingState.value = const Success(<ArticleModel>[]);
      } else {
        loadingState.value = const Loading();
      }
    }

    if (!_feedsLoaded) {
      final cachedFeeds = ContentCacheService.readSubscriptions();
      final cachedInboxFeeds = cachedFeeds
          .where((feed) => feed.isInbox)
          .toList();
      for (final feed in cachedFeeds) {
        _feedMap[feed.feedId] = feed;
      }

      final needRefresh =
          _feedMap.isEmpty || !ContentCacheService.isSubscriptionsFresh();
      if (needRefresh) {
        final feedResult = await FeedHttp.getSubscriptions();
        if (feedResult is Success<List<FeedModel>>) {
          final merged = <FeedModel>[
            ...feedResult.response,
            ...cachedInboxFeeds,
          ];
          for (final f in merged) {
            _feedMap[f.feedId] = f;
          }
          ContentCacheService.saveSubscriptions(merged);
        }
      }
      _feedsLoaded = true;
    }

    final unreadResult = await FeedHttp.collectEntries(
      view: 0,
      withContent: true,
      feedMap: _feedMap,
    );

    if (unreadResult is LoadError<List<ArticleModel>>) {
      if (!hasInitialContent && cachedArticles.isEmpty) {
        loadingState.value = unreadResult;
      }
      return;
    }

    final unreadData = unreadResult is Success<List<ArticleModel>>
        ? unreadResult.response
        : <ArticleModel>[];

    final socialResult = await FeedHttp.collectEntries(
      view: 1,
      withContent: true,
      feedMap: _feedMap,
    );

    if (socialResult is Success<List<ArticleModel>>) {
      unreadData.addAll(socialResult.response);
    }

    final inboxResult = await FeedHttp.collectAllInboxEntries(
      limit: 100,
      withContent: true,
    );

    if (inboxResult is Success<List<ArticleModel>>) {
      unreadData.addAll(inboxResult.response);
    }

    final filteredUnread = unreadData.where(_matchesScope).toList();
    _applyUnreadSnapshot(filteredUnread);

    final merged = _mergeLocalReadState(
      filteredUnread,
    ).where((article) => !article.isRead).toList();
    articles.value = merged;
    loadingState.value = Success(merged);
    ContentCacheService.saveFeedDetailArticles(_cacheScope, merged);
    // allArticles 包含已读（供筛选用）
    final all = LocalArticleDbService.readAllArticles()
        .where(_matchesScope)
        .toList();
    allArticles.value = _mergeLocalReadState(all);
    _applyFilter();
    // 全量同步完成后，强制通知订阅列表做全量重新计数，保证数字一致
    if (Get.isRegistered<SubscriptionsController>()) {
      Get.find<SubscriptionsController>().refreshUnreadCounts();
    }
    unawaited(_refreshRecentReadWindow());
  }

  List<ArticleModel> _buildInitialLocalSnapshot() {
    final localArticles = LocalArticleDbService.readAllArticles()
        .where(_matchesScope)
        .toList();
    if (localArticles.isEmpty) return const [];

    return _mergeLocalReadState(
      localArticles,
    ).where((article) => !article.isRead).toList();
  }

  List<ArticleModel> _buildInitialTimelineSnapshot() {
    if (!Get.isRegistered<TimelineController>()) return const [];
    final timeline = Get.find<TimelineController>();
    if (timeline.allArticles.isEmpty) return const [];
    return timeline.allArticles
        .where(_matchesScope)
        .where((article) => !article.isRead)
        .toList();
  }

  bool _hasAnyLocalScopeData() {
    return LocalArticleDbService.readAllArticles().any(_matchesScope);
  }

  bool _isTimelineSnapshotReady() {
    if (!Get.isRegistered<TimelineController>()) return false;
    final timeline = Get.find<TimelineController>();
    return timeline.loadingState.value is Success<List<ArticleModel>>;
  }

  int get _readSyncWindowDays {
    final raw = GStorage.setting.get(
      StorageKeys.readSyncWindowDays,
      defaultValue: AppConstants.defaultReadSyncWindowDays,
    );
    if (raw is int && raw > 0) return raw;
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) return parsed;
    }
    return AppConstants.defaultReadSyncWindowDays;
  }

  bool _matchesScope(ArticleModel article) {
    if (filterFeedId != null) {
      return article.feedId == filterFeedId;
    }
    if (filterCategory != null) {
      return article.subscriptionCategory == filterCategory;
    }
    if (filterView != null) {
      return article.category == SourceTaxonomy.viewKeyFromInt(filterView);
    }
    return true;
  }

  void _applyUnreadSnapshot(List<ArticleModel> unreadData) {
    final unreadIds = unreadData.map((a) => a.entryId).toSet();
    final localArticles = LocalArticleDbService.readAllArticles()
        .where(_matchesScope)
        .toList();
    for (final local in localArticles) {
      if (unreadIds.contains(local.entryId)) continue;
      final localOverride = LocalArticleDbService.readOverrideOf(local.entryId);
      if (localOverride == false) continue;
      GStorage.readStatus.put(local.entryId, true);
      LocalArticleDbService.setReadState(local.entryId, true);
    }

    // UPSERT NEW ARTICLES
    LocalArticleDbService.upsertMany(unreadData, defaultReadState: false);

    // API 返回未读 → 清除本地旧已读标记
    for (final article in unreadData) {
      final stale = GStorage.readStatus.get(article.entryId);
      if (stale == true) {
        GStorage.readStatus.delete(article.entryId);
      }
    }

    LocalArticleDbService.upsertMany(unreadData, defaultReadState: false);
    AutoFilterWorker.enqueueMany(unreadData);
    AutoTranslationWorker.enqueueIfEnabledMany(unreadData);
    AutoSummaryWorker.enqueueIfNeededMany(unreadData);
  }

  Future<void> _refreshRecentReadWindow() async {
    if (_isRefreshingRecentRead || !AccountService.instance.isLoggedIn.value) {
      return;
    }
    _isRefreshingRecentRead = true;

    try {
      final windowStart = DateTime.now().subtract(
        Duration(days: _readSyncWindowDays),
      );
      final feedsReadResult = await FeedHttp.collectEntries(
        view: 0,
        read: true,
        withContent: true,
        publishedAfter: windowStart.toUtc().toIso8601String(),
        feedMap: _feedMap,
      );

      final socialReadResult = await FeedHttp.collectEntries(
        view: 1,
        read: true,
        withContent: true,
        publishedAfter: windowStart.toUtc().toIso8601String(),
        feedMap: _feedMap,
      );

      final readData = <ArticleModel>[];
      if (feedsReadResult is Success<List<ArticleModel>>) {
        readData.addAll(feedsReadResult.response);
      }
      if (socialReadResult is Success<List<ArticleModel>>) {
        readData.addAll(socialReadResult.response);
      }

      final scopedReadData = readData.where(_matchesScope).toList();
      if (scopedReadData.isEmpty) {
        AppFeedback.info('已同步已读', '最近$_readSyncWindowDays天没有新增已读文章');
        return;
      }

      LocalArticleDbService.upsertMany(scopedReadData, defaultReadState: true);
      final merged = LocalArticleDbService.readAllArticles()
          .where(_matchesScope)
          .where((article) => !article.isRead)
          .toList();
      articles.value = merged;
      loadingState.value = Success(merged);
      ContentCacheService.saveFeedDetailArticles(_cacheScope, merged);

      final earliest = scopedReadData
          .map((article) => DateTime.tryParse(article.publishedAt))
          .whereType<DateTime>()
          .toList();
      if (earliest.isNotEmpty) {
        earliest.sort();
        final timeText = DateFormat(
          'MM-dd HH:mm',
        ).format(earliest.first.toLocal());
        AppFeedback.success('已同步已读', '最早文章：$timeText');
      } else {
        AppFeedback.success('已同步已读', '最近$_readSyncWindowDays天已同步完成');
      }
    } finally {
      _isRefreshingRecentRead = false;
    }
  }

  List<ArticleModel> _mergeLocalReadState(List<ArticleModel> source) {
    return source.map((a) {
      final localRead = LocalArticleDbService.readOverrideOf(a.entryId);
      if (localRead != null) {
        return ArticleModel(
          entryId: a.entryId,
          feedId: a.feedId,
          feedTitle: a.feedTitle,
          feedImage: a.feedImage,
          title: a.title,
          url: a.url,
          content: a.content,
          publishedAt: a.publishedAt,
          isRead: localRead,
          category: a.category,
          subscriptionCategory: a.subscriptionCategory,
          author: a.author,
          imageUrl: a.imageUrl,
          isRejectedByAi: a.isRejectedByAi,
          filterReason: a.filterReason,
          filterReviewed: a.filterReviewed,
        );
      }
      return a;
    }).toList();
  }
}

/// Feed 详情页 (沉浸式重构版)
class FeedDetailPage extends StatelessWidget {
  const FeedDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(FeedDetailController());
    final cs = Theme.of(context).colorScheme;

    // 解析安全的头像链接
    final safeImageUrl = controller.feedImage != null &&
            controller.feedImage!.isNotEmpty
        ? (ArticleImageService.toProxiedUrl(controller.feedImage) ??
            controller.feedImage)
        : null;

    return Scaffold(
      body: custom_refresh.RefreshIndicator(
        displacement: MediaQuery.paddingOf(context).top + kToolbarHeight + 10,
        onRefresh: controller.loadData,
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ─── 杂志级沉浸式头部 ───
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              stretch: true,
              backgroundColor: Colors.transparent, // 必须透明，靠内部的 BackdropFilter 呈现毛玻璃
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              iconTheme: IconThemeData(color: cs.onSurface),
              actionsIconTheme: IconThemeData(color: cs.onSurface),
              flexibleSpace: Stack(
                fit: StackFit.expand,
                children: [
                  // Persistent Glassmorphism Base
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: Container(
                        color: cs.surface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 48, right: 48, bottom: 16),
                    centerTitle: true,
                    title: Text(
                      controller.feedTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. 底层背景图：抓取源图片或者使用主题色填充
                        if (safeImageUrl != null)
                          CachedNetworkImage(
                            imageUrl: safeImageUrl,
                            fit: BoxFit.cover,
                          )
                        else
                          Container(color: cs.primaryContainer),

                        // 2. 极致的高斯模糊与表面色彩融合（Glassmorphism）
                        // 既能保留原图的色彩分布，又绝对保证文字的对比度可读性
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                          child: Container(
                            color: cs.surface.withValues(alpha: 0.85),
                          ),
                        ),

                        // 3. 居中大头像展示区（向上滚动时会自动淡出）
                        Positioned(
                          top: MediaQuery.of(context).padding.top + kToolbarHeight + 10,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.surface,
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.15),
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                image: safeImageUrl != null
                                    ? DecorationImage(
                                        image: CachedNetworkImageProvider(safeImageUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: safeImageUrl == null
                                  ? Icon(Icons.rss_feed, size: 32, color: cs.primary)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    collapseMode: CollapseMode.pin,
                  ),
                ],
              ),
              actions: [
                // Unread Count Badge
                Obx(() {
                  final unreadCount = controller.articles.where((a) => !a.isRead).length;
                  if (unreadCount == 0) return const SizedBox.shrink();
                  return Center(
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        unreadCount.toString(),
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }),
                // 已读筛选
                Obx(() => PopupMenuButton<int>(
                      tooltip: '筛选文章状态',
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      icon: Icon(
                        controller.readFilter.value == 0
                            ? Icons.mark_email_unread_outlined
                            : controller.readFilter.value == 1
                                ? Icons.inbox
                                : Icons.done_all,
                        size: 22,
                        color: cs.onSurfaceVariant,
                      ),
                      onSelected: (v) {
                        controller.readFilter.value = v;
                        controller._applyFilter();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 0, child: Text('仅未读')),
                        const PopupMenuItem(value: 1, child: Text('全部')),
                        const PopupMenuItem(value: 2, child: Text('仅已读')),
                      ],
                    )),
                // 自动翻译
                if (controller.filterFeedId != null)
                  Obx(() {
                    final isEnabled = controller.isAutoTranslateEnabled.value;
                    return IconButton(
                      icon: Icon(
                        isEnabled ? Icons.translate : Icons.translate_outlined,
                        color: isEnabled ? cs.primary : cs.onSurfaceVariant,
                      ),
                      tooltip: isEnabled ? '自动翻译已启用' : '启用自动翻译',
                      onPressed: () async {
                        await FeedTranslationSettingsService.toggleAutoTranslate(
                          controller.filterFeedId ?? '',
                        );
                        controller.refreshAutoTranslateStatus();
                        AppFeedback.success(
                          isEnabled ? '自动翻译已关闭' : '自动翻译已开启',
                          '仅对当前订阅源生效',
                        );
                      },
                    );
                  }),
                const SizedBox(width: 8),
              ],
            ),

            // ─── 文章列表区域 ───
            Obx(() {
              final state = controller.loadingState.value;

              return switch (state) {
                Loading() => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _FeedDetailSkeleton(),
                  ),
                LoadError(:final errMsg) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorView(
                      message: errMsg,
                      onRetry: controller.loadData,
                    ),
                  ),
                Success(:final response) when response.isEmpty =>
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyView(
                      onRetry: controller.loadData,
                      readFilter: controller.readFilter.value,
                    ),
                  ),
                Success() => Obx(() {
                    final list = controller.articles;
                    if (list.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyView(
                          onRetry: controller.loadData,
                          readFilter: controller.readFilter.value,
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: EdgeInsets.only(
                        top: 6,
                        bottom: 16 + MediaQuery.of(context).padding.bottom,
                      ),
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final article = list[index];
                          return ArticleCard(
                            article: article,
                            showFeedTitle: true,
                            onTap: () {
                              Get.toNamed(
                                Routes.article,
                                arguments: {
                                  'article': article,
                                  'sequence': controller.articles.toList(),
                                  'index': index,
                                },
                              );
                            },
                          );
                        },
                      ),
                    );
                  }),
              };
            }),
          ],
        ),
      ),
    );
  }
}

// ─── 优雅的局部状态视图 ───

class _FeedDetailSkeleton extends StatefulWidget {
  const _FeedDetailSkeleton();

  @override
  State<_FeedDetailSkeleton> createState() => _FeedDetailSkeletonState();
}

class _FeedDetailSkeletonState extends State<_FeedDetailSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacityAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 6),
      itemCount: 4,
      itemBuilder: (context, index) {
        return FadeTransition(
          opacity: _opacityAnim,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: MediaQuery.of(context).size.width * 0.6,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 64,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _ErrorView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 48, color: colorScheme.error),
            ),
            const SizedBox(height: 24),
            Text(
              '数据加载异常',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? '请检查网络连接后重试',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新加载'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback? onRetry;
  final int readFilter;

  const _EmptyView({this.onRetry, required this.readFilter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUnread = readFilter == 0;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isUnread ? Icons.done_all_rounded : Icons.inbox_outlined,
                size: 56,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isUnread ? '全部读完啦' : '暂无文章',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isUnread ? '该订阅源暂无最新的未读文章\n你可以尝试下拉刷新获取最新内容' : '该分类下暂时没有符合条件的文章',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('强制同步'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}