import '../utils/storage.dart';

/// 管理每个订阅源的自动提取长文设置
abstract final class FeedReadabilitySettingsService {
  static const String _keyPrefix = 'feed_auto_readability_';

  static bool isAutoReadabilityEnabled(String feedId) {
    if (feedId.isEmpty) return false;
    final stored = GStorage.setting.get('$_keyPrefix$feedId');
    return stored is bool ? stored : false;
  }

  static Future<void> setAutoReadability(String feedId, bool enabled) async {
    if (feedId.isEmpty) return;
    await GStorage.setting.put('$_keyPrefix$feedId', enabled);
  }

  static Future<void> toggleAutoReadability(String feedId) async {
    if (feedId.isEmpty) return;
    final current = isAutoReadabilityEnabled(feedId);
    await setAutoReadability(feedId, !current);
  }

  static Future<void> clearAllSettings() async {
    final keysToDelete = <String>[];
    for (final key in GStorage.setting.keys) {
      if (key is String && key.startsWith(_keyPrefix)) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await GStorage.setting.delete(key);
    }
  }
}
