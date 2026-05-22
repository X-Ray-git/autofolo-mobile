import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/widgets/refresh_indicator.dart' as custom_refresh;
import '../../common/widgets/refresh_aware_scroll_physics.dart';
import '../../common/widgets/no_overscroll_indicator_behavior.dart';

import '../../http/init.dart';
import '../../router/app_pages.dart';
import '../../services/article_state_notifier.dart';
import '../../services/local_article_db_service.dart';
import '../widgets/article_card.dart';
import 'timeline_controller.dart';

/// 时间线页 — 本地文章库（未读/全部/已读）
class TimelinePage extends StatefulWidget {
  final bool showAppBar;

  const TimelinePage({super.key, this.showAppBar = true});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  late final TimelineController controller;
  final ScrollController _scrollController = ScrollController();
  final _refreshKey = GlobalKey<custom_refresh.RefreshIndicatorState>();
  late final _refreshPhysics = RefreshAwareScrollPhysics(refreshKey: _refreshKey);
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    controller = Get.put(TimelineController());
    controller.bindScrollToTopHandler(_scrollToTop);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    controller.bindScrollToTopHandler(null);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!controller.isLoadingMore && controller.hasMore) {
        controller.loadMore();
      }
    }
  }

  void _onAppBarTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
      _scrollToTop();
      _lastTapTime = null;
    } else {
      _lastTapTime = now;
    }
  }

  Future<void> _scrollToTop() async {
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _buildFilterBar(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => Get.toNamed(Routes.filterReview),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI 智能过滤',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '拦截了 $count 篇低质量或无关内容',
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFFB45309).withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFFD97706),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: GestureDetector(
                onTap: _onAppBarTap,
                child: const Text('时间线'),
              ),
              scrolledUnderElevation: 1,
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(0.5),
                child: Divider(height: 0.5, thickness: 0.5),
              ),
            )
          : null,
      body: Obx(() {
        final state = controller.loadingState.value;

        return switch (state) {
          Loading() => const _LocalTimelineSkeleton(), // 使用定制化的优雅骨架屏
          LoadError(:final errMsg) => _ErrorView(
            message: errMsg,
            onRetry: controller.loadFeedsThenArticles,
          ),
          Success() => custom_refresh.RefreshIndicator(
            key: _refreshKey,
            edgeOffset: MediaQuery.paddingOf(context).top,
            displacement: 20,
            onRefresh: () async {
              await controller.loadFeedsThenArticles();
            },
            child: Obx(() {
              ArticleStateNotifier.version.value; // 订阅变更通知
              final filterCount = LocalArticleDbService.readAllArticles()
                  .where((a) => a.isRejectedByAi && !a.isRead)
                  .length;
              return ScrollConfiguration(
                behavior: const NoOverscrollIndicatorBehavior(),
                child: controller.articles.isEmpty
                  ? ListView(
                      physics: _refreshPhysics,
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top,
                        bottom: 8 +
                            kBottomNavigationBarHeight +
                            MediaQuery.of(context).padding.bottom,
                      ),
                      children: [
                        _buildFilterBar(filterCount),
                        Padding(
                          padding: const EdgeInsets.only(top: 64),
                          child: _EmptyView(
                            message: controller.emptyMessage,
                            onRetry: controller.loadFeedsThenArticles,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: _refreshPhysics,
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top,
                        bottom: 8 +
                            kBottomNavigationBarHeight +
                            MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount:
                          controller.articles.length +
                              1, // +1 for filter bar
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _buildFilterBar(filterCount);
                        }
                        final articleIndex = index - 1;
                        if (articleIndex == controller.articles.length) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final article =
                            controller.articles[articleIndex];
                        return ArticleCard(
                          article: article,
                          onTap: () {
                            Get.toNamed(
                              Routes.article,
                              arguments: {
                                'article': article,
                                'sequence':
                                    controller.articles.toList(),
                                'index': articleIndex,
                              },
                            );
                          },
                        );
                      },
                    ),
              );
            }),
          ),
        };
      }),
    );
  }
}

// ─── 优雅的加载骨架屏（与新版卡片像素级对齐） ───

class _LocalTimelineSkeleton extends StatefulWidget {
  const _LocalTimelineSkeleton();

  @override
  State<_LocalTimelineSkeleton> createState() => _LocalTimelineSkeletonState();
}

class _LocalTimelineSkeletonState extends State<_LocalTimelineSkeleton>
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
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 6),
      itemCount: 6,
      itemBuilder: (context, index) {
        return FadeTransition(
          opacity: _opacityAnim,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Lines
                    _SkeletonBlock(width: double.infinity, height: 18),
                    const SizedBox(height: 10),
                    _SkeletonBlock(width: MediaQuery.of(context).size.width * 0.6, height: 18),
                    const SizedBox(height: 20),
                    // Bottom Metadata Row
                    Row(
                      children: [
                        _SkeletonBlock(width: 48, height: 20, borderRadius: 10),
                        const SizedBox(width: 8),
                        _SkeletonBlock(width: 48, height: 20, borderRadius: 10),
                        const Spacer(),
                        _SkeletonBlock(width: 64, height: 14),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

// ─── 优雅的错误页 ───

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _ErrorView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 48, color: colorScheme.error),
            ),
            const SizedBox(height: 24),
            Text(
              '数据加载异常',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? '请检查网络连接后重试',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重新加载'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 优雅的空状态页 ───

class _EmptyView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _EmptyView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.done_all_rounded,
                size: 56,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '一切就绪',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? '当前没有未读的新文章\n您可以去订阅源发现更多内容',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('强制同步'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}