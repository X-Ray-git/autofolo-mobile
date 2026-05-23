import '../models/article.dart';
import '../utils/storage.dart';

/// 本地文章库（已读/未读统一持久化）
abstract final class LocalArticleDbService {
  static const String _metaPrefix = '__meta__';
  static const int _maxArticles = 5000;

  static Iterable<String> get _articleKeys {
    return GStorage.articleDb.keys.whereType<String>().where(
      (k) => !k.startsWith(_metaPrefix),
    );
  }

  static List<ArticleModel> readAllArticles() {
    final items = <ArticleModel>[];
    for (final key in _articleKeys) {
      final raw = GStorage.articleDb.get(key);
      if (raw is! Map) continue;
      items.add(ArticleModel.fromCache(Map<String, dynamic>.from(raw)));
    }
    items.sort(_compareArticleByTimeDesc);
    return items;
  }

  static bool? readOverrideOf(String entryId) {
    final raw = GStorage.readStatus.get(entryId);
    if (raw is bool) return raw;
    return null;
  }

  static void upsertMany(List<ArticleModel> source, {bool? defaultReadState}) {
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
            // 如果本地已有长文（可能被 Readability 扩充过），而新同步的只是短摘要，则保留本地长文
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

      GStorage.articleDb.put(item.entryId, merged.toJson());
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
    final keepIds = sorted.take(_maxArticles).map((e) => e.entryId).toSet();
    for (final key in keys) {
      if (!keepIds.contains(key)) {
        GStorage.articleDb.delete(key);
      }
    }
  }
}
