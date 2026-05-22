import 'package:flutter/material.dart';

import 'refresh_indicator.dart' as custom_refresh;

/// 一个感知下拉刷新状态的 [ScrollPhysics]。
///
/// 用于解决 Android 上 [ClampingScrollPhysics] 在反悔手势时
/// 导致内容跟随手指移动的问题：
///   - Android 的 ClampingScrollPhysics 在边界夹紧时，
///     下拉产生 overscroll 但位置停留在 0；
///   - 但当用户反悔上推时，pixels 0→正数 在边界内，
///     物理引擎放行 → 内容开始正常滚动。
///   - 本 Physics 在 RefreshIndicator 处于拖拽态 (drag/armed)
///     且有累积下拉量 (dragOffset > 0) 时，将正向滚动也视作 overscroll，
///     从而阻止内容位移。
class RefreshAwareScrollPhysics extends AlwaysScrollableScrollPhysics {
  final GlobalKey<custom_refresh.RefreshIndicatorState> refreshKey;

  const RefreshAwareScrollPhysics({
    required this.refreshKey,
    super.parent,
  });

  @override
  RefreshAwareScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return RefreshAwareScrollPhysics(
      refreshKey: refreshKey,
      parent: buildParent(ancestor),
    );
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // 先让父级物理做正常判断
    final double parentResult =
        super.applyBoundaryConditions(position, value);

    // 只有当 RefreshIndicator 处于活跃状态时才干预
    final state = refreshKey.currentState;
    if (state == null) {
      return parentResult;
    }

    final status = state.status;
    final dragOffset = state.dragOffset;

    final bool isRefreshing = status == custom_refresh.RefreshIndicatorStatus.drag ||
        status == custom_refresh.RefreshIndicatorStatus.armed;

    // 关键判断：刷新活跃 + 还有累积的下拉量 + 用户正向滚动 + 在顶部边界
    if (isRefreshing &&
        dragOffset != null &&
        dragOffset > 0 &&
        value > position.pixels &&
        position.pixels <= position.minScrollExtent) {
      // 把用户在顶部的正向滚动也当作 overscroll 拦截，
      // 这样内容 pixels 就不会从 0 变成正数，内容不会位移。
      // 当 dragOffset 降至 0（圆环完全收回）后，此分支不再触发，
      // 后续的正常滚动恢复。
      return value - position.pixels;
    }

    return parentResult;
  }
}
