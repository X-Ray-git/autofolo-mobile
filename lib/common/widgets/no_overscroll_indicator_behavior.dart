import 'package:flutter/material.dart';

/// 禁用所有 overscroll 指示器（Glow / Stretch）。
///
/// 用于配合 [RefreshIndicator] 使用——RefreshIndicator 自己管理下拉刷新的
/// 视觉效果，不需要平台自带的发光/拉伸动画干扰。
class NoOverscrollIndicatorBehavior extends MaterialScrollBehavior {
  const NoOverscrollIndicatorBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // 不添加任何平台指示器，直接返回 child
    return child;
  }
}
