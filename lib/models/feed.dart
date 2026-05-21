import 'package:flutter/material.dart';

import '../utils/source_taxonomy.dart';

class FeedModel {
  final String feedId;
  final String title;
  final String? category;
  final int? view;
  final String? url;
  final String? image;

  FeedModel({
    required this.feedId,
    required this.title,
    this.category,
    this.view,
    this.url,
    this.image,
  });

  factory FeedModel.fromJson(Map<String, dynamic> json) {
    final feeds = json['feeds'] as Map<String, dynamic>? ?? {};
    return FeedModel(
      feedId: json['feedId'] as String? ?? '',
      title: feeds['title'] as String? ?? '?',
      category: json['category'] as String?,
      view: json['view'] as int?,
      url: feeds['url'] as String?,
      image: feeds['image'] as String?,
    );
  }

  factory FeedModel.fromInboxJson(Map<String, dynamic> json) {
    return FeedModel(
      feedId: (json['id'] as String?) ?? (json['inboxId'] as String? ?? ''),
      title: SourceTaxonomy.inboxDisplayTitle(json),
      category: SourceTaxonomy.inboxShortLabel(json),
      view: 2,
      url: json['url'] as String?,
      image: json['image'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'feedId': feedId,
    'title': title,
    'category': category,
    'view': view,
    'url': url,
    'image': image,
  };

  factory FeedModel.fromCache(Map<String, dynamic> json) => FeedModel(
    feedId: json['feedId'] as String? ?? '',
    title: json['title'] as String? ?? '?',
    category: json['category'] as String?,
    view: json['view'] as int?,
    url: json['url'] as String?,
    image: json['image'] as String?,
  );

  String get displayCategory => category ?? '未分类';
  String get viewLabel => SourceTaxonomy.viewLabelFromInt(view);
  String get viewKey => SourceTaxonomy.viewKeyFromInt(view);
  Color get viewColor => SourceTaxonomy.viewColorFromInt(view);
  int get viewOrder => SourceTaxonomy.viewOrderFromInt(view);
  bool get isInbox => view == 2;
}
