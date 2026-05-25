import 'dart:async';

import 'package:intl/intl.dart';
import 'package:get/get.dart';
import '../../common/widgets/app_badger.dart';

import '../../common/constants/constants.dart';
import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../models/feed.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../services/account_service.dart';
import '../../services/content_cache_service.dart';
import '../../services/local_article_db_service.dart';
import '../../services/auto_readability_worker.dart';
import '../../services/article_state_notifier.dart';
import '../../services/read_sync_service.dart';
import '../../utils/storage.dart';
import '../subscriptions/subscriptions_controller.dart';

enum TimelineViewMode { unread, all, read }

/// 时间线控制器 — 本地文章库（未读/全部/已读）
class TimelineController extends GetxController {
  final loadingState = Rx<LoadingState<List<ArticleModel>>>(const Loading());
  final articles = <ArticleModel>[].obs;
  final allArticles = <ArticleModel>[].obs;
  final selectedMode = TimelineViewMode.unread.obs;
  final filterCount = 0.obs;

  String? _cursor;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isRefreshingRecentRead = false;

  final Map<String, FeedModel> _feedMap = {};
  bool _feedsLoaded = false;
  Future<void> Function()? _scrollToTopHandler;

  @override
  void onInit() {
    super.onInit();
    ever(allArticles, (_) => _updateAppBadge());
    loadFeedsThenArticles();
  }

  /// 先加载订阅源映射，再加载文章
  Future<void> loadFeedsThenArticles() async {
    if (!AccountService.instance.isLoggedIn.value) {
      articles.clear();
      loadingState.value = const LoadError('请先在“设置”页配置 Folo Token');
      return;
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

    await loadData();
  }

  Future<void> loadData() async {
    _cursor = null;
    _hasMore = false;

    unawaited(ReadSyncService.syncPendingReads());
    _loadFromLocalDatabase();
    if (allArticles.isEmpty) {
      loadingState.value = const Loading();
    }

    final results = await Future.wait([
      FeedHttp.collectEntries(
        view: 0,
        withContent: true,
        feedMap: _feedMap,
      ),
      FeedHttp.collectEntries(
        view: 1,
        withContent: true,
        feedMap: _feedMap,
      ),
      FeedHttp.collectAllInboxEntries(
        limit: 100,
        withContent: true,
      ),
    ]);

    final feedsResult = results[0];
    final socialResult = results[1];
    final inboxResult = results[2];

    final unreadData = <ArticleModel>[];
    bool hasError = false;

    if (feedsResult is Success<List<ArticleModel>>) {
      unreadData.addAll(feedsResult.response);
    } else if (feedsResult is LoadError<List<ArticleModel>>) {
      hasError = true;
      if (allArticles.isEmpty) loadingState.value = feedsResult;
    }

    if (socialResult is Success<List<ArticleModel>>) {
      unreadData.addAll(socialResult.response);
    } else if (socialResult is LoadError<List<ArticleModel>>) {
      hasError = true;
    }

    if (inboxResult is Success<List<ArticleModel>>) {
      unreadData.addAll(inboxResult.response);
    } else if (inboxResult is LoadError<List<ArticleModel>>) {
      hasError = true;
    }

    if (hasError && allArticles.isNotEmpty) {
      AppFeedback.error('同步未完成', '部分未读数据拉取失败，请稍后重试');
    }

    final feedsOk = feedsResult is Success<List<ArticleModel>>;
    final socialOk = socialResult is Success<List<ArticleModel>>;
    final inboxOk = inboxResult is Success<List<ArticleModel>>;

    _applyUnreadSnapshot(unreadData,
        feedsOk: feedsOk, socialOk: socialOk, inboxOk: inboxOk);
    _loadFromLocalDatabase();

    loadingState.value = Success(articles.toList());
    // 全量同步完成后，强制通知订阅列表做全量重新计数
    if (Get.isRegistered<SubscriptionsController>()) {
      Get.find<SubscriptionsController>().refreshUnreadCounts();
    }
    unawaited(_refreshRecentReadWindow());
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

  void _applyUnreadSnapshot(List<ArticleModel> unreadData,
      {bool feedsOk = true, bool socialOk = true, bool inboxOk = true}) {
    final unreadIds = unreadData.map((a) => a.entryId).toSet();
    final localArticles = LocalArticleDbService.readAllArticles();

    for (final local in localArticles) {
      if (unreadIds.contains(local.entryId)) continue;

      // 按文章类型独立判定：对应 API 失败则跳过，不误标记
      if (local.category == 'inbox' && !inboxOk) continue;
      if (local.category == 'social' && !socialOk) continue;
      // feeds 文章：feeds API 是主数据源，失败则跳过
      if (!feedsOk && local.category != 'inbox' && local.category != 'social') continue;

      final localOverride = LocalArticleDbService.readOverrideOf(local.entryId);
      if (localOverride == false) {
        // 用户曾标为「未读」，但文章在别处已被读完 → 清除过期覆盖
        GStorage.readStatus.delete(local.entryId);
      }
      // 只更新本地缓存，不创建 readStatus 覆盖（系统推断，非用户操作）
      LocalArticleDbService.setReadState(local.entryId, true);
    }

    // 收集待同步队列 ID，保护用户刚执行的乐观更新不被 API 旧数据覆盖
    final pendingIds = ReadSyncService.pendingReadItems
        .map((item) => item.entryId)
        .toSet();

    // API 返回未读 → 清除本地旧已读标记，实现双向同步
    // 跳过仍在待同步队列中的条目
    for (final article in unreadData) {
      final stale = GStorage.readStatus.get(article.entryId);
      if (stale == true && !pendingIds.contains(article.entryId)) {
        GStorage.readStatus.delete(article.entryId);
      }
    }

    LocalArticleDbService.upsertMany(unreadData, defaultReadState: false);
    AutoReadabilityWorker.enqueueMany(unreadData);
    ContentCacheService.saveTimelineArticles(unreadData);
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

      final readResults = await Future.wait([
        FeedHttp.getEntries(
          view: 0,
          read: true,
          limit: 200,
          withContent: true,
          feedMap: _feedMap,
        ),
        FeedHttp.getEntries(
          view: 1,
          read: true,
          limit: 200,
          withContent: true,
          feedMap: _feedMap,
        ),
      ]);

      final feedsReadResult = readResults[0];
      final socialReadResult = readResults[1];

      final readData = <ArticleModel>[];
      if (feedsReadResult is Success<List<ArticleModel>>) {
        readData.addAll(feedsReadResult.response);
      }
      if (socialReadResult is Success<List<ArticleModel>>) {
        readData.addAll(socialReadResult.response);
      }

      // 本地按窗口过滤（不依赖 API 的 publishedAfter 参数语义）
      final windowedReadData = readData.where((a) {
        final pub = DateTime.tryParse(a.publishedAt);
        return pub != null && pub.isAfter(windowStart);
      }).toList();

      if (windowedReadData.isEmpty) {
        AppFeedback.info('已同步已读', '最近$_readSyncWindowDays天没有新增已读文章');
        return;
      }

      LocalArticleDbService.upsertMany(windowedReadData, defaultReadState: true);
      _loadFromLocalDatabase();

      final earliest = windowedReadData
          .map(_timeScore)
          .whereType<int>()
          .fold<int?>(
            null,
            (min, value) => min == null || value < min ? value : min,
          );
      if (earliest != null && earliest > 0) {
        final timeText = DateFormat(
          'MM-dd HH:mm',
        ).format(DateTime.fromMillisecondsSinceEpoch(earliest).toLocal());
        AppFeedback.success('已同步已读', '最早文章：$timeText');
      } else {
        AppFeedback.success('已同步已读', '最近$_readSyncWindowDays天已同步完成');
      }
    } finally {
      _isRefreshingRecentRead = false;
    }
  }

  int? _timeScore(ArticleModel article) {
    final raw = article.publishedAt.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch;
  }

  /// 加载更多（游标翻页）
  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;
    _isLoadingMore = true;

    final result = await FeedHttp.getEntries(
      view: 0,
      withContent: true,
      publishedAfter: _cursor,
      feedMap: _feedMap,
    );

    if (result is Success<List<ArticleModel>>) {
      final data = result.response;
      if (data.isNotEmpty) {
        _cursor = data.last.publishedAt;
        LocalArticleDbService.upsertMany(_mergeLocalReadState(data));
        _loadFromLocalDatabase();
      }
      _hasMore = data.length >= 50;
    }

    _isLoadingMore = false;
  }

  void setViewMode(TimelineViewMode mode) {
    if (selectedMode.value == mode) return;
    selectedMode.value = mode;
    _applyFilter();
    loadingState.value = Success(articles.toList());
  }

  /// 标记文章为已读（仅本地）
  void markAsReadLocal(String entryId) {
    if (entryId.trim().isEmpty) return;
    GStorage.readStatus.put(entryId, true);
    LocalArticleDbService.setReadState(entryId, true);
    _updateReadStateInMemory(entryId, true);
    ArticleStateNotifier.tick(entryId);
  }

  void markAsUnreadLocal(String entryId) {
    if (entryId.trim().isEmpty) return;
    // 不再写入 readStatus=false；只更新本地缓存，信任服务端为最终权威
    LocalArticleDbService.setReadState(entryId, false);
    _updateReadStateInMemory(entryId, false);
  }

  bool get hasMore => selectedMode.value != TimelineViewMode.read && _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  int get unreadCount => allArticles.where((a) => !a.isRead).length;
  int get readCount => allArticles.where((a) => a.isRead).length;
  int get allCount => allArticles.length;
  
  void _updateAppBadge() {
    final strategy = GStorage.setting.get(
      StorageKeys.badgeStrategy,
      defaultValue: 'unread_count',
    );
    if (strategy == 'off') {
      AppBadger.removeBadge();
      return;
    }
    
    final unread = unreadCount;
    if (unread == 0) {
      AppBadger.removeBadge();
    } else {
      if (strategy == 'dot_only') {
        AppBadger.updateBadgeCount(1);
      } else {
        AppBadger.updateBadgeCount(unread);
      }
    }
  }
  List<ArticleModel> get searchSourceArticles => allArticles;
  String get emptyMessage => switch (selectedMode.value) {
    TimelineViewMode.unread => '没有未读文章',
    TimelineViewMode.all => '本地文章库为空',
    TimelineViewMode.read => '暂无已读文章',
  };

  void bindScrollToTopHandler(Future<void> Function()? handler) {
    _scrollToTopHandler = handler;
  }

  Future<void> scrollToTop() async {
    await _scrollToTopHandler?.call();
  }

  void _loadFromLocalDatabase() {
    final local = LocalArticleDbService.readAllArticles();
    allArticles.value = _mergeLocalReadState(local);
    _applyFilter();
    _updateFilterCount();
    if (allArticles.isNotEmpty ||
        selectedMode.value != TimelineViewMode.unread) {
      loadingState.value = Success(articles.toList());
    }
  }

  void _applyFilter() {
    final mode = selectedMode.value;
    final source = allArticles;
    final filtered = switch (mode) {
      TimelineViewMode.unread => source.where((a) => !a.isRead).toList(),
      TimelineViewMode.read => source.where((a) => a.isRead).toList(),
      TimelineViewMode.all => source.toList(),
    };
    articles.value = filtered;
  }

  void _updateFilterCount() {
    int count = 0;
    for (final a in allArticles) {
      if (a.isRejectedByAi && !a.isRead) count++;
    }
    filterCount.value = count;
  }

  void _updateReadStateInMemory(String entryId, bool isRead) {
    final idx = allArticles.indexWhere((a) => a.entryId == entryId);
    if (idx < 0) return;

    final a = allArticles[idx];
    if (a.isRead == isRead) return;

    final updated = ArticleModel(
      entryId: a.entryId,
      feedId: a.feedId,
      feedTitle: a.feedTitle,
      feedImage: a.feedImage,
      title: a.title,
      url: a.url,
      content: a.content,
      publishedAt: a.publishedAt,
      isRead: isRead,
      category: a.category,
      subscriptionCategory: a.subscriptionCategory,
      author: a.author,
      imageUrl: a.imageUrl,
      isRejectedByAi: a.isRejectedByAi,
      filterReason: a.filterReason,
      filterReviewed: a.filterReviewed,
    );
    allArticles[idx] = updated;
    allArticles.refresh();
    _applyFilter();
    _updateFilterCount();
    loadingState.value = Success(articles.toList());
  }

  List<ArticleModel> _mergeLocalReadState(List<ArticleModel> source) {
    return source.map((a) {
      final readVal = GStorage.readStatus.get(a.entryId);
      if (readVal == true && !a.isRead) {
        return ArticleModel(
          entryId: a.entryId,
          feedId: a.feedId,
          feedTitle: a.feedTitle,
          feedImage: a.feedImage,
          title: a.title,
          url: a.url,
          content: a.content,
          publishedAt: a.publishedAt,
          isRead: true,
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
