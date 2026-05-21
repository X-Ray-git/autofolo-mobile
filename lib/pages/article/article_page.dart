import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../services/article_image_service.dart';
import '../../services/local_article_db_service.dart';
import '../../services/read_sync_service.dart';
import '../../services/translation_service.dart';
import '../../services/summary_service.dart';
import '../../services/article_state_notifier.dart';
import '../../utils/article_content_utils.dart';
import '../../utils/html_chunk_parser.dart';
import '../../utils/security_utils.dart';
import '../../utils/storage.dart';
import '../timeline/timeline_controller.dart';
import 'widgets/html_chunk_card.dart';
import 'widgets/image_gallery_page.dart';

/// 文章详情控制器
class ArticleController extends GetxController {
  final ArticleModel article;
  String normalizedContent = '';
  List<String> imageUrls = [];
  final chunks = <HtmlChunk>[].obs;
  final translatedChunks = <HtmlChunk>[].obs;
  final showTranslation = false.obs;
  final isRead = false.obs;
  final isUpdatingReadState = false.obs;
  final isTranslated = false.obs;
  final translationContent = ''.obs;
  final isTranslating = false.obs;
  final summaryText = ''.obs;
  final isSummarized = false.obs;
  final isSummarizing = false.obs;

  ArticleController(this.article);

  @override
  void onInit() {
    super.onInit();
    isRead.value =
        GStorage.readStatus.get(article.entryId, defaultValue: false) as bool;
    _initContent();
    if (article.category == 'inbox' &&
        (article.content == null || article.content!.trim().isEmpty)) {
      _fetchInboxContent();
    }
  }

  void _initContent({String? overrideContent}) {
    normalizedContent = ArticleContentUtils.normalizeHtml(
      overrideContent ?? article.content ?? '',
    );
    imageUrls = ArticleContentUtils.extractImageUrls(normalizedContent);
    chunks.value = HtmlChunkParser.parseSync(normalizedContent);

    // 检查是否有翻译
    if (TranslationService.hasTranslation(article.entryId)) {
      isTranslated.value = true;
      final tContent =
          TranslationService.translatedContentFor(article.entryId) ?? '';
      translationContent.value = tContent;
      if (tContent.isNotEmpty) {
        translatedChunks.value = HtmlChunkParser.parseSync(tContent);
      }
      showTranslation.value = true;
    }

    // 检查是否有摘要
    if (SummaryService.hasSummary(article.entryId)) {
      isSummarized.value = true;
      summaryText.value = SummaryService.summaryFor(article.entryId) ?? '';
    }
  }

  Future<void> _fetchInboxContent() async {
    final result = await FeedHttp.getInboxEntryDetail(
      entryId: article.entryId,
    );
    if (result is Success<String> && result.response.isNotEmpty) {
      _initContent(overrideContent: result.response);
      update(); // 通知 UI 重建
    }
  }

  /// 标为已读（本地 + 云端同步 + 失败重试最多 5 次）
  Future<void> markAsRead() async {
    if (isRead.value) return;
    if (isUpdatingReadState.value) return;

    isUpdatingReadState.value = true;
    // 标已读时清除 AI 过滤标记
    if (article.isRejectedByAi) {
      LocalArticleDbService.upsertOne(ArticleModel(
        entryId: article.entryId,
        feedId: article.feedId,
        feedTitle: article.feedTitle,
        feedImage: article.feedImage,
        title: article.title,
        url: article.url,
        content: article.content,
        publishedAt: article.publishedAt,
        isRead: true,
        category: article.category,
        subscriptionCategory: article.subscriptionCategory,
        author: article.author,
        imageUrl: article.imageUrl,
        isRejectedByAi: false,
        filterReviewed: true,
      ));
    }
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsReadLocal(article.entryId);
    } else {
      GStorage.readStatus.put(article.entryId, true);
      LocalArticleDbService.setReadState(article.entryId, true);
    }
    final isInbox = article.category == 'inbox';
    ReadSyncService.enqueue(article.entryId, isInbox: isInbox);
    isRead.value = true;
    ArticleStateNotifier.tick();

    final ok = await _retrySync(
      action: () => FeedHttp.markRead(
        entryIds: [article.entryId],
        isInbox: isInbox,
      ),
      successMsg: '已标记已读',
      maxRetries: 5,
    );

    if (!ok) {
      // 5 次失败 → 恢复本地未读，与服务器保持一致
      if (Get.isRegistered<TimelineController>()) {
        Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
      } else {
        GStorage.readStatus.put(article.entryId, false);
        LocalArticleDbService.setReadState(article.entryId, false);
      }
      isRead.value = false;
      AppFeedback.error('标记已读失败', '已重试5次，已恢复为未读');
    }
    isUpdatingReadState.value = false;
  }

  Future<void> markAsUnread() async {
    if (!isRead.value || isUpdatingReadState.value) return;

    isUpdatingReadState.value = true;
    if (Get.isRegistered<TimelineController>()) {
      Get.find<TimelineController>().markAsUnreadLocal(article.entryId);
    } else {
      GStorage.readStatus.put(article.entryId, false);
      LocalArticleDbService.setReadState(article.entryId, false);
    }
    isRead.value = false;

    final ok = await _retrySync(
      action: () => FeedHttp.markUnread(entryId: article.entryId),
      successMsg: '已恢复未读',
      maxRetries: 5,
    );

    if (!ok) {
      // 5 次失败 → 恢复本地已读
      if (Get.isRegistered<TimelineController>()) {
        Get.find<TimelineController>().markAsReadLocal(article.entryId);
      } else {
        GStorage.readStatus.put(article.entryId, true);
        LocalArticleDbService.setReadState(article.entryId, true);
      }
      isRead.value = true;
      AppFeedback.error('恢复未读失败', '已重试5次，已恢复为已读');
    }
    isUpdatingReadState.value = false;
  }

  /// 带重试的云端同步。成功返回 true，5 次均失败返回 false。
  Future<bool> _retrySync({
    required Future<LoadingState<void>> Function() action,
    required String successMsg,
    int maxRetries = 5,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      final result = await action();
      if (result is Success<void>) {
        if (attempt == 1) {
          AppFeedback.success(successMsg, '已同步到云端');
        } else {
          AppFeedback.success(successMsg, '重试 $attempt 次后成功');
        }
        return true;
      }
      if (attempt < maxRetries) {
        final delay = Duration(milliseconds: 800 * attempt);
        await Future.delayed(delay);
        AppFeedback.info('同步失败，重试中', '第 $attempt/$maxRetries 次');
      }
    }
    return false;
  }

  Future<void> translateArticle() async {
    if (normalizedContent.isEmpty) {
      AppFeedback.warning('无法翻译', '文章内容为空');
      return;
    }

    isTranslating.value = true;
    try {
      final record = await TranslationService.translateArticle(
        article,
        targetLang: '简体中文',
      );

      if (record.translatedContent != null &&
          record.translatedContent!.isNotEmpty) {
        translationContent.value = record.translatedContent!;
        isTranslated.value = true;
        // 同步解析译文的块
        final tChunks = HtmlChunkParser.parseSync(record.translatedContent!);
        translatedChunks.value = tChunks;
        showTranslation.value = true;
        AppFeedback.success('翻译完成', '已生成文章译文');
      } else {
        AppFeedback.error('翻译失败', '请检查网络连接和 API 配置');
      }
    } catch (e) {
      AppFeedback.error('翻译出错', e.toString());
    } finally {
      isTranslating.value = false;
    }
  }

  Future<void> summarizeArticle() async {
    if (normalizedContent.isEmpty) {
      AppFeedback.warning('无法摘要', '文章内容为空');
      return;
    }

    isSummarizing.value = true;
    try {
      final record = await SummaryService.summarizeArticle(
        article,
        targetLang: '简体中文',
      );

      if (record.summaryText != null && record.summaryText!.isNotEmpty) {
        summaryText.value = record.summaryText!;
        isSummarized.value = true;
        AppFeedback.success('摘要完成', '已生成文章摘要');
      } else {
        AppFeedback.error('摘要失败', '请检查网络连接和 API 配置');
      }
    } catch (e) {
      AppFeedback.error('摘要出错', e.toString());
    } finally {
      isSummarizing.value = false;
    }
  }

  void toggleTranslationDisplay() {
    if (!isTranslated.value) return;
    showTranslation.toggle();
  }

  Future<void> openInBrowser() async {
    if (article.url.isEmpty) return;

    final uri = SecurityUtils.parseHttpUrl(article.url);
    if (uri == null) {
      AppFeedback.error('无法打开链接', '链接格式无效或协议不受支持');
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      AppFeedback.error('无法打开链接', '未找到默认浏览器');
    }
  }

  Future<void> openLink(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = SecurityUtils.parseHttpUrl(url);
    if (uri == null) {
      AppFeedback.error('无法打开链接', '链接格式无效或协议不受支持');
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      AppFeedback.error('无法打开链接', '未找到默认浏览器');
    }
  }

  Future<void> openSource() async {
    if (article.feedId.isEmpty) return;
    Get.toNamed(
      Routes.feedDetail,
      arguments: {'feedId': article.feedId, 'feedTitle': article.feedTitle},
    );
  }

  void openImagePreview(String imageUrl) {
    Get.to(
      () => ImageGalleryPage(
        imageUrls: imageUrls,
        initialIndex: imageUrls.indexOf(imageUrl).clamp(0, imageUrls.length - 1),
      ),
    );
  }
}

// ─── 路由参数解析 ───────────────────────────────

class _ArticleRouteRequest {
  final ArticleModel article;
  final List<ArticleModel>? sequence;
  final int index;

  const _ArticleRouteRequest({
    required this.article,
    this.sequence,
    this.index = 0,
  });

  bool get hasSequence => sequence != null && sequence!.length > 1;

  static _ArticleRouteRequest fromArguments(dynamic arguments) {
    if (arguments is ArticleModel) {
      return _ArticleRouteRequest(article: arguments);
    }

    if (arguments is Map) {
      final article = arguments['article'];
      final sequence = arguments['sequence'];
      final index = arguments['index'];
      if (article is ArticleModel) {
        final items = sequence is List<ArticleModel> ? sequence : null;
        final safeIndex = index is int && index >= 0
            ? index.clamp(0, (items?.length ?? 1) - 1).toInt()
            : 0;
        return _ArticleRouteRequest(
          article: article,
          sequence: items,
          index: safeIndex,
        );
      }
    }

    throw StateError('Invalid article route arguments');
  }
}

// ─── 入口页（处理分页器） ───────────────────────

class ArticlePage extends StatelessWidget {
  const ArticlePage({super.key});

  @override
  Widget build(BuildContext context) {
    final request = _ArticleRouteRequest.fromArguments(Get.arguments);
    if (request.sequence != null && request.sequence!.length > 1) {
      return _ArticlePagerPage(request: request);
    }
    return ArticlePageView(article: request.article);
  }
}

// ─── 分页器（多篇文章左右滑动） ──────────────────

class _ArticlePagerPage extends StatefulWidget {
  final _ArticleRouteRequest request;
  const _ArticlePagerPage({required this.request});

  @override
  State<_ArticlePagerPage> createState() => _ArticlePagerPageState();
}

class _ArticlePagerPageState extends State<_ArticlePagerPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.request.index;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final articles = widget.request.sequence!;
    return PageView.builder(
      controller: _pageController,
      itemCount: articles.length,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      itemBuilder: (context, index) => ArticlePageView(
        key: ValueKey(articles[index].entryId),
        article: articles[index],
        pageLabel: '${index + 1}/${articles.length}',
      ),
    );
  }
}

// ─── 文章视图（核心） ───────────────────────────

class ArticlePageView extends StatefulWidget {
  final ArticleModel article;
  final String? pageLabel;

  const ArticlePageView({super.key, required this.article, this.pageLabel});

  @override
  State<ArticlePageView> createState() => _ArticlePageViewState();
}

class _ArticlePageViewState extends State<ArticlePageView> {
  late final String _tag;
  late final ArticleController controller;

  @override
  void initState() {
    super.initState();
    _tag = widget.article.entryId;
    controller = Get.put(ArticleController(widget.article), tag: _tag);
  }

  @override
  void dispose() {
    if (Get.isRegistered<ArticleController>(tag: _tag)) {
      Get.delete<ArticleController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.of(context).size.width - 32;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pageLabel == null ? '文章详情' : '文章详情 · ${widget.pageLabel}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器中打开',
            onPressed: controller.openInBrowser,
          ),
        ],
      ),
      floatingActionButton: Obx(() {
        final isRead = controller.isRead.value;
        final isUpdating = controller.isUpdatingReadState.value;
        return Opacity(
          opacity: 0.85,
          child: FloatingActionButton(
            onPressed: isUpdating
                ? null
                : (isRead ? controller.markAsUnread : controller.markAsRead),
            tooltip: isRead ? '恢复未读' : '标为已读',
            child: Icon(isRead ? Icons.undo : Icons.check),
          ),
        );
      }),
      body: CustomScrollView(
        slivers: [
          // ─── 元数据区域 ──────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Text(
                    controller.article.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 元数据
                  _MetadataSection(controller: controller, cs: colorScheme),
                  const SizedBox(height: 8),

                  if (controller.article.publishedAt.isNotEmpty)
                    Text(
                      '发布于: ${controller.article.publishedAt}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),

                  const Divider(height: 24),

                  // 翻译按钮
                  _TranslateButton(controller: controller, cs: colorScheme),
                  _ToggleTranslationButton(controller: controller),

                  // 摘要按钮
                  _SummaryButton(controller: controller),
                  _SummaryCard(controller: controller),
                ],
              ),
            ),
          ),

          // ─── 图片预加载（隐藏） ──────────────────
          if (controller.imageUrls.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 0,
                child: Stack(
                  children: [
                    for (final url in controller.imageUrls)
                      Positioned(
                        left: -1,
                        top: -1,
                        child: SizedBox(
                          width: 1,
                          height: 1,
                          child: CachedNetworkImage(
                            imageUrl:
                                ArticleImageService.toProxiedUrl(url) ?? url,
                            httpHeaders: ArticleImageService.httpHeaders,
                            cacheKey: 'v2_$url',
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (_, _) => const SizedBox.shrink(),
                            errorWidget: (_, _, _) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // ─── 正文区域：逐块渲染 ──────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: Obx(() {
              final activeChunks = controller.showTranslation.value &&
                      controller.translatedChunks.isNotEmpty
                  ? controller.translatedChunks
                  : controller.chunks;

              if (activeChunks.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(Icons.article_outlined,
                            size: 48,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(
                          '暂无正文内容',
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                        ),
                        if (controller.article.url.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.open_in_browser, size: 18),
                            label: const Text('在浏览器中查看原文'),
                            onPressed: () => controller.openInBrowser(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              return SliverList.builder(
                itemCount: activeChunks.length,
                itemBuilder: (context, index) {
                  return HtmlChunkCard(
                    chunk: activeChunks[index],
                    maxWidth: maxWidth,
                    onImageTap: controller.openImagePreview,
                  );
                },
              );
            }),
          ),

          // 底部间距
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }
}

// ─── 小型辅助组件 ─────────────────────────────

class _MetadataSection extends StatelessWidget {
  final ArticleController controller;
  final ColorScheme cs;
  const _MetadataSection({required this.controller, required this.cs});

  @override
  Widget build(BuildContext context) {
    final imageUrl = controller.article.feedImage;
    return Row(
      children: [
        Text('来自: ',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        if (imageUrl != null && imageUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image(
              image: CachedNetworkImageProvider(
                ArticleImageService.toProxiedUrl(imageUrl) ?? imageUrl,
              ),
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: InkWell(
            onTap:
                controller.article.feedId.isEmpty ? null : controller.openSource,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                controller.article.feedTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TranslateButton extends StatelessWidget {
  final ArticleController controller;
  final ColorScheme cs;
  const _TranslateButton({required this.controller, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final record = TranslationService.recordOf(controller.article.entryId);
      final isPending =
          (record?.isPending ?? false) || controller.isTranslating.value;
      final hasTranslation =
          (record?.translatedContent?.trim().isNotEmpty ?? false) ||
              controller.translationContent.value.trim().isNotEmpty;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton.tonalIcon(
            onPressed: isPending ? null : controller.translateArticle,
            icon: isPending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.language),
            label: Text(
              isPending
                  ? '翻译中...'
                  : (hasTranslation ? '重新翻译' : '翻译文章'),
            ),
          ),
        ),
      );
    });
  }
}

class _ToggleTranslationButton extends StatelessWidget {
  final ArticleController controller;
  const _ToggleTranslationButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final record = TranslationService.recordOf(controller.article.entryId);
      final hasTranslation =
          (record?.translatedContent?.trim().isNotEmpty ?? false) ||
              controller.translationContent.value.trim().isNotEmpty;
      if (!hasTranslation) return const SizedBox.shrink();
      final showTranslation = controller.showTranslation.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: controller.toggleTranslationDisplay,
            icon: Icon(
              showTranslation ? Icons.visibility_off : Icons.visibility,
              size: 18,
            ),
            label: Text(showTranslation ? '查看原文' : '查看译文'),
          ),
        ),
      );
    });
  }
}

class _SummaryButton extends StatelessWidget {
  final ArticleController controller;
  const _SummaryButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final record = SummaryService.recordOf(controller.article.entryId);
      final isPending =
          (record?.isPending ?? false) || controller.isSummarizing.value;
      final hasSummary =
          (record?.summaryText?.trim().isNotEmpty ?? false) ||
              controller.summaryText.value.trim().isNotEmpty;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton.tonalIcon(
            onPressed: isPending ? null : controller.summarizeArticle,
            icon: isPending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFD97706)),
                    ),
                  )
                : const Icon(Icons.summarize),
            label: Text(
              isPending
                  ? '摘要中...'
                  : (hasSummary ? '重新生成摘要' : '生成摘要'),
            ),
          ),
        ),
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  final ArticleController controller;
  const _SummaryCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final record = SummaryService.recordOf(controller.article.entryId);
      final summary =
          (record?.summaryText ?? controller.summaryText.value).trim();
      if (summary.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFD97706).withValues(alpha: 0.1),
            border: Border.all(
              color: const Color(0xFFD97706).withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.summarize, size: 16, color: Color(0xFFD97706)),
                SizedBox(width: 8),
                Text('文章摘要',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD97706))),
              ]),
              const SizedBox(height: 8),
              Text(summary, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
          ),
        ),
      );
    });
  }
}
