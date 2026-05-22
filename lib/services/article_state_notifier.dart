import 'package:get/get.dart';

/// 全局文章状态变更通知器。
/// 调用 [tick(entryId)] 通知所有监听页该文章状态已变。
abstract final class ArticleStateNotifier {
  static final version = 0.obs;
  static String? _lastEntryId;

  /// 最近的变更 entryId（消费者读完即清）
  static String? get lastEntryId => _lastEntryId;

  /// 消费者读完后清除，防止后续调用永远走增量路径
  static void clearLastEntryId() => _lastEntryId = null;

  static void tick(String entryId) {
    _lastEntryId = entryId;
    version.value++;
  }
}
