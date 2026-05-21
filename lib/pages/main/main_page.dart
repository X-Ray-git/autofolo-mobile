import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../timeline/timeline_controller.dart';
import '../timeline/timeline_page.dart';
import '../widgets/article_search_delegate.dart';
import '../subscriptions/subscriptions_page.dart';
import '../settings/settings_page.dart';
import '../../common/widgets/feedback_toast.dart';

/// 主页面 — 底部导航栏
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final _currentIndex = 0.obs;
  DateTime? _lastTimelineNavTapAt;

  static const _titles = ['时间线', '订阅源', '设置'];

  final _pages = const <Widget>[
    TimelinePage(showAppBar: false),
    SubscriptionsPage(),
    SettingsPage(showAppBar: false),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true, // 核心：允许列表内容穿透到导航栏下方，配合毛玻璃效果
      appBar: AppBar(
        title: Obx(() => Text(_titles[_currentIndex.value])),
        scrolledUnderElevation: 1,
        actions: [
          Obx(() {
            if (_currentIndex.value != 0 ||
                !Get.isRegistered<TimelineController>()) {
              return const SizedBox.shrink();
            }
            final controller = Get.find<TimelineController>();
            final mode = controller.selectedMode.value;
            return PopupMenuButton<TimelineViewMode>(
              tooltip: '切换视图',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: controller.setViewMode,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: TimelineViewMode.unread,
                  child: Text('未读 ${controller.unreadCount}'),
                ),
                PopupMenuItem(
                  value: TimelineViewMode.all,
                  child: Text('全部 ${controller.allCount}'),
                ),
                PopupMenuItem(
                  value: TimelineViewMode.read,
                  child: Text('已读 ${controller.readCount}'),
                ),
              ],
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${_modeLabel(mode)} ${_modeCount(controller, mode)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索',
            onPressed: () async {
              if (_currentIndex.value != 0) {
                AppFeedback.info('无法搜索', '当前仅支持时间线文章搜索');
                return;
              }
              if (!Get.isRegistered<TimelineController>()) {
                return;
              }

              final controller = Get.find<TimelineController>();
              final selected = await showSearch<ArticleModel?>(
                context: context,
                delegate: ArticleSearchDelegate(
                  source: controller.searchSourceArticles,
                ),
              );
              if (selected != null) {
                final source = controller.searchSourceArticles;
                final index = source.indexOf(selected);
                Get.toNamed(
                  Routes.article,
                  arguments: {
                    'article': selected,
                    'sequence': source,
                    'index': index < 0 ? 0 : index,
                  },
                );
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(
        // 使用自定义的淡入淡出堆叠组件替换生硬的 IndexedStack
        () => _FadeIndexedStack(
          index: _currentIndex.value,
          children: _pages,
        ),
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
            ),
            child: Obx(() {
              return NavigationBar(
                elevation: 0,
                backgroundColor: colorScheme.surface.withValues(alpha: 0.40),
                indicatorColor: colorScheme.primary.withValues(alpha: 0.80),
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: _currentIndex.value,
                onDestinationSelected: _onDestinationSelected,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.article_outlined),
                    selectedIcon: Icon(Icons.article),
                    label: '时间线',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.rss_feed_outlined),
                    selectedIcon: Icon(Icons.rss_feed),
                    label: '订阅源',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: '设置',
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  String _modeLabel(TimelineViewMode mode) => switch (mode) {
        TimelineViewMode.unread => '未读',
        TimelineViewMode.all => '全部',
        TimelineViewMode.read => '已读',
      };

  int _modeCount(TimelineController controller, TimelineViewMode mode) =>
      switch (mode) {
        TimelineViewMode.unread => controller.unreadCount,
        TimelineViewMode.all => controller.allCount,
        TimelineViewMode.read => controller.readCount,
      };

  void _onDestinationSelected(int index) {
    final now = DateTime.now();
    if (index == _currentIndex.value) {
      if (index == 0 &&
          _lastTimelineNavTapAt != null &&
          now.difference(_lastTimelineNavTapAt!).inMilliseconds < 300) {
        _lastTimelineNavTapAt = null;
        if (!Get.isRegistered<TimelineController>()) return;
        Get.find<TimelineController>().scrollToTop();
        return;
      }
      if (index == 0) {
        _lastTimelineNavTapAt = now;
      }
      return;
    }
    _currentIndex.value = index;
    _lastTimelineNavTapAt = index == 0 ? now : null;
  }
}

/// 优雅的淡入淡出堆叠组件 (FadeIndexedStack)
/// 替代原生的 IndexedStack，解决页面切换生硬的问题，同时完美保留页面状态。
class _FadeIndexedStack extends StatelessWidget {
  final int index;
  final List<Widget> children;
  
  const _FadeIndexedStack({
    required this.index,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: List.generate(children.length, (i) {
        final active = i == index;
        return IgnorePointer(
          ignoring: !active,
          child: AnimatedOpacity(
            opacity: active ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: TickerMode(
              enabled: active, // 不活跃时暂停内部动画，节省性能
              child: children[i],
            ),
          ),
        );
      }),
    );
  }
}