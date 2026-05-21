import 'package:get/get.dart';

import '../common/constants/constants.dart';
import '../utils/storage.dart';

/// 账号服务 — Token 存取 + 登录状态
class AccountService extends GetxController {
  static AccountService get instance => Get.find<AccountService>();

  final isLoggedIn = false.obs;

  AccountService() {
    _checkLogin();
  }

  void _checkLogin() {
    final token =
        GStorage.setting.get(StorageKeys.sessionToken, defaultValue: '')
            as String;
    final clientId =
        GStorage.setting.get(StorageKeys.clientId, defaultValue: '') as String;
    final sessionId =
        GStorage.setting.get(StorageKeys.sessionId, defaultValue: '') as String;
    isLoggedIn.value =
        token.isNotEmpty && clientId.isNotEmpty && sessionId.isNotEmpty;
  }

  void saveTokens({
    required String sessionToken,
    required String clientId,
    required String sessionId,
  }) {
    GStorage.setting.put(StorageKeys.sessionToken, sessionToken);
    GStorage.setting.put(StorageKeys.clientId, clientId);
    GStorage.setting.put(StorageKeys.sessionId, sessionId);
    isLoggedIn.value = true;
  }

  void clearTokens() {
    GStorage.setting.delete(StorageKeys.sessionToken);
    GStorage.setting.delete(StorageKeys.clientId);
    GStorage.setting.delete(StorageKeys.sessionId);
    isLoggedIn.value = false;
  }

  String? get sessionToken =>
      GStorage.setting.get(StorageKeys.sessionToken) as String?;
  String? get clientId => GStorage.setting.get(StorageKeys.clientId) as String?;
  String? get sessionId =>
      GStorage.setting.get(StorageKeys.sessionId) as String?;
}
