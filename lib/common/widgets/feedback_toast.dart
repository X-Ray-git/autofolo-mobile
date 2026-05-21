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
      displayTime: const Duration(milliseconds: 1500),
      alignment: Alignment.bottomCenter,
      clickMaskDismiss: false,
      usePenetrate: true,
      consumeEvent: false,
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

    final (Color accent, Color background, Color foreground, IconData icon) =
        switch (tone) {
      FeedbackTone.info => (
          cs.primary,
          cs.primaryContainer,
          cs.onPrimaryContainer,
          Icons.info_outline,
        ),
      FeedbackTone.success => (
          const Color(0xFF16A34A),
          isDark
              ? const Color(0xFF052E16)
              : const Color(0xFFDCFCE7),
          isDark ? const Color(0xFFBBF7D0) : const Color(0xFF166534),
          Icons.check_circle_outline,
        ),
      FeedbackTone.warning => (
          const Color(0xFFD97706),
          isDark
              ? const Color(0xFF451A03)
              : const Color(0xFFFEF3C7),
          isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
          Icons.report_outlined,
        ),
      FeedbackTone.error => (
          cs.error,
          cs.errorContainer,
          cs.onErrorContainer,
          Icons.error_outline,
        ),
    };

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(icon, size: 20, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
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
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            color: foreground.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
