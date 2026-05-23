import 'package:flutter/services.dart';

/// 桌面角标控制器
/// Vivo/OriginOS：直写 ContentProvider，通知栏干净
/// 其他厂商：静默 Notification 兜底
abstract final class AppBadger {
  static const _channel = MethodChannel('com.autofolo/badge');

  static Future<void> updateBadgeCount(int count) =>
      _channel.invokeMethod('updateBadge', {'count': count});

  static Future<void> removeBadge() =>
      _channel.invokeMethod('removeBadge');
}
