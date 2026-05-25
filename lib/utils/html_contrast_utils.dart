import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'color_parser.dart';

/// 一个用于调整 HTML 字符串中内联颜色样式的工具类，确保其在特定背景色下达到足够的对比度。
class HtmlContrastUtils {
  // 简单的 LRU 缓存，避免在列表滚动时重复解析相同的 HTML 片段
  static final Map<String, String> _cache = {};
  static const int _maxCacheSize = 200;

  /// 调整 HTML 字符串，使其内部硬编码的颜色在 [backgroundColor] 下具有至少 [minContrast] 的对比度。
  /// 对于深色模式，如果文本颜色过深，会被智能提亮。
  static String adjustHtmlContrast(String html, Color backgroundColor, {double minContrast = 4.5}) {
    if (html.isEmpty) return html;

    // 缓存 Key 组合了背景色和 HTML 内容
    final cacheKey = '${backgroundColor.toARGB32()}_$html';
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      // 简单的 LRU 策略：访问后重新插入到队尾
      _cache.remove(cacheKey);
      _cache[cacheKey] = cached;
      return cached;
    }

    // 解析 HTML 片段
    final fragment = html_parser.parseFragment(html);
    bool changed = _processNode(fragment, backgroundColor, minContrast);

    final result = changed ? fragment.outerHtml : html;

    // 维护缓存大小
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = result;

    return result;
  }

  static bool _processNode(dom.Node node, Color bg, double minContrast) {
    bool changed = false;

    if (node is dom.Element) {
      // 1. 处理 style 属性 (如 style="color: #333333;")
      if (node.attributes.containsKey('style')) {
        final styleStr = node.attributes['style'];
        if (styleStr != null && styleStr.isNotEmpty) {
          final newStyle = _adjustStyleString(styleStr, bg, minContrast);
          if (newStyle != styleStr) {
            node.attributes['style'] = newStyle;
            changed = true;
          }
        }
      }

      // 2. 处理老旧的 font 标签 (如 <font color="#333333">)
      if (node.localName == 'font' && node.attributes.containsKey('color')) {
        final colorStr = node.attributes['color'];
        if (colorStr != null && colorStr.isNotEmpty) {
          final c = ColorParser.parseCssColor(colorStr);
          if (c != null) {
            final adjusted = _ensureContrast(c, bg, minContrast);
            if (adjusted != c) {
              node.attributes['color'] = ColorParser.toCssString(adjusted);
              changed = true;
            }
          }
        }
      }
    }

    // 递归处理子节点
    for (final child in node.nodes) {
      if (_processNode(child, bg, minContrast)) {
        changed = true;
      }
    }

    return changed;
  }

  static String _adjustStyleString(String styleStr, Color bg, double minContrast) {
    final parts = styleStr.split(';');
    bool changed = false;

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) continue;

      final colonIdx = part.indexOf(':');
      if (colonIdx == -1) continue;

      final propName = part.substring(0, colonIdx).trim().toLowerCase();
      final propVal = part.substring(colonIdx + 1).trim();

      if (propName == 'color') {
        final c = ColorParser.parseCssColor(propVal);
        if (c != null) {
          final adjusted = _ensureContrast(c, bg, minContrast);
          if (adjusted != c) {
            parts[i] = '$propName: ${ColorParser.toCssString(adjusted)}';
            changed = true;
          }
        }
      }
      // 如果将来需要处理 background-color，可以在这里扩展。
      // 当前主要解决深色模式下，深色文字看不清的问题。
    }

    if (changed) {
      return parts.join('; ').trim();
    }
    return styleStr;
  }

  /// 确保前景色 [fg] 和背景色 [bg] 之间的对比度不低于 [minContrast]。
  /// 在深色模式下（背景为深色），如果对比度不足，会将前景色逐渐提亮（与白色混合）。
  static Color _ensureContrast(Color fg, Color bg, double minContrast) {
    final double fgLum = fg.computeLuminance();
    final double bgLum = bg.computeLuminance();

    double getRatio(double lum1, double lum2) {
      return (lum1 > lum2)
          ? (lum1 + 0.05) / (lum2 + 0.05)
          : (lum2 + 0.05) / (lum1 + 0.05);
    }

    final double ratio = getRatio(fgLum, bgLum);
    if (ratio >= minContrast) return fg;

    // 获取透明度值，以便在混合后恢复
    // 兼容新版 Flutter Color 属性
    final double alpha = (fg.a).toDouble();

    Color currentFg = fg;
    // 渐进式与白色混合，直到对比度达标（最多 20 步）
    for (int i = 1; i <= 20; i++) {
      final t = i / 20.0;
      currentFg = Color.lerp(fg, Colors.white, t) ?? Colors.white;
      if (getRatio(currentFg.computeLuminance(), bgLum) >= minContrast) {
        break;
      }
    }

    return currentFg.withValues(alpha: alpha);
  }
}
