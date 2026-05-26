import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../../utils/article_content_utils.dart';
import '../../../utils/html_chunk_parser.dart';
import '../../../utils/html_contrast_utils.dart';
import '../../../services/article_image_service.dart';
import 'inline_video_player.dart';

/// 单块渲染器 — 根据 HtmlChunkType 渲染对应 Widget，
/// 自动包裹 RepaintBoundary。
class HtmlChunkCard extends StatelessWidget {
  final HtmlChunk chunk;
  final double maxWidth;
  final void Function(String imageUrl)? onImageTap;

  const HtmlChunkCard({
    super.key,
    required this.chunk,
    required this.maxWidth,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final widget = _buildContent(context);
    if (widget == null) return const SizedBox.shrink();

    // 1. 修复：精准使用隔离层，防止纯文本图层爆炸
    final needsBoundary = chunk.type == HtmlChunkType.image || 
                          chunk.type == HtmlChunkType.iframeVideo;

    return Padding(
      padding: _paddingForType,
      child: needsBoundary ? RepaintBoundary(child: widget) : widget,
    );
  }

  // 优化垂直阅读节奏 (Vertical Rhythm)
  EdgeInsets get _paddingForType => switch (chunk.type) {
    HtmlChunkType.heading => const EdgeInsets.only(top: 24, bottom: 8),
    HtmlChunkType.paragraph => const EdgeInsets.only(bottom: 14),
    HtmlChunkType.image => const EdgeInsets.symmetric(vertical: 12),
    HtmlChunkType.codeBlock => const EdgeInsets.only(bottom: 16),
    HtmlChunkType.blockquote => const EdgeInsets.only(bottom: 16),
    HtmlChunkType.table => const EdgeInsets.only(bottom: 16),
    HtmlChunkType.list => const EdgeInsets.only(bottom: 14),
    HtmlChunkType.horizontalRule => const EdgeInsets.symmetric(vertical: 16),
    HtmlChunkType.iframeVideo => const EdgeInsets.symmetric(vertical: 12),
    HtmlChunkType.rawHtml => const EdgeInsets.only(bottom: 14),
  };

  Widget? _buildContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return switch (chunk.type) {
      HtmlChunkType.heading => _buildHeading(context, colorScheme),
      HtmlChunkType.paragraph => _buildParagraph(context, colorScheme),
      HtmlChunkType.image => _buildImage(context),
      HtmlChunkType.codeBlock => _buildCodeBlock(context, colorScheme),
      HtmlChunkType.blockquote => _buildBlockquote(context, colorScheme),
      HtmlChunkType.table => _buildTable(context, colorScheme),
      HtmlChunkType.list => _buildList(context, colorScheme),
      HtmlChunkType.horizontalRule => _buildDivider(colorScheme),
      HtmlChunkType.iframeVideo => _buildMediaPlaceholder(context, colorScheme),
      HtmlChunkType.rawHtml => _buildRawHtml(context, colorScheme),
    };
  }

  Future<void> _handleLinkTap(String? url, Map<String, String> attributes, dynamic element) async {
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // ── 标题 ──

  Widget _buildHeading(BuildContext context, ColorScheme cs) {
    final fontSize = switch (chunk.headingLevel) {
      1 => 24.0,
      2 => 20.0,
      3 => 18.0,
      4 => 16.0,
      _ => 15.0,
    };
    String htmlData = chunk.content;
    if (Theme.of(context).brightness == Brightness.dark) {
      htmlData = HtmlContrastUtils.adjustHtmlContrast(htmlData, cs.surface);
    }
    return Html(
      data: htmlData,
      onLinkTap: _handleLinkTap,
      style: {
        'body': Style(
          fontSize: FontSize(fontSize),
          fontWeight: FontWeight.bold,
          color: cs.onSurface,
          lineHeight: const LineHeight(1.35),
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'a': Style(color: cs.primary, textDecoration: TextDecoration.none),
      },
    );
  }

  // ── 段落 ──

  Widget _buildParagraph(BuildContext context, ColorScheme cs) {
    String htmlData = '<p>${chunk.content}</p>';
    if (Theme.of(context).brightness == Brightness.dark) {
      htmlData = HtmlContrastUtils.adjustHtmlContrast(htmlData, cs.surface);
    }
    return Html(
      data: htmlData,
      onLinkTap: _handleLinkTap,
      style: {
        'p': Style(
          fontSize: FontSize(16),
          lineHeight: const LineHeight(1.7),
          color: cs.onSurface,
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          textAlign: TextAlign.start,
        ),
        'a': Style(color: cs.primary),
        'strong': Style(fontWeight: FontWeight.w700),
        'em': Style(fontStyle: FontStyle.italic),
        'code': Style(
          backgroundColor: cs.surfaceContainerHighest,
          fontFamily: 'monospace',
          fontSize: FontSize(14),
        ),
      },
    );
  }

  // ── 图片 ──

  Widget _buildImage(BuildContext context) {
    final imageUrl = chunk.normalizedImageUrl;
    if (imageUrl == null) return const SizedBox.shrink();
    return _ArticleInlineImage(
      imageUrl: imageUrl,
      maxWidth: maxWidth,
      imageWidth: chunk.imageWidth,
      imageHeight: chunk.imageHeight,
      style: chunk.attributes['style'],
      className: chunk.attributes['class'],
      onTap: onImageTap,
    );
  }

  // ── 代码块 ──

  Widget _buildCodeBlock(BuildContext context, ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          chunk.content,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: cs.onSurface,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  // ── 引用 ──

  Widget _buildBlockquote(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(left: BorderSide(color: cs.primary, width: 4)),
      ),
      child: Html(
        data: Theme.of(context).brightness == Brightness.dark
            ? HtmlContrastUtils.adjustHtmlContrast(chunk.content, cs.surface)
            : chunk.content,
        onLinkTap: _handleLinkTap,
        style: {
          'body': Style(
            fontSize: FontSize(15),
            lineHeight: const LineHeight(1.6),
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
          ),
          'a': Style(color: cs.primary),
        },
        extensions: [_imageExtension(context)],
      ),
    );
  }

  // ── 表格 ──

  Widget _buildTable(BuildContext context, ColorScheme cs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Html(
        data: Theme.of(context).brightness == Brightness.dark
            ? HtmlContrastUtils.adjustHtmlContrast(chunk.content, cs.surface)
            : chunk.content,
        onLinkTap: _handleLinkTap,
        style: {
          'table': Style(
            border: Border.all(color: cs.outlineVariant),
            fontSize: FontSize(14),
          ),
          'th': Style(
            backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            fontWeight: FontWeight.w700,
            padding: HtmlPaddings.symmetric(horizontal: 10, vertical: 8),
          ),
          'td': Style(
            padding: HtmlPaddings.symmetric(horizontal: 10, vertical: 8),
          ),
        },
        extensions: [_imageExtension(context)],
      ),
    );
  }

  // ── 列表 ──

  Widget _buildList(BuildContext context, ColorScheme cs) {
    final isOrdered = chunk.attributes['ordered'] == 'true';
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: chunk.listItems.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;

          String htmlData = item;
          if (Theme.of(context).brightness == Brightness.dark) {
            htmlData = HtmlContrastUtils.adjustHtmlContrast(htmlData, cs.surface);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    isOrdered ? '${i + 1}.' : '•',
                    style: TextStyle(
                      fontSize: 16,
                      color: cs.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Html(
                    data: htmlData,
                    onLinkTap: _handleLinkTap,
                    style: {
                      'body': Style(
                        fontSize: FontSize(16),
                        color: cs.onSurface,
                        lineHeight: const LineHeight(1.5),
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                      ),
                      'a': Style(color: cs.primary, textDecoration: TextDecoration.none),
                    },
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 分割线 ──

  Widget _buildDivider(ColorScheme cs) {
    return Divider(color: cs.outlineVariant, height: 1);
  }

  // ── 媒体占位 ──

  Widget _buildMediaPlaceholder(BuildContext context, ColorScheme cs) {
    final isVideo = chunk.attributes['mediaTag'] == 'video';
    final videoUrl = chunk.imageSrc;
    final posterUrl = chunk.posterSrc != null
        ? ArticleImageService.toProxiedUrl(chunk.posterSrc)
        : null;
    final aspectRatio = (chunk.imageWidth != null &&
            chunk.imageHeight != null &&
            chunk.imageHeight! > 0)
        ? chunk.imageWidth! / chunk.imageHeight!
        : 16 / 9;

    // 视频 → 内联播放器
    if (isVideo && videoUrl != null && videoUrl.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InlineVideoPlayer(
          videoUrl: videoUrl,
          posterUrl: posterUrl,
          aspectRatio: aspectRatio,
        ),
      );
    }

    // iframe / 其他 → 静态占位 + 浏览器打开
    return _buildIframePlaceholder(context, cs, aspectRatio);
  }

  Widget _buildIframePlaceholder(BuildContext context, ColorScheme cs, double aspectRatio) {
    final url = chunk.imageSrc;
    final posterUrl = chunk.posterSrc != null
        ? ArticleImageService.toProxiedUrl(chunk.posterSrc)
        : null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 400),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景：poster 图片 或 纯色
              if (posterUrl != null)
                CachedNetworkImage(
                  imageUrl: posterUrl,
                  httpHeaders: ArticleImageService.httpHeaders,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 250),
                  fadeOutDuration: const Duration(milliseconds: 80),
                  placeholder: (context, url) =>
                      Container(color: cs.surfaceContainerHighest),
                  errorWidget: (context, url, error) =>
                      Container(color: cs.surfaceContainerHighest),
                )
              else
                Container(color: cs.surfaceContainerHighest),

              // 渐变暗角遮罩，提升整体质感，代替生硬的纯黑透明度
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
              
              // 居中毛玻璃按钮
              Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: InkWell(
                      onTap: () async {
                        if (url != null && url.isNotEmpty) {
                          final uri = Uri.tryParse(url);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: cs.onPrimaryContainer.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.language,
                          size: 32,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 底部标签：毛玻璃药丸风格
              Positioned(
                bottom: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, size: 12, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            '外部网页',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 兜底 HTML ──

  Widget _buildRawHtml(BuildContext context, ColorScheme cs) {
    return Html(
      data: Theme.of(context).brightness == Brightness.dark
          ? HtmlContrastUtils.adjustHtmlContrast(chunk.content, cs.surface)
          : chunk.content,
      onLinkTap: _handleLinkTap,
      style: {
        'body': Style(
          fontSize: FontSize(16),
          lineHeight: const LineHeight(1.7),
          color: cs.onSurface,
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'a': Style(color: cs.primary),
      },
      extensions: [_imageExtension(context)],
    );
  }

  /// 共享的图片渲染扩展：使用 CachedNetworkImage + 统一请求头 + 点击放大
  ImageExtension _imageExtension(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (maxWidth * dpr).round();

    return ImageExtension(
      builder: (extensionContext) {
        final imageUrl = ArticleContentUtils.imageUrlFromAttributes(
          extensionContext.attributes,
        );
        if (imageUrl == null) {
          return const SizedBox.shrink();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            cacheKey: 'v2_$imageUrl',
            httpHeaders: ArticleImageService.httpHeaders,
            fit: BoxFit.contain,
            width: maxWidth,
            memCacheWidth: cacheWidth,
            maxWidthDiskCache: cacheWidth * 2,
            fadeInDuration: const Duration(milliseconds: 80),
            fadeOutDuration: const Duration(milliseconds: 80),
            placeholder: (context, url) => Container(
              height: 180,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.35),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: 120,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.2),
              child: const Center(
                child: Icon(Icons.broken_image_outlined, size: 36),
              ),
            ),
            imageBuilder: (context, imageProvider) {
              if (onImageTap != null) {
                return GestureDetector(
                  onTap: () => onImageTap!(imageUrl),
                  child: Image(image: imageProvider, fit: BoxFit.contain),
                );
              }
              return Image(image: imageProvider, fit: BoxFit.contain);
            },
          ),
        );
      },
    );
  }
}

// 2. 修复：混入 AutomaticKeepAliveClientMixin 以保持状态存活
class _ArticleInlineImage extends StatefulWidget {
  final String imageUrl;
  final double maxWidth;
  final double? imageWidth;
  final double? imageHeight;
  final String? style;
  final String? className;
  final void Function(String imageUrl)? onTap;

  const _ArticleInlineImage({
    required this.imageUrl,
    required this.maxWidth,
    this.imageWidth,
    this.imageHeight,
    this.style,
    this.className,
    this.onTap,
  });

  @override
  State<_ArticleInlineImage> createState() => _ArticleInlineImageState();
}

class _ArticleInlineImageState extends State<_ArticleInlineImage> with AutomaticKeepAliveClientMixin {
  int _retryCount = 0;

  @override
  bool get wantKeepAlive => true; // 告诉 ListView 不要在滑出屏幕时销毁该组件

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须在首行调用 super.build(context)

    final cs = Theme.of(context).colorScheme;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (widget.maxWidth * dpr).round();
    final hasHeightStyle =
        RegExp(r'max-height\s*:|height\s*:').hasMatch(widget.style ?? '');
    final isCutOff =
        (widget.className ?? '').contains('cut-off') || hasHeightStyle;

    // 仅在有可靠像素尺寸时约束比例；否则让图片自适应
    final hasRealDimensions = widget.imageWidth != null &&
        widget.imageHeight != null &&
        widget.imageHeight! > 0 &&
        widget.imageWidth! > 0;
    final aspectRatio =
        hasRealDimensions ? widget.imageWidth! / widget.imageHeight! : null;

    final canTap = widget.onTap != null;
    final imageUrl = ArticleImageService.appendRetryStamp(
      widget.imageUrl,
      _retryCount,
    );

    Widget image = Hero(
      tag: widget.imageUrl,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        cacheKey: 'v2_$imageUrl',
        httpHeaders: ArticleImageService.httpHeaders,
        fit: BoxFit.contain,
        width: widget.maxWidth,
        // 有可靠尺寸时用 AspectRatio 精确控制；否则不设 height，自适应
        height: hasRealDimensions
            ? (widget.maxWidth / aspectRatio!).clamp(40.0, 420.0)
            : null,
        memCacheWidth: cacheWidth,
        maxWidthDiskCache: cacheWidth * 2,
        fadeInDuration: const Duration(milliseconds: 250),
        fadeOutDuration: const Duration(milliseconds: 80),
        placeholder: (context, url) => SizedBox(
          width: widget.maxWidth,
          height: hasRealDimensions
              ? (widget.maxWidth / aspectRatio!).clamp(40.0, 420.0)
              : (isCutOff ? 220.0 : 100.0),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _ImageErrorWidget(
          cs: cs,
          onRetry: () => setState(() => _retryCount++),
        ),
      ),
    );

    if (canTap) {
      image = InkWell(
        onTap: () => widget.onTap!(widget.imageUrl),
        child: image,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth,
        maxHeight: isCutOff ? 260.0 : 420.0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          // 3. 修复：移除 IntrinsicHeight 和 Stack，直接返回 image
          child: image,
        ),
      ),
    );
  }
}

class _ImageErrorWidget extends StatelessWidget {
  final ColorScheme cs;
  final VoidCallback onRetry;
  const _ImageErrorWidget({required this.cs, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onRetry,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: cs.onSurfaceVariant,
            size: 36,
          ),
          const SizedBox(height: 6),
          Text(
            '图片加载失败',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}