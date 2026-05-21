import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/constants/constants.dart';
import '../../common/widgets/loading_widget.dart';
import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../models/feed.dart';
import '../../router/app_pages.dart';
import '../../utils/source_taxonomy.dart';
import '../../common/widgets/feedback_toast.dart';
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

  void _refreshFromLocal() {
    final local = LocalArticleDbService.readAllArticles()
        .where(_matchesScope)
        .toList();
    final kept = _mergeLocalReadState(local);
    articles.value = kept.where((a) => !a.isRead).toList();
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
    if (cachedArticles.isNotEmpty) {
      final mergedCached = _mergeLocalReadState(cachedArticles);
      articles.value = mergedCached;
      loadingState.value = Success(mergedCached);
    } else if (!hasInitialContent) {
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

/// Feed 详情页
class FeedDetailPage extends StatelessWidget {
  const FeedDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(FeedDetailController());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.feedImage != null &&
                controller.feedImage!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image(
                    image: CachedNetworkImageProvider(
                      ArticleImageService.toProxiedUrl(
                            controller.feedImage,
                          ) ??
                          controller.feedImage!,
                    ),
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            Flexible(
              child: Obx(() {
                final unreadCount = controller.articles
                    .where((a) => !a.isRead)
                    .length;
                return Text(
                  unreadCount > 0
                      ? '${controller.feedTitle} ($unreadCount)'
                      : controller.feedTitle,
                  overflow: TextOverflow.ellipsis,
                );
              }),
            ),
          ],
        ),
        scrolledUnderElevation: 1,
        actions: [
          if (controller.filterFeedId != null)
            Obx(() {
              final isEnabled = controller.isAutoTranslateEnabled.value;
              return IconButton(
                icon: Icon(
                  isEnabled ? Icons.translate : Icons.translate_outlined,
                  color: isEnabled ? Theme.of(context).primaryColor : null,
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
        ],
      ),
      body: Obx(() {
        final state = controller.loadingState.value;

        return switch (state) {
          Loading() => const LoadingWidget(msg: '加载中...'),
          LoadError(:final errMsg) => _ErrorView(
            message: errMsg,
            onRetry: controller.loadData,
          ),
          Success(:final response) when response.isEmpty => _EmptyView(
            onRetry: controller.loadData,
          ),
          Success(:final response) => RefreshIndicator(
            onRefresh: controller.loadData,
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: response.length,
              itemBuilder: (context, index) {
                final article = response[index];
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
          ),
        };
      }),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message ?? '加载失败',
              style: TextStyle(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback? onRetry;

  const _EmptyView({this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '该订阅源暂无未读文章',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 16,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('刷新')),
            ],
          ],
        ),
      ),
    );
  }
}
