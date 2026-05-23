import 'package:flutter/services.dart';

/// 桌面角标控制器（替代已停止维护的 flutter_app_badger）
abstract final class AppBadger {
  static const _channel = MethodChannel('g123k/flutter_app_badger');

  static Future<void> updateBadgeCount(int count) =>
      _channel.invokeMethod('updateBadgeCount', {'count': count});

  static Future<void> removeBadge() =>
      _channel.invokeMethod('removeBadge');
}
