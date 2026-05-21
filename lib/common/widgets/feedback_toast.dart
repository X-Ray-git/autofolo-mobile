import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

enum FeedbackTone { info, success, warning, error }

abstract final class AppFeedback {
  static void info(String title, String message) {
    _show(title: title, message: message, tone: FeedbackTone.info);
  }

  static void success(String title, String message) {
    _show(title: title, message: message, tone: FeedbackTone.success);
  }

  static void warning(String title, String message) {
    _show(title: title, message: message, tone: FeedbackTone.warning);
  }

  static void error(String title, String message) {
    _show(title: title, message: message, tone: FeedbackTone.error);
  }

  static void _show({
    required String title,
    required String message,
    required FeedbackTone tone,
  }) {
    SmartDialog.showToast(
      '',
      displayTime: const Duration(milliseconds: 2000),
      alignment: Alignment.topCenter,
      clickMaskDismiss: false,
      usePenetrate: true,
      consumeEvent: false,
      // 增加顺畅的位移与淡入淡出（Slide & Fade）组合动画
      animationBuilder: (controller, child, animationParam) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.6), // 从上方滑入
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: controller,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          )),
          child: FadeTransition(
            opacity: controller,
            child: child,
          ),
        );
      },
      builder: (context) => _FeedbackToast(
        title: title,
        message: message,
        tone: tone,
      ),
    );
  }
}

class _FeedbackToast extends StatelessWidget {
  final String title;
  final String message;
  final FeedbackTone tone;

  const _FeedbackToast({
    required this.title,
    required this.message,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 分配各状态的专属色彩与圆润图标
    final (Color accent, IconData icon) = switch (tone) {
      FeedbackTone.info => (cs.primary, Icons.info_rounded),
      FeedbackTone.success => (const Color(0xFF10B981), Icons.check_circle_rounded),
      FeedbackTone.warning => (const Color(0xFFF59E0B), Icons.warning_rounded),
      FeedbackTone.error => (cs.error, Icons.error_rounded),
    };

    // 背景色：采用与当前亮度适配的半透明基色，以衬托毛玻璃效果
    final bgColor = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
        : const Color(0xFFF9F9F9).withValues(alpha: 0.85);

    final foreground = cs.onSurface;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, left: 24, right: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999), // 完美的胶囊状
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.25),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 图标底座：带微弱透明度的强调色圆圈
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 20, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: foreground,
                            ),
                          ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: foreground.withValues(alpha: 0.75),
                                height: 1.2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8), // 右侧流出呼吸空间
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}