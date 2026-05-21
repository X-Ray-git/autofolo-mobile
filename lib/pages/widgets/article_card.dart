import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';

import '../../common/widgets/feedback_toast.dart';
import '../../common/widgets/pill_tag.dart';
import '../../models/article.dart';
import '../../services/article_image_service.dart';
import '../../services/translation_service.dart';
import '../../utils/source_taxonomy.dart';

/// 文章卡片组件
class ArticleCard extends StatefulWidget {
  final ArticleModel article;
  final VoidCallback? onTap;
  final VoidCallback? onTranslate;
  final bool showFeedTitle;

  const ArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.onTranslate,
    this.showFeedTitle = true,
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
  final bool isTranslated;
  final VoidCallback? onTranslateSuccess;

  const _ArticleCardContent({
    required this.article,
    this.onTap,
    this.onTranslate,
    required this.showFeedTitle,
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
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: article.isRejectedByAi
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFF59E0B), width: 2),
                )
              : null,
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          child: InkWell(
            onTap: onTap,
            onLongPress: () =>
                _showTranslateMenu(context, isTranslated, isPending),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!article.isRead) ...[
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6, right: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          displayTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: article.isRead
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: article.isRead
                                ? colorScheme.onSurface.withValues(alpha: 0.7)
                                : colorScheme.onSurface,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPending) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colorScheme.primary.withValues(
                                alpha: 0.25,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '翻译中',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (isTranslated) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: '已翻译',
                          child: Icon(
                            Icons.language,
                            size: 18,
                            color: colorScheme.primary,
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
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            PillTag(
                              label: viewLabel,
                              backgroundColor: viewColor.withValues(
                                alpha: 0.14,
                              ),
                              foregroundColor: viewColor,
                            ),
                            if (categoryLabel.isNotEmpty)
                              PillTag(
                                label: categoryLabel,
                                backgroundColor:
                                    colorScheme.surfaceContainerHighest,
                                foregroundColor: colorScheme.onSurfaceVariant,
                              ),
                            if (showFeedTitle)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _FeedIcon(
                                    imageUrl: article.feedImage,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 180,
                                    ),
                                    child: Text(
                                      article.feedTitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.6),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
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
                ],
              ),
            ),
          ),
        ),
      );
    });
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
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: isPending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.language),
                title: Text(
                  isPending ? '翻译中...' : (isTranslated ? '重新翻译' : '翻译文章'),
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
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('删除翻译'),
                  onTap: () {
                    Navigator.pop(context);
                    TranslationService.deleteTranslation(article.entryId);
                  },
                ),
              ],
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
      return Icon(Icons.rss_feed, size: size,
          color: cs.onSurfaceVariant.withValues(alpha: 0.6));
    }
    final proxyUrl = ArticleImageService.toProxiedUrl(imageUrl);
    if (proxyUrl == null) {
      return Icon(Icons.rss_feed, size: size,
          color: cs.onSurfaceVariant.withValues(alpha: 0.6));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image(
        image: CachedNetworkImageProvider(proxyUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.rss_feed, size: size,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
    );
  }
}
