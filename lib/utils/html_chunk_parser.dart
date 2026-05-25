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

  static final _tableTagRe = RegExp(r'<table[>\s]', caseSensitive: false);
  static final _divTagRe = RegExp(r'<div[>\s]', caseSensitive: false);

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

  /// 从包含媒体的标题中提取纯文本（跳过媒体节点）
  static String _headingTextOnly(dom.Element element) {
    final buffer = StringBuffer();
    for (final node in element.nodes) {
      if (node is dom.Text) {
        buffer.write(node.text);
      } else if (node is dom.Element) {
        final tag = node.localName?.toLowerCase() ?? '';
        if (_mediaTags.contains(tag)) continue;
        if (_hasMediaDescendant(node)) continue;
        buffer.write(' ${node.text} ');
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
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

    // 检测邮件 HTML：大量 table 但几乎无 div → 启用表格展平（最多只扫前 50000 字符即可判断）
    final scopeHtml = rawHtml.length > 50000 ? rawHtml.substring(0, 50000) : rawHtml;
    final tableCount = _tableTagRe.allMatches(scopeHtml).length;
    final divCount = _divTagRe.allMatches(scopeHtml).length;
    final isEmail = tableCount > 5 && tableCount > divCount * 2;

    final chunks = <HtmlChunk>[];
    _processMixedNodes(fragment.nodes, chunks, isEmail);

    return _mergeAdjacentParagraphs(chunks);
  }

  static void _processMixedNodes(Iterable<dom.Node> nodes, List<HtmlChunk> chunks, bool isEmail) {
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
          _processElement(child, chunks, isEmail: isEmail);
        } else {
          buffer.write(child.outerHtml);
        }
      } else if (child is dom.Text) {
        buffer.write(child.text);
      }
    }
    flush();
  }

  static void _processElement(dom.Element element, List<HtmlChunk> chunks,
      {bool isEmail = false}) {
    final tag = element.localName?.toLowerCase() ?? '';

    // 标题 — BUGFIX: 有媒体子节点时保留标题文本+单独发媒体块，空标题跳过
    if (_headingTags.contains(tag)) {
      final level = int.tryParse(tag.substring(1)) ?? 1;
      if (_hasMediaDescendant(element)) {
        final text = _headingTextOnly(element);
        if (text.isNotEmpty) {
          chunks.add(HtmlChunk(
            type: HtmlChunkType.heading,
            content: text,
            headingLevel: level,
          ));
        }
        _emitMediaChildren(element, chunks);
        return;
      }
      final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) return; // skip empty spacers like <h3><span><br></span></h3>
      chunks.add(HtmlChunk(
        type: HtmlChunkType.heading,
        content: text,
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

    // 表格 — 邮件模式下展平，递归提取内部内容
    if (tag == 'table') {
      if (isEmail) {
        // 邮件布局 table → 递归提取 p/img/h1-h6，丢弃表格骨架
        final childChunks = <HtmlChunk>[];
        for (final child in element.nodes) {
          if (child is dom.Element) {
            _processElement(child, childChunks, isEmail: true);
          } else if (child is dom.Text) {
            final text = child.text.trim();
            if (text.isNotEmpty) {
              childChunks.add(
                  HtmlChunk(type: HtmlChunkType.paragraph, content: text));
            }
          }
        }
        chunks.addAll(childChunks);
        return;
      }
      chunks.add(HtmlChunk(
        type: HtmlChunkType.table,
        content: element.outerHtml,
      ));
      return;
    }

    // 列表
    if (tag == 'ul' || tag == 'ol') {
      final items = element
          .querySelectorAll('li')
          .map((li) => li.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        chunks.add(HtmlChunk(
          type: HtmlChunkType.list,
          content: '',
          listItems: items,
          attributes: {'ordered': (tag == 'ol').toString()},
        ));
      }
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
      _processMixedNodes(element.nodes, chunks, isEmail);
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
      _processMixedNodes(element.nodes, chunks, isEmail);
      return;
    }

    // figure → 提取内部 img/iframe + figcaption
    if (tag == 'figure') {
      final childChunks = <HtmlChunk>[];
      final nonCaptionNodes = element.nodes.where((n) => 
        !(n is dom.Element && n.localName?.toLowerCase() == 'figcaption')
      );
      _processMixedNodes(nonCaptionNodes, childChunks, isEmail);
      
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
    _processMixedNodes(element.nodes, chunks, isEmail);
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
  static List<HtmlChunk> _mergeAdjacentParagraphs(List<HtmlChunk> chunks) {
    if (chunks.isEmpty) return chunks;

    final merged = <HtmlChunk>[];
    for (final chunk in chunks) {
      if (merged.isNotEmpty &&
          merged.last.type == HtmlChunkType.paragraph &&
          chunk.type == HtmlChunkType.paragraph) {
        
        final combinedLength = merged.last.content.length + chunk.content.length;
        if (combinedLength > 1500) {
          // 合并后过长，强制断开，保护渲染性能
          merged.add(chunk);
        } else {
          // 合并文本
          merged.last = HtmlChunk(
            type: HtmlChunkType.paragraph,
            content: '${merged.last.content}\n\n${chunk.content}',
          );
        }
      } else {
        merged.add(chunk);
      }
    }
    return merged;
  }
}
