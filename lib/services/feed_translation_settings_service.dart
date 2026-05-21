import '../utils/storage.dart';

/// 管理每个订阅源的自动翻译设置
abstract final class FeedTranslationSettingsService {
  static const String _keyPrefix = 'feed_auto_translate_';

  static bool isAutoTranslateEnabled(String feedId) {
    if (feedId.isEmpty) return false;
    final stored = GStorage.setting.get('$_keyPrefix$feedId');
    return stored is bool ? stored : false;
  }

  static Future<void> setAutoTranslate(String feedId, bool enabled) async {
    if (feedId.isEmpty) return;
    await GStorage.setting.put('$_keyPrefix$feedId', enabled);
  }

  static Future<void> toggleAutoTranslate(String feedId) async {
    if (feedId.isEmpty) return;
    final current = isAutoTranslateEnabled(feedId);
    await setAutoTranslate(feedId, !current);
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
