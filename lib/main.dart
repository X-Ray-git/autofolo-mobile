import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'common/constants/constants.dart';
import 'common/widgets/loading_widget.dart';
import 'http/init.dart';
import 'router/app_pages.dart';
import 'services/account_service.dart';
import 'utils/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化存储
  await GStorage.init();

  // 初始化网络请求
  Request();

  // 注册服务
  Get.put(AccountService());

  // 设置状态栏样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // 设置沉浸式状态栏
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 设置高帧率（Android）
  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      debugPrint('Error setting high refresh rate: $e');
    }
  }

  runApp(const FoloReaderApp());
}

/// 应用入口
class FoloReaderApp extends StatelessWidget {
  const FoloReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightScheme, darkScheme) {
        final light = lightScheme ?? _defaultLightScheme;
        final dark = darkScheme ?? _defaultDarkScheme;

        return GetMaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,

          // 多语言
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          locale: const Locale('zh', 'CN'),
          fallbackLocale: const Locale('en', 'US'),

          // 路由
          getPages: appPages,
          initialRoute: Routes.main,
          defaultTransition: Transition.native,

          // 主题
          theme: ThemeData(
            colorScheme: light,
            useMaterial3: true,
            brightness: Brightness.light,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              },
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: dark,
            useMaterial3: true,
            brightness: Brightness.dark,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              },
            ),
          ),
          themeMode: ThemeMode.system,

          // SmartDialog
          builder: FlutterSmartDialog.init(
            toastBuilder: (String msg) => _CustomToast(msg: msg),
            loadingBuilder: (msg) => LoadingWidget(msg: msg),
          ),
          navigatorObservers: [FlutterSmartDialog.observer],
        );
      },
    );
  }

  static final _defaultLightScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0A66C2),
    brightness: Brightness.light,
  );

  static final _defaultDarkScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0A66C2),
    brightness: Brightness.dark,
  );
}

/// 自定义 Toast
class _CustomToast extends StatelessWidget {
  final String msg;

  const _CustomToast({required this.msg});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        msg,
        style: TextStyle(color: colorScheme.onInverseSurface, fontSize: 13),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
