import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/widgets/pill_tag.dart';
import '../../common/widgets/loading_widget.dart';
import '../../http/init.dart';
import '../../models/feed.dart';
import '../../router/app_pages.dart';
import '../../services/article_image_service.dart';
import '../../utils/source_taxonomy.dart';
import 'subscriptions_controller.dart';

/// 订阅源页 — 按 view → 分类 → 订阅源 树形展示
/// 交互：点击箭头 = 展开/折叠，点击其他区域 = 查看该层级全部文章
class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  late final SubscriptionsController controller;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = Get.put(SubscriptionsController());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    controller.refreshUnreadCounts();
    return Obx(() {
      final state = controller.loadingState.value;

      return switch (state) {
        Loading() => const LoadingWidget(msg: '加载中...'),
        LoadError(:final errMsg) => _ErrorView(
          message: errMsg,
          onRetry: controller.loadData,
        ),
        Success() => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                onChanged: controller.updateSearchQuery,
                decoration: InputDecoration(
                  hintText: '搜索 view、分类或订阅源',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.searchQuery.value.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          onPressed: () {
                            _searchController.clear();
                            controller.updateSearchQuery('');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: Builder(builder: (context) {
                final filtered = controller.filteredNodes;
                if (filtered.isEmpty) {
                  return const Center(child: Text('没有匹配的订阅源'));
                }
                return RefreshIndicator(
                  onRefresh: controller.loadData,
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      top: 8,
                      bottom: 8 +
                          kBottomNavigationBarHeight +
                          MediaQuery.of(context).padding.bottom,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _ViewSection(
                        controller: controller,
                        viewNode: filtered[index],
                        defaultExpanded:
                            controller.searchQuery.value.isNotEmpty,
                      );
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      };
    });
  }
}

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  const _ErrorView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 16),
            Text(message ?? '加载失败',
                style: TextStyle(color: cs.onSurface),
                textAlign: TextAlign.center),
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

// ─── View 层级 ──────────────────────────────────

class _ViewSection extends StatefulWidget {
  final SubscriptionsController controller;
  final SourceViewNode viewNode;
  final bool defaultExpanded;

  const _ViewSection({
    required this.controller,
    required this.viewNode,
    this.defaultExpanded = false,
  });

  @override
  State<_ViewSection> createState() => _ViewSectionState();
}

class _ViewSectionState extends State<_ViewSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.controller.isExpanded(
      'view:${widget.viewNode.name}',
      defaultExpanded: widget.defaultExpanded,
    );
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      widget.controller.setExpanded('view:${widget.viewNode.name}', _expanded);
    });
  }

  void _openAll() {
    Get.toNamed(Routes.feedDetail, arguments: {
      'view': widget.viewNode.view,
      'viewName': widget.viewNode.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final viewColor = SourceTaxonomy.viewColorFromInt(widget.viewNode.view);

    return Column(
      children: [
        InkWell(
          onTap: _openAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                PillTag(
                  label: widget.viewNode.name,
                  backgroundColor: viewColor.withValues(alpha: 0.14),
                  foregroundColor: viewColor,
                  fontSize: 12,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Obx(() {
                    final unread =
                        widget.controller.unreadForView(
                            widget.viewNode.categories);
                    return Row(
                      children: [
                        Text(
                          '${widget.viewNode.categoryCount}个分类',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$unread',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  }),
                ),
                GestureDetector(
                  onTap: _toggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.chevron_right,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              for (final cat in widget.viewNode.categories)
                _CategorySection(
                  controller: widget.controller,
                  viewNode: widget.viewNode,
                  category: cat,
                  defaultExpanded: widget.defaultExpanded,
                ),
            ],
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

// ─── 订阅源头像 ──────────────────────────────

class _FeedAvatar extends StatelessWidget {
  final FeedModel feed;
  const _FeedAvatar({required this.feed});

  @override
  Widget build(BuildContext context) {
    final viewColor = SourceTaxonomy.viewColorFromInt(feed.view);
    final imageUrl = feed.image != null
        ? ArticleImageService.toProxiedUrl(feed.image)
        : null;

    return CircleAvatar(
      radius: 18,
      backgroundColor: viewColor.withValues(alpha: 0.15),
      backgroundImage:
          imageUrl != null ? CachedNetworkImageProvider(imageUrl) : null,
      child: imageUrl == null
          ? Text(
              feed.title.isNotEmpty ? feed.title[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: viewColor,
              ),
            )
          : null,
    );
  }
}

// ─── 分类层级 ──────────────────────────────────

class _CategorySection extends StatefulWidget {
  final SubscriptionsController controller;
  final SourceViewNode viewNode;
  final SourceCategoryNode category;
  final bool defaultExpanded;

  const _CategorySection({
    required this.controller,
    required this.viewNode,
    required this.category,
    this.defaultExpanded = false,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.controller.isExpanded(
      'cat:${widget.viewNode.name}:${widget.category.name}',
      defaultExpanded: widget.defaultExpanded,
    );
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      widget.controller.setExpanded(
        'cat:${widget.viewNode.name}:${widget.category.name}',
        _expanded,
      );
    });
  }

  void _openAll() {
    Get.toNamed(Routes.feedDetail, arguments: {
      'category': widget.category.name,
      'categoryName': widget.category.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final viewColor = SourceTaxonomy.viewColorFromInt(widget.viewNode.view);

    return Column(
      children: [
        InkWell(
          onTap: _openAll,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16, color: viewColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.category.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Obx(() {
                  final unread = widget.controller.unreadForCategory(
                      widget.category.name, widget.category.feeds);
                  if (unread == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$unread',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: _toggle,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.chevron_right,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              ...widget.category.feeds.map(
                (feed) => ListTile(
                  leading: _FeedAvatar(feed: feed),
                  title: Text(
                    feed.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: feed.url != null && feed.url!.isNotEmpty
                      ? Text(
                          feed.url!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      : null,
                  trailing: Obx(() {
                    final count =
                        widget.controller.unreadFor(feed.feedId);
                    if (count == 0) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    );
                  }),
                  onTap: () {
                    Get.toNamed(Routes.feedDetail, arguments: {
                      'feedId': feed.feedId,
                      'feedTitle': feed.title,
                      'feedImage': feed.image,
                      'category': feed.category,
                    });
                  },
                ),
              ),
            ],
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
