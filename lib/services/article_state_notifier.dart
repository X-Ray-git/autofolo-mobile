import 'package:get/get.dart';

/// 全局文章状态变更通知器。
/// 任何地方改了文章状态（读/未读/过滤/捞回/拒绝），
/// 调 [tick] 一次，所有监听页各自 Obx 感知刷新。
abstract final class ArticleStateNotifier {
  static final version = 0.obs;

  static void tick() {
    version.value++;
  }
}
