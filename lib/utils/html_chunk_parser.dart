import 'dart:isolate';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../services/article_image_service.dart';

enum HtmlChunkType {
  heading,
  paragraph,
  image,
  codeBlock,
  blockquote,
  table,
  list,
  horizontalRule,
  iframeVideo,
  rawHtml,
}

class HtmlChunk {
  final HtmlChunkType type;
  final String content;
  final Map<String, String> attributes;
  final int? headingLevel;
  final double? imageWidth;
  final double? imageHeight;
  final String? imageSrc;
  final String? imageAlt;
  final String? posterSrc;
  final List<String> listItems;

  const HtmlChunk({
    required this.type,
    required this.content,
    this.attributes = const {},
    this.headingLevel,
    this.imageWidth,
    this.imageHeight,
    this.imageSrc,
    this.imageAlt,
    this.posterSrc,
    this.listItems = const [],
  });

  String? get normalizedImageUrl {
    if (imageSrc == null) return null;
    return ArticleImageService.toProxiedUrl(imageSrc);
  }

  /// 预估该块在屏幕上的高度（像素），用于占位 SizedBox。
  /// 不做精确计算，误差在 ±30% 以内即可，避免图片加载后大幅跳布局。
  double get estimatedHeight {
    const double charPerLine = 42; // 混合中英文，16px 字号在 ~340px 宽下的粗略每行字符数
    const double lineH = 27.0; // ~16px * 1.7 行高

    switch (type) {
      case HtmlChunkType.heading:
        final lines =
            (content.length / charPerLine).ceil().clamp(1, 5).toDouble();
        final fontSize = switch (headingLevel) {
          1 => 24.0,
          2 => 20.0,
          3 => 18.0,
          4 => 16.0,
          _ => 15.0,
        };
        return lines * fontSize * 1.35 + 32; // 24 top + 8 bottom
      case HtmlChunkType.paragraph:
        final lines =
            (content.length / charPerLine).ceil().clamp(1, 100).toDouble();
        return lines * lineH + 14;
      case HtmlChunkType.image:
        if (imageWidth != null &&
            imageHeight != null &&
            imageHeight! > 0 &&
            imageWidth! > 0) {
          // 有实际尺寸 → 按比例估算渲染高度
          final ratio = imageHeight! / imageWidth!;
          return (340 * ratio).clamp(40, 420) + 24;
        }
        return 220; // 无尺寸 → 保守默认值
      case HtmlChunkType.codeBlock:
        final lines = content.split('\n').length.clamp(1, 50).toDouble();
        return lines * 20 + 24;
      case HtmlChunkType.blockquote:
        final lines =
            (content.length / charPerLine).ceil().clamp(1, 50).toDouble();
        return lines * 24 + 24;
      case HtmlChunkType.table:
        return 120;
      case HtmlChunkType.list:
        final lines =
            (content.length / charPerLine).ceil().clamp(1, 30).toDouble();
        return lines * 24 + 14;
      case HtmlChunkType.horizontalRule:
        return 32;
      case HtmlChunkType.iframeVideo:
        return 250;
      case HtmlChunkType.rawHtml:
        final lines =
            (content.length / charPerLine).ceil().clamp(1, 50).toDouble();
        return lines * lineH + 14;
    }
  }
}

/// HTML 块解析器 — 将完整 HTML 拆分为可逐块渲染的模型列表。
///
/// 策略：DOM 深度遍历，每个块级元素（或特殊内联元素如 img/iframe）
/// 独立成一个 HtmlChunk。文本节点合并到最近的块级父元素。
///
/// 性能：单篇 200KB 以内 HTML 主线程解析 < 50ms；
/// >500KB 自动切 Isolate.run() 避免卡 UI。
abstract final class HtmlChunkParser {
  static const int _isolateThresholdBytes = 500 * 1024;

  static const _containerTags = {
    'div',
    'section',
    'article',
    'header',
    'footer',
    'main',
    'aside',
  };

  static const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};


  static const _mediaTags = {
    'img', 'iframe', 'video', 'audio', 'table', 'pre', 'code',
    'blockquote', 'ul', 'ol', 'hr',
  };

  /// 递归检查元素是否包含媒体子节点（图片/视频/表格等）
  static bool _hasMediaDescendant(dom.Element element) {
    for (final child in element.nodes) {
      if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        if (_mediaTags.contains(tag)) return true;
        if (_hasMediaDescendant(child)) return true;
      }
    }
    return false;
  }

  /// 从包含媒体的标题中提取HTML（跳过媒体节点，保留行内标签）
  static String _headingHtmlOnly(dom.Element element) {
    final buffer = StringBuffer();
    for (final node in element.nodes) {
      if (node is dom.Text) {
        buffer.write(node.text);
      } else if (node is dom.Element) {
        final tag = node.localName?.toLowerCase() ?? '';
        if (_mediaTags.contains(tag)) continue;
        if (_hasMediaDescendant(node)) continue;
        buffer.write(node.outerHtml);
      }
    }
    return buffer.toString().trim();
  }

  /// 只发媒体子节点（文本已在标题中捕获）
  static void _emitMediaChildren(dom.Element element, List<HtmlChunk> chunks) {
    for (final child in element.nodes) {
      if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        if (_mediaTags.contains(tag) || _headingTags.contains(tag) || tag == 'source') {
          _processElement(child, chunks);
        } else if (_hasMediaDescendant(child)) {
          _emitMediaChildren(child, chunks);
        }
      }
    }
  }

  static Future<List<HtmlChunk>> parse(String rawHtml) async {
    if (rawHtml.trim().isEmpty) return const [];

    if (rawHtml.length > _isolateThresholdBytes) {
      return await Isolate.run(() => _parseSync(rawHtml));
    }
    return _parseSync(rawHtml);
  }

  static List<HtmlChunk> parseSync(String rawHtml) => _parseSync(rawHtml);

  static List<HtmlChunk> _parseSync(String rawHtml) {
    final fragment = html_parser.parseFragment(rawHtml);

    final chunks = <HtmlChunk>[];
    _processMixedNodes(fragment.nodes, chunks);

    return _mergeAdjacentParagraphs(chunks);
  }

  static void _processMixedNodes(Iterable<dom.Node> nodes, List<HtmlChunk> chunks) {
    final buffer = StringBuffer();
    void flush() {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        chunks.add(HtmlChunk(type: HtmlChunkType.paragraph, content: text));
      }
      buffer.clear();
    }

    for (final child in nodes) {
      if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        
        // 过滤无用的内联样式和脚本，避免引发 flutter_html 渲染性能灾难和破坏 App 主题
        if (tag == 'style' || tag == 'script' || tag == 'link' || tag == 'meta') {
          continue;
        }
        
        final isBlockLike = _containerTags.contains(tag) || tag == 'p' || 
                            _headingTags.contains(tag) || 
                            tag == 'table' || 
                            tag == 'ul' || tag == 'ol' || 
                            tag == 'hr' || 
                            tag == 'figure' || 
                            tag == 'blockquote' ||
                            tag == 'pre' || tag == 'code';
        if (_mediaTags.contains(tag) || isBlockLike || _hasMediaDescendant(child)) {
          flush();
          _processElement(child, chunks);
        } else {
          buffer.write(child.outerHtml);
        }
      } else if (child is dom.Text) {
        buffer.write(child.text);
      }
    }
    flush();
  }

  static void _processElement(dom.Element element, List<HtmlChunk> chunks) {
    final tag = element.localName?.toLowerCase() ?? '';

    // 标题 — BUGFIX: 有媒体子节点时保留标题文本+单独发媒体块，空标题跳过
    if (_headingTags.contains(tag)) {
      final level = int.tryParse(tag.substring(1)) ?? 1;
      if (_hasMediaDescendant(element)) {
        final htmlContent = _headingHtmlOnly(element);
        if (htmlContent.isNotEmpty) {
          chunks.add(HtmlChunk(
            type: HtmlChunkType.heading,
            content: htmlContent,
            headingLevel: level,
          ));
        }
        _emitMediaChildren(element, chunks);
        return;
      }
      if (element.text.trim().isEmpty) return; // skip empty spacers like <h3><span><br></span></h3>
      final htmlContent = element.innerHtml.trim();
      chunks.add(HtmlChunk(
        type: HtmlChunkType.heading,
        content: htmlContent,
        headingLevel: level,
      ));
      return;
    }

    // 图片 — 跳过无 src 的占位图
    if (tag == 'img') {
      final src = _extractSrc(element);
      if (src.isEmpty) return; // 无有效 src（如 CSS background 占位），跳过
      final (w, h) = _extractDimensions(element);
      chunks.add(HtmlChunk(
        type: HtmlChunkType.image,
        content: '',
        imageSrc: src,
        imageWidth: w,
        imageHeight: h,
        imageAlt:
            element.attributes['alt'] ?? element.attributes['title'] ?? '',
      ));
      return;
    }

    // iframe / video / audio → 降级为占位卡片
    if (tag == 'iframe' || tag == 'video' || tag == 'audio') {
      var src = _extractSrc(element);
      // <video> with <source> children: extract src from first <source>
      if (src.isEmpty && tag == 'video') {
        final source = element.querySelector('source[src]');
        if (source != null) {
          src = (source.attributes['src'] ?? '').trim();
        }
      }
      final poster = (element.attributes['poster'] ?? '').trim();
      final (w, h) = _extractDimensions(element);
      chunks.add(HtmlChunk(
        type: HtmlChunkType.iframeVideo,
        content: '',
        imageSrc: src.isEmpty ? null : src,
        posterSrc: poster.isEmpty ? null : poster,
        imageWidth: w,
        imageHeight: h,
        attributes: {if (tag != 'iframe') 'mediaTag': tag},
      ));
      return;
    }

    // 代码块 - 回退为提取纯文本，降低渲染负担
    if (tag == 'pre' || tag == 'code') {
      chunks.add(HtmlChunk(
        type: HtmlChunkType.codeBlock,
        content: element.text.trim(),
      ));
      return;
    }

    // 引用
    if (tag == 'blockquote') {
      chunks.add(HtmlChunk(
        type: HtmlChunkType.blockquote,
        content: element.innerHtml,
      ));
      return;
    }

    // 表格 — 保持原生结构，交给前端渲染
    if (tag == 'table') {
      chunks.add(HtmlChunk(
        type: HtmlChunkType.table,
        content: element.outerHtml,
      ));
      return;
    }

    // 列表
    if (tag == 'ul' || tag == 'ol') {
      chunks.add(HtmlChunk(
        type: HtmlChunkType.list,
        content: element.outerHtml,
      ));
      return;
    }

    // 分割线
    if (tag == 'hr') {
      chunks.add(HtmlChunk(
        type: HtmlChunkType.horizontalRule,
        content: '',
      ));
      return;
    }

    // 容器标签 → 强制递归处理子节点，避免巨大富文本
    if (_containerTags.contains(tag)) {
      _processMixedNodes(element.nodes, chunks);
      return;
    }

    // 段落标签
    if (tag == 'p') {
      if (!_hasMediaDescendant(element)) {
        final content = element.innerHtml.trim();
        if (content.isNotEmpty) {
          chunks.add(HtmlChunk(type: HtmlChunkType.paragraph, content: content));
        }
        return;
      }
      _processMixedNodes(element.nodes, chunks);
      return;
    }

    // figure → 提取内部 img/iframe + figcaption
    if (tag == 'figure') {
      final childChunks = <HtmlChunk>[];
      final nonCaptionNodes = element.nodes.where((n) => 
        !(n is dom.Element && n.localName?.toLowerCase() == 'figcaption')
      );
      _processMixedNodes(nonCaptionNodes, childChunks);
      
      final caption = element.querySelector('figcaption');
      if (caption != null) {
        final text = caption.innerHtml.trim();
        if (text.isNotEmpty) {
          childChunks.add(HtmlChunk(type: HtmlChunkType.paragraph, content: text));
        }
      }
      chunks.addAll(childChunks);
      return;
    }

    // 未知元素 → 递归子节点（如 <a><img></a>），不再只提取文本导致媒体丢失
    if (!_hasMediaDescendant(element)) {
      final content = element.outerHtml.trim();
      if (content.isNotEmpty) {
        chunks.add(HtmlChunk(type: HtmlChunkType.paragraph, content: content));
      }
      return;
    }
    _processMixedNodes(element.nodes, chunks);
  }

  static String _extractSrc(dom.Element element) {
    // 仅提取原始 URL，不做代理（代理由 normalizedImageUrl 统一处理）
    final raw = (element.attributes['src']) ??
        (element.attributes['data-src']) ??
        (element.attributes['data-original']) ??
        '';
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.startsWith('//') ? 'https:$trimmed' : trimmed;
    return ArticleImageService.normalizeImageUrl(normalized) ?? '';
  }

  static (double?, double?) _extractDimensions(dom.Element element) {
    double? parseDim(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
      final v = double.tryParse(cleaned);
      if (v != null && v > 0) return v;
      return null;
    }

    // 先看 width/height 属性
    var w = parseDim(element.attributes['width']);
    var h = parseDim(element.attributes['height']);

    // 再看 style 中的 width/height — BUGFIX: 百分比宽度不按 px 解析
    if (w == null || h == null) {
      final style = element.attributes['style'] ?? '';
      if (w == null) {
        final m = RegExp(r'width\s*:\s*(\d+(?:\.\d+)?)\s*(px|em|rem|%|vw)?',
                caseSensitive: false)
            .firstMatch(style);
        final val = m?.group(1);
        final unit = m?.group(2);
        if (val != null) {
          if (unit == '%' || unit == 'vw') {
            // 百分比宽度 → 无法确定固定像素值，保持 null 由渲染层 fallback
            w = null;
          } else {
            w = parseDim(val);
          }
        }
      }
      if (h == null) {
        final m = RegExp(r'height\s*:\s*(\d+(?:\.\d+)?)\s*(px|em|rem|%|vh)?',
                caseSensitive: false)
            .firstMatch(style);
        final val = m?.group(1);
        final unit = m?.group(2);
        if (val != null) {
          if (unit == '%' || unit == 'vh') {
            h = null;
          } else {
            h = parseDim(val);
          }
        }
      }
    }

    return (w, h);
  }

  /// 合并相邻的纯文本 paragraph，减少 widget 数量
  /// 注：这里移除了强制拼接大量文本的逻辑，因为如果一次性拼接过长（如 1500 字），
  /// 在滑动时构建单个庞大的 `Html` 组件会导致严重的单帧阻塞（掉帧）。
  /// 只拼接连续的纯文本且适度保持颗粒度，以确保滑动流畅。
  static List<HtmlChunk> _mergeAdjacentParagraphs(List<HtmlChunk> chunks) {
    if (chunks.isEmpty) return chunks;

    final merged = <HtmlChunk>[];
    for (final chunk in chunks) {
      if (merged.isNotEmpty &&
          merged.last.type == HtmlChunkType.paragraph &&
          chunk.type == HtmlChunkType.paragraph) {
        
        // 我们使用 <br><br> 来拼接段落，这样既合并了 Flutter 组件，又完全保留了原有的段落间距排版！
        final combinedLength = merged.last.content.length + chunk.content.length;
        if (combinedLength > 2000) {
          // 合并后过长，强制断开，保护单帧渲染性能
          merged.add(chunk);
        } else {
          // 合并文本，使用 <br><br> 保留段落间距
          merged.last = HtmlChunk(
            type: HtmlChunkType.paragraph,
            content: '${merged.last.content}<br><br>${chunk.content}',
          );
        }
      } else {
        merged.add(chunk);
      }
    }
    return merged;
  }
}
