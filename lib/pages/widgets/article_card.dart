import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/pill_tag.dart';
import '../../models/article.dart';
import '../../services/article_image_service.dart';
import '../../services/translation_service.dart';
import '../../services/summary_service.dart';
import '../../utils/source_taxonomy.dart';

/// 文章卡片组件
class ArticleCard extends StatefulWidget {
  final ArticleModel article;
  final VoidCallback? onTap;
  final VoidCallback? onTranslate;
  final bool showFeedTitle;
  final bool showSummary;

  const ArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.onTranslate,
    this.showFeedTitle = true,
    this.showSummary = false,
  });

  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard> {
  late bool _isTranslated;

  @override
  void initState() {
    super.initState();
    _isTranslated = TranslationService.hasTranslation(widget.article.entryId);
  }

  void _onTranslateSuccess() {
    if (mounted) {
      setState(() => _isTranslated = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ArticleCardContent(
      article: widget.article,
      onTap: widget.onTap,
      onTranslate: widget.onTranslate,
      showFeedTitle: widget.showFeedTitle,
      showSummary: widget.showSummary,
      isTranslated: _isTranslated,
      onTranslateSuccess: _onTranslateSuccess,
    );
  }
}

class _ArticleCardContent extends StatelessWidget {
  final ArticleModel article;
  final VoidCallback? onTap;
  final VoidCallback? onTranslate;
  final bool showFeedTitle;
  final bool showSummary;
  final bool isTranslated;
  final VoidCallback? onTranslateSuccess;

  const _ArticleCardContent({
    required this.article,
    this.onTap,
    this.onTranslate,
    required this.showFeedTitle,
    required this.showSummary,
    required this.isTranslated,
    this.onTranslateSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewLabel = SourceTaxonomy.viewLabelFromCategory(article.category);
    final viewColor = SourceTaxonomy.viewColorFromCategory(article.category);
    final categoryLabel = article.subscriptionCategory.trim();

    return Obx(() {
      final record = TranslationService.recordOf(article.entryId);
      final isPending = record?.isPending ?? false;
      final isTranslated =
          (record?.translatedTitle?.isNotEmpty ?? false) ||
          (record?.translatedContent?.isNotEmpty ?? false);
      final displayTitle = TranslationService.displayTitleFor(article);

      return RepaintBoundary(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          clipBehavior: Clip.antiAlias, // 确保内部带色条的 Container 会被完美裁切圆角
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: () =>
                _showTranslateMenu(context, isTranslated, isPending),
            child: Container(
              // 将 AI 拒文左侧色条移至 InkWell 内部，水波纹现在可正常覆盖全卡片
              decoration: article.isRejectedByAi
                  ? BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: colorScheme.primary,
                          width: 4,
                        ),
                      ),
                    )
                  : null,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI 拒文标记优化显示
                  if (article.isRejectedByAi && article.filterReason != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                article.filterReason!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        // 使用 Text.rich 和 WidgetSpan 确保红点与文字第一行绝对对齐，不受字体缩放影响
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (!article.isRead)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              TextSpan(
                                text: displayTitle,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.4,
                                  fontWeight: article.isRead
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                  color: article.isRead
                                      ? colorScheme.onSurface
                                          .withValues(alpha: 0.7)
                                      : colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 翻译状态标签，移除了生硬的透明度叠加，改用规范的 Material 颜色
                      if (isPending) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '翻译中',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (isTranslated) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Tooltip(
                            message: '已翻译',
                            child: Icon(
                              Icons.translate,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (article.author != null && article.author!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      article.author!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (showSummary) ...[
                    const SizedBox(height: 12),
                    _buildSummaryBlock(colorScheme, article.entryId),
                  ] else ...[
                    const SizedBox(height: 12),
                  ],
                  // 底部元信息区域重构：放弃 Wrap 与硬编码宽度，改用 Row + Flexible，保证时间永不换行
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              flex: 0,
                              child: PillTag(
                                label: viewLabel,
                                backgroundColor: viewColor.withValues(
                                  alpha: 0.14,
                                ),
                                foregroundColor: viewColor,
                              ),
                            ),
                            if (categoryLabel.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                flex: 0,
                                child: PillTag(
                                  label: categoryLabel,
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  foregroundColor: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(article.publishedAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (showFeedTitle) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _FeedIcon(
                          imageUrl: article.feedImage,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            article.feedTitle,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildSummaryBlock(ColorScheme cs, String entryId) {
    final record = SummaryService.recordOf(entryId);
    final isDone = record?.status == SummaryStatus.done;
    final text = record?.summaryText;

    final displayContent = (isDone && text != null && text.isNotEmpty)
        ? text
        : 'AI 尚未生成摘要...';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.format_quote_rounded,
            size: 16, color: cs.primary.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            displayContent,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              height: 1.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _translateArticle(BuildContext context) async {
    try {
      await TranslationService.translateArticle(article);
      AppFeedback.success('翻译完成', '已生成文章译文');
    } catch (e) {
      AppFeedback.error('翻译失败', e.toString());
    }
  }

  void _showTranslateMenu(
    BuildContext context,
    bool isTranslated,
    bool isPending,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true, // 增加顶部的现代拖拽指示条
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: isPending
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Icon(Icons.translate, color: colorScheme.primary),
                title: Text(
                  isPending ? '翻译中...' : (isTranslated ? '重新翻译' : '翻译文章'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                enabled: !isPending,
                onTap: isPending
                    ? null
                    : () {
                        Navigator.pop(context);
                        _translateArticle(context);
                      },
              ),
              if (isTranslated) ...[
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: colorScheme.error,
                  ),
                  title: Text(
                    '删除翻译',
                    style: TextStyle(color: colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    TranslationService.deleteTranslation(article.entryId);
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(String isoTime) {
    if (isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 60) {
        return '${diff.inMinutes}分钟前';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}小时前';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}天前';
      } else {
        return DateFormat('MM-dd').format(dt);
      }
    } catch (_) {
      return isoTime;
    }
  }
}

// ─── 订阅源小图标 ─────────────────────────────

class _FeedIcon extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const _FeedIcon({this.imageUrl, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Icon(Icons.rss_feed,
          size: size, color: cs.onSurfaceVariant.withValues(alpha: 0.6));
    }
    final proxyUrl = ArticleImageService.toProxiedUrl(imageUrl);
    if (proxyUrl == null) {
      return Icon(Icons.rss_feed,
          size: size, color: cs.onSurfaceVariant.withValues(alpha: 0.6));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image(
        image: CachedNetworkImageProvider(proxyUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(Icons.rss_feed,
            size: size, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
    );
  }
}