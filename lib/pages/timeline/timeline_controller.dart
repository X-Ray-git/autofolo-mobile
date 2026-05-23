import 'dart:async';

import 'package:intl/intl.dart';
import 'package:get/get.dart';

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

    final feedsResult = await FeedHttp.collectEntries(
      view: 0,
      withContent: true,
      feedMap: _feedMap,
    );

    final socialResult = await FeedHttp.collectEntries(
      view: 1,
      withContent: true,
      feedMap: _feedMap,
    );

    final inboxResult = await FeedHttp.collectAllInboxEntries(
      limit: 100,
      withContent: true,
    );

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

    if (unreadData.isNotEmpty || !hasError) {
      _applyUnreadSnapshot(unreadData);
      _loadFromLocalDatabase();
    }

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

  void _applyUnreadSnapshot(List<ArticleModel> unreadData) {
    final unreadIds = unreadData.map((a) => a.entryId).toSet();
    final localArticles = LocalArticleDbService.readAllArticles();
    for (final local in localArticles) {
      if (unreadIds.contains(local.entryId)) continue;
      final localOverride = LocalArticleDbService.readOverrideOf(local.entryId);
      if (localOverride == false) continue;
      GStorage.readStatus.put(local.entryId, true);
      LocalArticleDbService.setReadState(local.entryId, true);
    }

    // API 返回未读 → 清除本地旧已读标记，实现双向同步
    for (final article in unreadData) {
      final stale = GStorage.readStatus.get(article.entryId);
      if (stale == true) {
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

      if (readData.isEmpty) {
        AppFeedback.info('已同步已读', '最近$_readSyncWindowDays天没有新增已读文章');
        return;
      }

      LocalArticleDbService.upsertMany(readData, defaultReadState: true);
      _loadFromLocalDatabase();

      final earliest = readData
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
    GStorage.readStatus.put(entryId, false);
    LocalArticleDbService.setReadState(entryId, false);
    _updateReadStateInMemory(entryId, false);
  }

  bool get hasMore => selectedMode.value != TimelineViewMode.read && _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  int get unreadCount => allArticles.where((a) => !a.isRead).length;
  int get readCount => allArticles.where((a) => a.isRead).length;
  int get allCount => allArticles.length;
  List<ArticleModel> get searchSourceArticles => allArticles.toList();
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

  void _updateReadStateInMemory(String entryId, bool isRead) {
    bool changed = false;
    final updatedAll = allArticles.map((a) {
      if (a.entryId != entryId) return a;
      changed = true;
      return ArticleModel(
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
    }).toList();

    if (changed) {
      allArticles.value = updatedAll;
      _applyFilter();
      loadingState.value = Success(articles.toList());
    }
  }

  List<ArticleModel> _mergeLocalReadState(List<ArticleModel> source) {
    return source.map((a) {
      final readVal = GStorage.readStatus.get(a.entryId);
      if (readVal == true) {
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
