import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import 'common/constants/constants.dart';
import 'common/widgets/loading_widget.dart';
import 'http/init.dart';
import 'router/app_pages.dart';
import 'services/account_service.dart';
import 'utils/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 扩大全局图片内存缓存池到 300MB，解决长列表大图滚动时由于频繁换入换出导致的解码掉帧问题
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 300;

  // 初始化存储
  await GStorage.init();

  // 初始化网络请求
  Request();

  // 注册服务
  Get.put(AccountService());

  // 设置状态栏样式 (全局透明)
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

      // 主题 (注入全局组件规范)
      theme: ThemeData(
        colorScheme: _defaultLightScheme,
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: _defaultLightScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: _defaultLightScheme.surface,
          scrolledUnderElevation: 0, // 全局移除 AppBar 滚动时的生硬投影色
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: _defaultLightScheme.onSurface),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // 全局统一 16px 卡片圆角
          ),
          clipBehavior: Clip.antiAlias,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          },
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: _defaultDarkScheme,
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _defaultDarkScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: _defaultDarkScheme.surface,
          scrolledUnderElevation: 0,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: _defaultDarkScheme.onSurface),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          },
        ),
      ),
      themeMode: ThemeMode.system,

      // SmartDialog 注入毛玻璃版全局基础 Toast
      builder: FlutterSmartDialog.init(
        toastBuilder: (String msg) => _CustomToast(msg: msg),
        loadingBuilder: (msg) => LoadingWidget(msg: msg),
      ),
      navigatorObservers: [FlutterSmartDialog.observer],
    );
  }

  // ── Folo UIKit 配色 ──────────────────────────
  // accent: #FF5C00 · 表面: 中性灰白 · 文字: 高对比
  static const _accent = Color(0xFFFF5C00);
  static const _onAccent = Color(0xFFFFFFFF);
  // primary container: 亮/暗两套
  static const _primaryContainerLight = Color(0xFFFFD4B8);
  static const _onPrimaryContainerLight = Color(0xFF331100);
  static const _primaryContainerDark = Color(0xFF5C2800);
  static const _onPrimaryContainerDark = Color(0xFFFFD4B8);

  static final _defaultLightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: _accent,
    onPrimary: _onAccent,
    primaryContainer: _primaryContainerLight,
    onPrimaryContainer: _onPrimaryContainerLight,
    secondary: _accent,
    onSecondary: _onAccent,
    error: const Color(0xFFBA1A1A),
    onError: const Color(0xFFFFFFFF),
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410002),
    surface: const Color(0xFFFAFAFA),
    onSurface: const Color(0xFF1C1B1F),
    surfaceContainerHighest: const Color(0xFFEDEDED),
    surfaceContainerLow: const Color(0xFFF5F5F5),
    surfaceContainer: const Color(0xFFF0F0F0),
    surfaceContainerHigh: const Color(0xFFE8E8E8),
    onSurfaceVariant: const Color(0xFF666666),
    outline: const Color(0xFF8E8E93),
    outlineVariant: const Color(0xFFDEDEDE),
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: const Color(0xFF313033),
    onInverseSurface: const Color(0xFFF4EFF4),
    inversePrimary: const Color(0xFFD96E2C),
  );

  static final _defaultDarkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _accent,
    onPrimary: _onAccent,
    primaryContainer: _primaryContainerDark,
    onPrimaryContainer: _onPrimaryContainerDark,
    secondary: _accent,
    onSecondary: _onAccent,
    error: const Color(0xFFFFB4AB),
    onError: const Color(0xFF690005),
    errorContainer: const Color(0xFF93000A),
    onErrorContainer: const Color(0xFFFFDAD6),
    surface: const Color(0xFF1A1A1C),
    onSurface: const Color(0xFFE6E1E5),
    surfaceContainerHighest: const Color(0xFF3A3A3C),
    surfaceContainerLow: const Color(0xFF2C2C2E),
    surfaceContainer: const Color(0xFF333336),
    surfaceContainerHigh: const Color(0xFF444446),
    onSurfaceVariant: const Color(0xFFBEBEC3),
    outline: const Color(0xFF636366),
    outlineVariant: const Color(0xFF3A3A3C),
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: const Color(0xFFE6E1E5),
    onInverseSurface: const Color(0xFF313033),
    inversePrimary: const Color(0xFFD96E2C),
  );
}

/// 全局基础 Toast (毛玻璃胶囊形态)
/// 作为未调用 AppFeedback 时的全局兜底方案，保持视觉大一统。
class _CustomToast extends StatelessWidget {
  final String msg;

  const _CustomToast({required this.msg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 背景色：采用与当前亮度适配的半透明基色，以衬托毛玻璃效果
    final bgColor = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
        : const Color(0xFFF9F9F9).withValues(alpha: 0.85);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.only(bottom: 48), // 避开底部安全区和可能的导航栏
        constraints: const BoxConstraints(maxWidth: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                msg,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}