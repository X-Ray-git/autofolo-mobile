import 'package:flutter/material.dart';

import '../../models/article.dart';

class ArticleSearchDelegate extends SearchDelegate<ArticleModel?> {
  final List<ArticleModel> source;

  ArticleSearchDelegate({required this.source});

  List<ArticleModel> _filter(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return source;

    return source.where((article) {
      final title = article.title.toLowerCase();
      final feedTitle = article.feedTitle.toLowerCase();
      final author = (article.author ?? '').toLowerCase();
      return title.contains(query) ||
          feedTitle.contains(query) ||
          author.contains(query);
    }).toList();
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: '清空',
          onPressed: () => query = '',
          icon: const Icon(Icons.close),
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: '返回',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildList(context, _filter(query));
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildList(context, _filter(query));
  }

  Widget _buildList(BuildContext context, List<ArticleModel> items) {
    if (items.isEmpty) {
      return const Center(child: Text('没有匹配的文章'));
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final article = items[index];
        return ListTile(
          title: Text(
            article.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${article.feedTitle}${article.author?.isNotEmpty == true ? ' · ${article.author}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => close(context, article),
        );
      },
    );
  }
}
