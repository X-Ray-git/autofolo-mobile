import 'package:flutter/material.dart';

import '../../models/article.dart';
import 'article_card.dart';

/// 全局文章搜索代理
class ArticleSearchDelegate extends SearchDelegate<ArticleModel?> {
  final List<ArticleModel> source;

  ArticleSearchDelegate({required this.source})
      : super(searchFieldLabel: '搜索文章标题、内容或来源...');

  /// 覆写系统主题，移除原生 SearchDelegate 生硬的阴影和下划线，赋予现代化质感
  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(
          fontSize: 16,
          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: cs.primary,
        selectionColor: cs.primary.withValues(alpha: 0.3),
        selectionHandleColor: cs.primary,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) return const [];
    return [
      IconButton(
        tooltip: '清空',
        icon: Icon(
          Icons.cancel_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: '返回',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    // 1. 初始搜索空状态
    if (query.trim().isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.manage_search_rounded,
        title: '全局检索',
        message: '输入关键字查找当前列表中的文章\n支持匹配标题、内容摘要与来源名称',
      );
    }

    final lowerQuery = query.toLowerCase();
    final results = source.where((article) {
      return article.title.toLowerCase().contains(lowerQuery) ||
          (article.feedTitle.toLowerCase().contains(lowerQuery)) ||
          (article.content?.toLowerCase().contains(lowerQuery) ?? false) ||
          (article.author?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();

    // 2. 搜索无结果状态
    if (results.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.search_off_rounded,
        title: '未找到相关结果',
        message: '没有匹配到与 "$query" 相关的文章\n换个关键词再试一次吧',
      );
    }

    // 3. 渲染结果卡片
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: 8,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final article = results[index];
        return ArticleCard(
          article: article,
          showFeedTitle: true,
          onTap: () => close(context, article),
        );
      },
    );
  }

  /// 统一的高阶空状态组件
  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}