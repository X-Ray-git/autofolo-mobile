import '../utils/source_taxonomy.dart';

class ArticleModel {
  final String entryId;
  final String feedId;
  final String feedTitle;
  final String? feedImage;
  final String title;
  final String url;
  final String? content;
  final String publishedAt;
  final bool isRead;
  final String category;
  final String subscriptionCategory;
  final String? author;
  final String? imageUrl;
  final bool isRejectedByAi;
  final String? filterReason;
  final bool filterReviewed; // 用户已审核过，不再重判

  ArticleModel({
    required this.entryId,
    required this.feedId,
    required this.feedTitle,
    this.feedImage,
    required this.title,
    required this.url,
    this.content,
    this.publishedAt = '',
    this.isRead = false,
    this.category = 'feeds',
    this.subscriptionCategory = '',
    this.author,
    this.imageUrl,
    this.isRejectedByAi = false,
    this.filterReason,
    this.filterReviewed = false,
  });

  factory ArticleModel.fromEntryJson(
    Map<String, dynamic> item, {
    String? feedTitle,
    String? feedImage,
    String? subscriptionCategory,
    int view = 0,
    int? feedView,
  }) {
    final entry = item['entries'] as Map<String, dynamic>? ?? {};
    final feed = item['feeds'] as Map<String, dynamic>? ?? {};
    final media = entry['media'] as List<dynamic>?;
    String? imageUrl;
    if (media != null && media.isNotEmpty) {
      final m = media.first as Map<String, dynamic>?;
      imageUrl = m?['url'] as String?;
    }

    final category = (view == 1 || feedView == 1) ? 'social' : 'feeds';

    return ArticleModel(
      entryId: entry['id'] as String? ?? '',
      feedId: feed['id'] as String? ?? '',
      feedTitle: feedTitle ?? feed['title'] as String? ?? '?',
      feedImage: feedImage ?? feed['image'] as String?,
      title: entry['title'] as String? ?? '?',
      url: entry['url'] as String? ?? '',
      content: entry['content'] as String?,
      publishedAt: entry['publishedAt'] as String? ?? '',
      isRead: entry['read'] as bool? ?? false,
      category: category,
      subscriptionCategory: subscriptionCategory ?? '',
      author: entry['author'] as String?,
      imageUrl: imageUrl,
      isRejectedByAi: false,
      filterReviewed: false,
    );
  }

  factory ArticleModel.fromInboxJson(
    Map<String, dynamic> item, {
    String? feedTitle,
    String? feedImage,
    String? subscriptionCategory,
  }) {
    final entry = item['entries'] as Map<String, dynamic>? ?? {};
    final sourceTitle = feedTitle ?? SourceTaxonomy.inboxDisplayTitle(item);
    return ArticleModel(
      entryId: entry['id'] as String? ?? '',
      feedId: (item['feeds'] as Map<String, dynamic>?)?['id'] as String? ??
          entry['inboxHandle'] as String? ?? '',
      feedTitle: sourceTitle,
      feedImage: feedImage ?? item['image'] as String?,
      title: entry['title'] as String? ?? '?',
      url: entry['url'] as String? ?? '',
      content: entry['content'] as String?,
      publishedAt: entry['publishedAt'] as String? ?? '',
      isRead: entry['read'] as bool? ?? false,
      category: 'inbox',
      subscriptionCategory:
          subscriptionCategory ?? SourceTaxonomy.inboxShortLabel(item),
      isRejectedByAi: false,
      filterReviewed: false,
    );
  }

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'feedId': feedId,
    'feedTitle': feedTitle,
    'feedImage': feedImage,
    'title': title,
    'url': url,
    'content': content,
    'publishedAt': publishedAt,
    'isRead': isRead,
    'category': category,
    'subscriptionCategory': subscriptionCategory,
    'author': author,
    'imageUrl': imageUrl,
    'isRejectedByAi': isRejectedByAi,
    'filterReason': filterReason,
    'filterReviewed': filterReviewed,
  };

  factory ArticleModel.fromCache(Map<String, dynamic> json) => ArticleModel(
    entryId: json['entryId'] as String? ?? '',
    feedId: json['feedId'] as String? ?? '',
    feedTitle: json['feedTitle'] as String? ?? '?',
    feedImage: json['feedImage'] as String?,
    title: json['title'] as String? ?? '?',
    url: json['url'] as String? ?? '',
    content: json['content'] as String?,
    publishedAt: json['publishedAt'] as String? ?? '',
    isRead: json['isRead'] as bool? ?? false,
    category: json['category'] as String? ?? 'feeds',
    subscriptionCategory: json['subscriptionCategory'] as String? ?? '',
    author: json['author'] as String?,
    imageUrl: json['imageUrl'] as String?,
    isRejectedByAi: json['isRejectedByAi'] as bool? ?? false,
    filterReason: json['filterReason'] as String?,
    filterReviewed: json['filterReviewed'] as bool? ?? false,
  );

  String get displayCategory =>
      subscriptionCategory.isNotEmpty ? subscriptionCategory : '未分类';
}
