import 'package:flutter/material.dart';

/// 一个轻量级的 CSS 颜色解析器。
class ColorParser {
  static const Map<String, Color> _namedColors = {
    'black': Colors.black,
    'white': Colors.white,
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'yellow': Colors.yellow,
    'cyan': Colors.cyan,
    'magenta': Colors.purpleAccent,
    'gray': Colors.grey,
    'grey': Colors.grey,
    'transparent': Colors.transparent,
  };

  /// 尝试从 CSS 颜色字符串中解析出 Flutter [Color] 对象。
  /// 支持格式：#RGB, #RRGGBB, rgb(r, g, b), rgba(r, g, b, a), 以及常见颜色名。
  /// 如果解析失败，返回 null。
  static Color? parseCssColor(String? colorString) {
    if (colorString == null || colorString.trim().isEmpty) return null;
    final colorStr = colorString.trim().toLowerCase();

    if (_namedColors.containsKey(colorStr)) {
      return _namedColors[colorStr];
    }

    if (colorStr.startsWith('#')) {
      final hex = colorStr.substring(1);
      if (hex.length == 3) {
        // #RGB -> #RRGGBB
        final r = hex[0] + hex[0];
        final g = hex[1] + hex[1];
        final b = hex[2] + hex[2];
        return Color(int.parse('0xFF$r$g$b'));
      } else if (hex.length == 6) {
        return Color(int.parse('0xFF$hex'));
      } else if (hex.length == 8) {
        // CSS is #RRGGBBAA, Flutter is 0xAARRGGBB
        final rrggbb = hex.substring(0, 6);
        final aa = hex.substring(6, 8);
        return Color(int.parse('0x$aa$rrggbb'));
      }
      return null;
    }

    if (colorStr.startsWith('rgba')) {
      final match = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)').firstMatch(colorStr);
      if (match != null) {
        final r = int.tryParse(match.group(1) ?? '0') ?? 0;
        final g = int.tryParse(match.group(2) ?? '0') ?? 0;
        final b = int.tryParse(match.group(3) ?? '0') ?? 0;
        final aText = match.group(4);
        final a = aText != null ? (double.tryParse(aText) ?? 1.0) : 1.0;
        return Color.fromRGBO(r, g, b, a);
      }
    } else if (colorStr.startsWith('rgb')) {
      final match = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(colorStr);
      if (match != null) {
        final r = int.tryParse(match.group(1) ?? '0') ?? 0;
        final g = int.tryParse(match.group(2) ?? '0') ?? 0;
        final b = int.tryParse(match.group(3) ?? '0') ?? 0;
        return Color.fromRGBO(r, g, b, 1.0);
      }
    }

    return null;
  }

  /// 将 Flutter [Color] 转换为 CSS rgba 字符串。
  static String toCssString(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return 'rgba($r, $g, $b, ${color.a.toStringAsFixed(2)})';
  }
}
