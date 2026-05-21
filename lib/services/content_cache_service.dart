import '../models/article.dart';
import '../models/feed.dart';
import '../utils/storage.dart';

abstract final class ContentCacheService {
  static const Duration _timelineTtl = Duration(minutes: 15);
  static const Duration _subscriptionsTtl = Duration(minutes: 30);
  static const Duration _feedDetailTtl = Duration(minutes: 10);

  static const int _maxTimelineItems = 300;
  static const int _maxFeedDetailItems = 200;

  static const String _timelineKey = 'cache.timeline.articles.v1';
  static const String _timelineAtKey = 'cache.timeline.articles.at';
  static const String _subscriptionsKey = 'cache.subscriptions.v2';
  static const String _subscriptionsAtKey = 'cache.subscriptions.at';

  static List<ArticleModel> readTimelineArticles({bool allowStale = true}) {
    return _readArticles(
      key: _timelineKey,
      atKey: _timelineAtKey,
      ttl: _timelineTtl,
      allowStale: allowStale,
    );
  }

  static void saveTimelineArticles(List<ArticleModel> items) {
    final deduped = _dedupeByEntryId(items).take(_maxTimelineItems).toList();
    _writeArticles(key: _timelineKey, atKey: _timelineAtKey, items: deduped);
  }

  static List<FeedModel> readSubscriptions({bool allowStale = true}) {
    if (!allowStale && !_isFresh(_subscriptionsAtKey, _subscriptionsTtl)) {
      return const [];
    }

    final raw = GStorage.localCache.get(_subscriptionsKey);
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((e) => FeedModel.fromCache(Map<String, dynamic>.from(e)))
        .toList();
  }

  static void saveSubscriptions(List<FeedModel> items) {
    GStorage.localCache.put(
      _subscriptionsKey,
      items.map((e) => e.toJson()).toList(),
    );
    GStorage.localCache.put(
      _subscriptionsAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static List<ArticleModel> readFeedDetailArticles(
    String cacheScope, {
    bool allowStale = true,
  }) {
    return _readArticles(
      key: 'cache.feed-detail.$cacheScope.articles.v1',
      atKey: 'cache.feed-detail.$cacheScope.at',
      ttl: _feedDetailTtl,
      allowStale: allowStale,
    );
  }

  static void saveFeedDetailArticles(
    String cacheScope,
    List<ArticleModel> items,
  ) {
    final deduped = _dedupeByEntryId(items).take(_maxFeedDetailItems).toList();
    _writeArticles(
      key: 'cache.feed-detail.$cacheScope.articles.v1',
      atKey: 'cache.feed-detail.$cacheScope.at',
      items: deduped,
    );
  }

  static bool isSubscriptionsFresh() =>
      _isFresh(_subscriptionsAtKey, _subscriptionsTtl);

  static bool _isFresh(String atKey, Duration ttl) {
    final ts = GStorage.localCache.get(atKey);
    if (ts is! int || ts <= 0) return false;
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now().difference(cachedAt) <= ttl;
  }

  static List<ArticleModel> _readArticles({
    required String key,
    required String atKey,
    required Duration ttl,
    required bool allowStale,
  }) {
    if (!allowStale && !_isFresh(atKey, ttl)) {
      return const [];
    }

    final raw = GStorage.localCache.get(key);
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((e) => ArticleModel.fromCache(Map<String, dynamic>.from(e)))
        .toList();
  }

  static void _writeArticles({
    required String key,
    required String atKey,
    required List<ArticleModel> items,
  }) {
    GStorage.localCache.put(key, items.map((e) => e.toJson()).toList());
    GStorage.localCache.put(atKey, DateTime.now().millisecondsSinceEpoch);
  }

  static List<ArticleModel> _dedupeByEntryId(List<ArticleModel> source) {
    final byId = <String, ArticleModel>{};
    for (final article in source) {
      if (article.entryId.isEmpty) continue;
      byId[article.entryId] = article;
    }
    return byId.values.toList();
  }
}
