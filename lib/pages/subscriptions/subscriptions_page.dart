import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/widgets/pill_tag.dart';
import '../../http/init.dart';
import '../../models/feed.dart';
import '../../router/app_pages.dart';
import '../../services/article_image_service.dart';
import '../../utils/source_taxonomy.dart';
import 'subscriptions_controller.dart';

/// 订阅源页 — 按 view → 分类 → 订阅源 树形展示
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
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 现代化的搜索栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: controller.updateSearchQuery,
            decoration: InputDecoration(
              hintText: '搜索 view、分类或订阅源',
              hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              prefixIcon: Icon(Icons.search_rounded, color: cs.primary),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
              suffixIcon: Obx(() {
                return controller.searchQuery.value.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          _searchController.clear();
                          controller.updateSearchQuery('');
                        },
                        icon: Icon(Icons.cancel, color: cs.onSurfaceVariant),
                      );
              }),
            ),
          ),
        ),
        Expanded(
          child: Obx(() {
            final state = controller.loadingState.value;

            return switch (state) {
              Loading() => const _SubscriptionsSkeleton(),
              LoadError(:final errMsg) => _ErrorView(
                  message: errMsg,
                  onRetry: controller.loadData,
                ),
              Success() => Builder(builder: (context) {
                  final filtered = controller.filteredNodes;
                  if (filtered.isEmpty) {
                    return _EmptyView(
                      message: '没有找到匹配的订阅源\n请尝试更换搜索关键词',
                      onClear: () {
                        _searchController.clear();
                        controller.updateSearchQuery('');
                      },
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: controller.loadData,
                    color: cs.primary,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        top: 8,
                        bottom: 16 +
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
            };
          }),
        ),
      ],
    );
  }
}

// ─── 优雅的骨架屏 ────────────────────────────────

class _SubscriptionsSkeleton extends StatefulWidget {
  const _SubscriptionsSkeleton();

  @override
  State<_SubscriptionsSkeleton> createState() => _SubscriptionsSkeletonState();
}

class _SubscriptionsSkeletonState extends State<_SubscriptionsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacityAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 16),
      itemCount: 4,
      itemBuilder: (context, index) {
        return FadeTransition(
          opacity: _opacityAnim,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // View 层占位
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 24,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 100,
                      height: 14,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Feed 卡片占位
                Container(
                  margin: const EdgeInsets.only(left: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120,
                              height: 14,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 180,
                              height: 12,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── 状态视图 ──────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  const _ErrorView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 48, color: cs.error),
            ),
            const SizedBox(height: 24),
            Text(
              '无法获取订阅数据',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? '请检查网络连接后重试',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新加载'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String? message;
  final VoidCallback? onClear;
  const _EmptyView({this.message, this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded, size: 56, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text(
              message ?? '暂无订阅源',
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            if (onClear != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('清空搜索'),
              ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _openAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                PillTag(
                  label: widget.viewNode.name,
                  backgroundColor: viewColor.withValues(alpha: 0.15),
                  foregroundColor: viewColor,
                  fontSize: 13,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(() {
                    final unread =
                        widget.controller.unreadForView(
                            widget.viewNode.categories);
                    return Row(
                      children: [
                        Text(
                          '${widget.viewNode.categoryCount} 个分类',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$unread',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
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
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.chevron_right,
                        size: 18,
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
              const SizedBox(height: 8),
            ],
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
          sizeCurve: Curves.easeInOut,
        ),
      ],
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
            padding: const EdgeInsets.fromLTRB(32, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 18, color: viewColor),
                const SizedBox(width: 8),
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
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unread',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_right_rounded,
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
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Column(
              children: [
                ...widget.category.feeds.map(
                  (feed) => _FeedCard(
                    controller: widget.controller,
                    feed: feed,
                    viewColor: viewColor,
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}

// ─── 独立圆角的柔和 Feed 卡片 ─────────────────────────

class _FeedCard extends StatelessWidget {
  final SubscriptionsController controller;
  final FeedModel feed;
  final Color viewColor;

  const _FeedCard({
    required this.controller,
    required this.feed,
    required this.viewColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final unreadCount = controller.unreadFor(feed.feedId);
      final hasUnread = unreadCount > 0;

      return Container(
        margin: const EdgeInsets.only(left: 48, right: 16, bottom: 8),
        decoration: BoxDecoration(
          // 如果有未读，背景泛起柔和的 Primary 强调色；否则为安静的表面色
          color: hasUnread
              ? cs.primaryContainer.withValues(alpha: 0.15)
              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasUnread
                ? cs.primary.withValues(alpha: 0.2)
                : cs.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Get.toNamed(Routes.feedDetail, arguments: {
              'feedId': feed.feedId,
              'feedTitle': feed.title,
              'feedImage': feed.image,
              'category': feed.category,
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _FeedAvatar(feed: feed, viewColor: viewColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feed.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      if (feed.url != null && feed.url!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          feed.url!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasUnread) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unreadCount.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _FeedAvatar extends StatelessWidget {
  final FeedModel feed;
  final Color viewColor;
  const _FeedAvatar({required this.feed, required this.viewColor});

  @override
  Widget build(BuildContext context) {
    final imageUrl = feed.image != null
        ? ArticleImageService.toProxiedUrl(feed.image)
        : null;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: viewColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        image: imageUrl != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(imageUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: imageUrl == null
          ? Text(
              feed.title.isNotEmpty ? feed.title[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: viewColor,
              ),
            )
          : null,
    );
  }
}