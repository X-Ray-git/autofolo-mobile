import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common/widgets/loading_widget.dart';
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
    return InkWell(
      onTap: () => Get.toNamed(Routes.filterReview),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            const Icon(Icons.filter_alt_outlined,
                size: 16, color: Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            Text('AI 已过滤 $count 篇 · 查看',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFFF59E0B))),
            const Spacer(),
            const Icon(Icons.chevron_right,
                size: 16, color: Color(0xFFF59E0B)),
          ],
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
            )
          : null,
      body: Obx(() {
        final state = controller.loadingState.value;

        return switch (state) {
          Loading() => const LoadingWidget(msg: '加载中...'),
          LoadError(:final errMsg) => _ErrorView(
            message: errMsg,
            onRetry: controller.loadFeedsThenArticles,
          ),
          Success() => RefreshIndicator(
            onRefresh: () async {
              await controller.loadFeedsThenArticles();
            },
            child: Obx(() {
              ArticleStateNotifier.version.value; // 订阅变更通知
              final filterCount = LocalArticleDbService.readAllArticles()
                  .where((a) => a.isRejectedByAi && !a.isRead)
                  .length;
              return controller.articles.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        top: 40,
                        bottom: 8 +
                            kBottomNavigationBarHeight +
                            MediaQuery.of(context).padding.bottom,
                      ),
                      children: [
                        _buildFilterBar(filterCount),
                        _EmptyView(
                          message: controller.emptyMessage,
                          onRetry: controller.loadFeedsThenArticles,
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                        top: 0,
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
                            padding: EdgeInsets.all(16),
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
                    );
            }),
          ),
        };
      }),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _ErrorView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message ?? '加载失败',
              style: TextStyle(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
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

class _EmptyView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const _EmptyView({this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message ?? '暂无文章',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 16,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('刷新')),
            ],
          ],
        ),
      ),
    );
  }
}
