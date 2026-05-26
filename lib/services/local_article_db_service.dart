import '../models/article.dart';
import '../utils/storage.dart';

/// 本地文章库（已读/未读统一持久化）
abstract final class LocalArticleDbService {
  static const String _metaPrefix = '__meta__';
  static const int _maxArticles = 5000;

  static List<ArticleModel>? _cachedAllArticles;

  static void invalidateCache() {
    _cachedAllArticles = null;
  }

  static Iterable<String> get _articleKeys {
    return GStorage.articleDb.keys.whereType<String>().where(
      (k) => !k.startsWith(_metaPrefix),
    );
  }

  static List<ArticleModel> readAllArticles() {
    if (_cachedAllArticles != null) {
      return _cachedAllArticles!;
    }
    
    final items = <ArticleModel>[];
    for (final key in _articleKeys) {
      final raw = GStorage.articleDb.get(key);
      if (raw is! Map) continue;
      items.add(ArticleModel.fromCache(Map<String, dynamic>.from(raw)));
    }
    items.sort(_compareArticleByTimeDesc);
    _cachedAllArticles = items;
    return items;
  }

  static bool? readOverrideOf(String entryId) {
    final raw = GStorage.readStatus.get(entryId);
    if (raw is bool) return raw;
    return null;
  }

  static void upsertMany(List<ArticleModel> source, {bool? defaultReadState}) {
    if (source.isEmpty) return;
    final updates = <String, dynamic>{};

    for (final item in source) {
      if (item.entryId.isEmpty) continue;

      final existingRaw = GStorage.articleDb.get(item.entryId);
      final existing = existingRaw is Map
          ? ArticleModel.fromCache(Map<String, dynamic>.from(existingRaw))
          : null;

      final localOverride = readOverrideOf(item.entryId);
      final mergedRead =
          localOverride ??
          defaultReadState ??
          item.isRead || (existing?.isRead ?? false);

      final merged = ArticleModel(
        entryId: item.entryId,
        feedId: item.feedId.isNotEmpty ? item.feedId : (existing?.feedId ?? ''),
        feedTitle: item.feedTitle != '?'
            ? item.feedTitle
            : (existing?.feedTitle ?? '?'),
        feedImage: (item.feedImage != null && item.feedImage!.isNotEmpty)
            ? item.feedImage
            : existing?.feedImage,
        title: item.title != '?' ? item.title : (existing?.title ?? '?'),
        url: item.url.isNotEmpty ? item.url : (existing?.url ?? ''),
        content: () {
          final newItemContent = item.content ?? '';
          final existingContent = existing?.content ?? '';
          if (newItemContent.isNotEmpty && existingContent.isNotEmpty) {
            if (existingContent.length > newItemContent.length + 100) {
              return existingContent;
            }
          }
          return newItemContent.isNotEmpty ? newItemContent : existingContent;
        }(),
        publishedAt: item.publishedAt.isNotEmpty
            ? item.publishedAt
            : (existing?.publishedAt ?? ''),
        isRead: mergedRead,
        category: item.category,
        subscriptionCategory: item.subscriptionCategory.isNotEmpty
            ? item.subscriptionCategory
            : (existing?.subscriptionCategory ?? ''),
        author: (item.author != null && item.author!.isNotEmpty)
            ? item.author
            : existing?.author,
        imageUrl: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
            ? item.imageUrl
            : existing?.imageUrl,
        isRejectedByAi: item.isRejectedByAi || (existing?.isRejectedByAi ?? false),
        filterReason: (item.filterReason != null && item.filterReason!.isNotEmpty)
            ? item.filterReason
            : existing?.filterReason,
        filterReviewed: item.filterReviewed || (existing?.filterReviewed ?? false),
      );

      updates[item.entryId] = merged.toJson();
    }

    if (updates.isNotEmpty) {
      GStorage.articleDb.putAll(updates);
      invalidateCache();
    }

    _trimOverflow();
  }

  static void upsertOne(ArticleModel article) {
    upsertMany([article]);
  }

  static void setReadState(String entryId, bool isRead) {
    final raw = GStorage.articleDb.get(entryId);
    if (raw is! Map) return;

    final old = ArticleModel.fromCache(Map<String, dynamic>.from(raw));
    final updated = ArticleModel(
      entryId: old.entryId,
      feedId: old.feedId,
      feedTitle: old.feedTitle,
      feedImage: old.feedImage,
      title: old.title,
      url: old.url,
      content: old.content,
      publishedAt: old.publishedAt,
      isRead: isRead,
      category: old.category,
      subscriptionCategory: old.subscriptionCategory,
      author: old.author,
      imageUrl: old.imageUrl,
      isRejectedByAi: old.isRejectedByAi,
      filterReason: old.filterReason,
      filterReviewed: old.filterReviewed,
    );
    GStorage.articleDb.put(entryId, updated.toJson());
    invalidateCache();
  }

  static int _compareArticleByTimeDesc(ArticleModel a, ArticleModel b) {
    final ta = _timeScore(a);
    final tb = _timeScore(b);
    return tb.compareTo(ta);
  }

  static int _timeScore(ArticleModel article) {
    final raw = article.publishedAt.trim();
    if (raw.isEmpty) return 0;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }

  static void _trimOverflow() {
    final keys = _articleKeys.toList();
    if (keys.length <= _maxArticles) return;

    final sorted = readAllArticles();
    
    // 按优先级排序以决定保留哪些文章
    // 优先级 1: 所有未读文章 (在 5000 限制内优先保留未读，避免重复拉取)
    // 优先级 0: 已读文章
    sorted.sort((a, b) {
      int score(ArticleModel m) {
        if (!m.isRead) return 1;
        return 0;
      }
      
      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sb.compareTo(sa); // 优先级高的排在前面
      
      return _compareArticleByTimeDesc(a, b); // 优先级相同则按时间倒序
    });
    
    final keepIds = sorted.take(_maxArticles).map((e) => e.entryId).toSet();
    
    final toDelete = <String>[];
    for (final key in keys) {
      if (!keepIds.contains(key)) {
        toDelete.add(key);
      }
    }
    
    if (toDelete.isNotEmpty) {
      GStorage.articleDb.deleteAll(toDelete);
      invalidateCache();
    }
  }
}
