import 'package:flutter/material.dart';

class ShimmerCard extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerCard({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<ShimmerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: [
                cs.onSurface.withValues(alpha: 0.04),
                cs.onSurface.withValues(alpha: 0.08),
                cs.onSurface.withValues(alpha: 0.04),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 时间线骨架加载
class TimelineSkeleton extends StatelessWidget {
  const TimelineSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(6, (_) => _buildCard(context)),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ShimmerCard(width: 8, height: 8, borderRadius: 4),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      ShimmerCard(height: 14, borderRadius: 4),
                      SizedBox(height: 8),
                      ShimmerCard(height: 14, borderRadius: 4),
                      SizedBox(height: 8),
                      ShimmerCard(width: 120, height: 14, borderRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const ShimmerCard(height: 12, borderRadius: 4),
            const SizedBox(height: 8),
            const ShimmerCard(width: 60, height: 12, borderRadius: 4),
          ],
        ),
      ),
    );
  }
}

/// 共享骨架屏淡入淡出列表 — 封装动画控制器逻辑，消除三处重复代码。
/// 各页面只需传入自己的卡片 builder。
class ShimmerFadeList extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;

  const ShimmerFadeList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.physics,
  });

  @override
  State<ShimmerFadeList> createState() => _ShimmerFadeListState();
}

class _ShimmerFadeListState extends State<ShimmerFadeList>
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
      physics: widget.physics ?? const NeverScrollableScrollPhysics(),
      padding: widget.padding ?? const EdgeInsets.only(top: 6),
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        return FadeTransition(
          opacity: _opacityAnim,
          child: widget.itemBuilder(context, index),
        );
      },
    );
  }
}
