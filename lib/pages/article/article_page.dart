import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;

import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../router/app_pages.dart';
import '../../common/constants/constants.dart';
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
import 'package:flutter_html/flutter_html.dart';
import 'widgets/image_gallery_page.dart';
import '../../common/widgets/hero_dialog_route.dart';

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
  final isFetchingReadability = false.obs;
  final isFetchingContent = false.obs;

  ArticleController(this.article);

  @override
  void onInit() {
    super.onInit();
    isRead.value =
        GStorage.readStatus.get(article.entryId, defaultValue: false) as bool;
    if (article.category == 'inbox' &&
        (article.content == null || article.content!.trim().isEmpty)) {
      isFetchingContent.value = true;
      _fetchInboxContent();
    } else if (article.content != null && article.content!.isNotEmpty) {
      _initContent();
    } else {
      _initContent();
      isFetchingContent.value = true;
      if (article.url.isNotEmpty) {
        fetchReadabilityContent();
      }
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
      // 持久化到本地，下次打开无需重复拉取
      LocalArticleDbService.upsertOne(ArticleModel(
        entryId: article.entryId,
        feedId: article.feedId,
        feedTitle: article.feedTitle,
        feedImage: article.feedImage,
        title: article.title,
        url: article.url,
        content: result.response,
        publishedAt: article.publishedAt,
        category: article.category,
        subscriptionCategory: article.subscriptionCategory,
        author: article.author,
        imageUrl: article.imageUrl,
        isRejectedByAi: article.isRejectedByAi,
        filterReason: article.filterReason,
        filterReviewed: article.filterReviewed,
      ));
      update(); // 通知 UI 重建
    }
    isFetchingContent.value = false;
  }

  Future<void> fetchReadabilityContent() async {
    if (article.url.isEmpty) return;
    
    // We shouldn't block initialization, run async
    Future.microtask(() async {
      isFetchingReadability.value = true;
      try {
        final response = await Request.dio.get(article.url);
        final htmlStr = response.data.toString();
        final document = html_parser.parse(htmlStr);
        final articleNode = ArticleContentUtils.getReadabilityContent(document);
        if (articleNode != null) {
          _initContent(overrideContent: articleNode.outerHtml);
          // 持久化抓取结果，下次打开无需重复抓
          LocalArticleDbService.upsertOne(ArticleModel(
            entryId: article.entryId,
            feedId: article.feedId,
            feedTitle: article.feedTitle,
            feedImage: article.feedImage,
            title: article.title,
            url: article.url,
            content: articleNode.outerHtml,
            publishedAt: article.publishedAt,
            category: article.category,
            subscriptionCategory: article.subscriptionCategory,
            author: article.author,
            imageUrl: article.imageUrl,
            isRejectedByAi: article.isRejectedByAi,
            filterReason: article.filterReason,
            filterReviewed: article.filterReviewed,
          ));
        }
      } catch (e) {
        // silently fail on auto-fetch
      } finally {
        isFetchingReadability.value = false;
        isFetchingContent.value = false;
      }
    });
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
    ArticleStateNotifier.tick(article.entryId);

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
        overrideContent: normalizedContent,
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
        AppFeedback.error('翻译失败', record.errorMessage ?? '请检查网络连接和 API 配置');
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
        overrideContent: normalizedContent,
      );

      if (record.summaryText != null && record.summaryText!.isNotEmpty) {
        summaryText.value = record.summaryText!;
        isSummarized.value = true;
        AppFeedback.success('摘要完成', '已生成文章摘要');
      } else {
        AppFeedback.error('摘要失败', record.errorMessage ?? '请检查网络连接和 API 配置');
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

  void openImagePreview(String imageUrl, BuildContext context) {
    Navigator.of(context).push(
      HeroDialogRoute(
        builder: (context) => ImageGalleryPage(
          imageUrls: imageUrls,
          initialIndex: imageUrls.indexOf(imageUrl).clamp(0, imageUrls.length - 1),
        ),
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
        pageLabel: '${index + 1} / ${articles.length}',
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
  late final ScrollController _scrollController;
  
  // 1. 改为使用 ValueNotifier 以实现局部刷新
  final ValueNotifier<double> _scrollProgress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _tag = widget.article.entryId;
    controller = Get.put(ArticleController(widget.article), tag: _tag);
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollProgress.dispose(); // 记得释放 Notifier
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
          widget.pageLabel ?? '文章详情',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 2.0,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.surface.withValues(alpha: 0.5),
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: const [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: ValueListenableBuilder<double>(
            valueListenable: _scrollProgress,
            builder: (context, progress, child) {
              return progress > 0.0
                  ? TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: progress),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 1.0,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                        );
                      },
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      ),
      floatingActionButton: Obx(() {
        final isRead = controller.isRead.value;
        final isUpdating = controller.isUpdatingReadState.value;
        return Opacity(
          opacity: 0.85,
          child: FloatingActionButton(
            onPressed: isUpdating ? null
                : (isRead ? controller.markAsUnread : controller.markAsRead),
            tooltip: isRead ? '恢复未读' : '标为已读',
            child: Icon(isRead ? Icons.undo : Icons.check),
          ),
        );
      }),
      body: SelectionArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical) {
              final maxScroll = notification.metrics.maxScrollExtent;
              final currentScroll = notification.metrics.pixels;
              if (maxScroll > 0) {
                _scrollProgress.value = (currentScroll / maxScroll).clamp(0.0, 1.0);
              } else if (notification.metrics.hasContentDimensions) {
                _scrollProgress.value = 1.0;
              }
            }
            return false;
          },
          child: CustomScrollView(
            controller: _scrollController,
          slivers: [
          // ─── 元数据区域 ──────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: controller.openInBrowser,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.article.title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
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

                  _ToolbarRow(controller: controller, cs: colorScheme),
                  _SummaryCard(controller: controller),
                ],
              ),
            ),
          ),

          // （已删除：高度为 0 的隐藏预加载栈代码）

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
                    child: controller.isFetchingContent.value
                        ? Column(children: [
                            const SizedBox(height: 32),
                            SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: colorScheme.primary.withValues(alpha: 0.6)),
                            ),
                            const SizedBox(height: 16),
                            Text('正在加载正文…',
                                style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 14)),
                          ])
                        : Column(children: [
                            Icon(Icons.article_outlined,
                                size: 48,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text('暂无正文内容',
                                style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500)),
                            if (controller.article.url.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                icon: const Icon(Icons.open_in_browser, size: 18),
                                label: const Text('在浏览器中查看原文'),
                                onPressed: () => controller.openInBrowser(),
                              ),
                            ],
                          ]),
                  ),
                );
              }

              final useLazyLoading = GStorage.setting.get(
                StorageKeys.articleLazyLoading,
                defaultValue: false,
              ) as bool;

              if (useLazyLoading) {
                return SliverList.builder(
                  itemCount: activeChunks.length,
                  itemBuilder: (context, index) {
                    return HtmlChunkCard(
                      chunk: activeChunks[index],
                      maxWidth: maxWidth,
                      onImageTap: (url) => controller.openImagePreview(url, context),
                    );
                  },
                );
              }

              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: activeChunks.map((chunk) {
                    return HtmlChunkCard(
                      chunk: chunk,
                      maxWidth: maxWidth,
                      onImageTap: (url) => controller.openImagePreview(url, context),
                    );
                  }).toList(),
                ),
              );
            }),
          ),

          // 底部间距
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ))),
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
    return InkWell(
      onTap: controller.article.feedId.isEmpty ? null : controller.openSource,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image(
                  image: CachedNetworkImageProvider(
                    ArticleImageService.toProxiedUrl(imageUrl) ?? imageUrl,
                  ),
                  width: 16, height: 16, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.rss_feed, size: 14, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          Flexible(child: Text(controller.article.feedTitle,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 14,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
        ]),
      ),
    );
  }
}

class _ToolbarRow extends StatelessWidget {
  final ArticleController controller;
  final ColorScheme cs;
  const _ToolbarRow({required this.controller, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final rec = TranslationService.recordOf(controller.article.entryId);
      final isPending = (rec?.isPending ?? false) || controller.isTranslating.value;
      final hasTranslation = controller.isTranslated.value;
      final isSummarizing = controller.isSummarizing.value;
      final hasSummary = controller.isSummarized.value;
      final isFetchingReadability = controller.isFetchingReadability.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _Chip(cs: cs, icon: controller.showTranslation.value ? Icons.translate : Icons.translate_outlined,
              label: isPending ? '翻译…' : hasTranslation ? '已译' : '翻译',
              active: controller.showTranslation.value || isPending,
              onTap: isPending ? null : hasTranslation ? () => controller.showTranslation.toggle() : () => controller.translateArticle()),
            const SizedBox(width: 8),
            _Chip(cs: cs, icon: hasSummary ? Icons.summarize : Icons.summarize_outlined,
              label: isSummarizing ? '摘要…' : hasSummary ? '已摘要' : '摘要',
              active: hasSummary || isSummarizing,
              onTap: isSummarizing ? null : () => controller.summarizeArticle()),
            if (isFetchingReadability) ...[
              const SizedBox(width: 8),
              _Chip(cs: cs, icon: Icons.sync,
                label: '加载长文中…',
                active: true,
                onTap: null),
            ]
          ]),
        ),
      );
    });
  }
}

class _Chip extends StatelessWidget {
  final ColorScheme cs; final IconData icon; final String label;
  final bool active; final VoidCallback? onTap;
  const _Chip({required this.cs, required this.icon, required this.label,
    required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? cs.primary.withValues(alpha: 0.12) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: active ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
              color: active ? cs.primary : cs.onSurfaceVariant)),
        ]),
      ),
    );
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
            color: Theme.of(context).brightness == Brightness.light
                ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.10)
                : Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.summarize, size: 16,
                    color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 8),
                Text('文章摘要', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary)),
              ]),
              const SizedBox(height: 8),
              Html(
                data: summary,
                style: {
                  'body': Style(
                    fontSize: FontSize(14),
                    lineHeight: const LineHeight(1.5),
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                  ),
                  'a': Style(
                    color: Theme.of(context).colorScheme.primary,
                    textDecoration: TextDecoration.none,
                  ),
                },
                onLinkTap: (url, _, __) async {
                  if (url != null && url.isNotEmpty) {
                    final uri = Uri.tryParse(url);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    });
  }
}