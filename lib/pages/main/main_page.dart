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
  late final TimelineController _timelineController;

  static const _titles = ['时间线', '订阅源', '设置'];

  final _pages = const <Widget>[
    TimelinePage(showAppBar: false),
    SubscriptionsPage(),
    SettingsPage(showAppBar: false),
  ];

  @override
  void initState() {
    super.initState();
    _timelineController = Get.put(TimelineController());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true, // 核心：允许列表内容穿透到导航栏下方，配合毛玻璃效果
      extendBodyBehindAppBar: true, // 核心：允许列表内容穿透到顶部导航栏下方
      appBar: AppBar(
        leadingWidth: 130, // 给未读胶囊足够的空间
        leading: Obx(() {
          if (_currentIndex.value != 0) return const SizedBox.shrink();
          final mode = _timelineController.selectedMode.value;
          // 强制触发底层列表的长度监听，确保未读数字精确响应
          final _ = _timelineController.allArticles.length;
          return Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Builder(
                  builder: (buttonContext) => InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      // 显示下拉菜单
                      final RenderBox button = buttonContext.findRenderObject() as RenderBox;
                      final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                    final RelativeRect position = RelativeRect.fromRect(
                      Rect.fromPoints(
                        button.localToGlobal(Offset(0, button.size.height + 8), ancestor: overlay),
                        button.localToGlobal(button.size.bottomRight(Offset.zero) + const Offset(0, 8), ancestor: overlay),
                      ),
                      Offset.zero & overlay.size,
                    );
                    showMenu<TimelineViewMode>(
                      context: context,
                      position: position,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
                      elevation: 4,
                      items: [
                        PopupMenuItem(
                          value: TimelineViewMode.unread,
                          child: Text('未读 ${_timelineController.unreadCount}'),
                        ),
                        PopupMenuItem(
                          value: TimelineViewMode.all,
                          child: Text('全部 ${_timelineController.allCount}'),
                        ),
                        PopupMenuItem(
                          value: TimelineViewMode.read,
                          child: Text('已读 ${_timelineController.readCount}'),
                        ),
                      ],
                    ).then((value) {
                      if (value != null) _timelineController.setViewMode(value);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: mode == TimelineViewMode.unread 
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: mode == TimelineViewMode.unread
                            ? colorScheme.primary.withValues(alpha: 0.3)
                            : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          mode == TimelineViewMode.unread
                              ? Icons.mark_email_unread_rounded
                              : mode == TimelineViewMode.all
                                  ? Icons.inbox_rounded
                                  : Icons.done_all_rounded,
                          size: 16,
                          color: mode == TimelineViewMode.unread
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_modeLabel(mode)} ${_modeCount(_timelineController, mode)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: mode == TimelineViewMode.unread
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
            ),
          );
        }),
        title: Obx(() => Text(
          _titles[_currentIndex.value],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        )),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: colorScheme.surface.withValues(alpha: 0.85)),
          ),
        ),
        actions: [
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
                overlayColor: WidgetStateProperty.all(Colors.transparent),
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