import 'package:get/get.dart';

import '../../http/feed_http.dart';
import '../../http/init.dart';
import '../../models/article.dart';
import '../../models/feed.dart';
import '../../services/account_service.dart';
import '../../services/article_state_notifier.dart';
import '../../services/content_cache_service.dart';
import '../../services/local_article_db_service.dart';
import '../../utils/source_taxonomy.dart';
import '../../utils/storage.dart';

class SourceCategoryNode {
  final String name;
  final List<FeedModel> feeds;

  SourceCategoryNode({required this.name, required this.feeds});
}

class SourceViewNode {
  final int view;
  final String name;
  final List<SourceCategoryNode> categories;

  SourceViewNode({
    required this.view,
    required this.name,
    required this.categories,
  });

  int get sourceCount => categories.fold(0, (sum, cat) => sum + cat.feeds.length);
  int get categoryCount => categories.length;
}

/// 订阅源控制器
class SubscriptionsController extends GetxController {
  final loadingState = Rx<LoadingState<List<SourceViewNode>>>(const Loading());
  final allFeeds = <FeedModel>[].obs;
  final searchQuery = ''.obs;
  final viewNodes = <SourceViewNode>[].obs;
  final expandedState = <String, bool>{}.obs;

  @override
  void onInit() {
    super.onInit();
    refreshUnreadCounts();
    loadData();
    ever(ArticleStateNotifier.version, (_) => refreshUnreadCounts());
  }

  Future<void> loadData() async {
    refreshUnreadCounts();
    if (!AccountService.instance.isLoggedIn.value) {
      loadingState.value = const LoadError('请先在“设置”页配置 Folo Token');
      viewNodes.clear();
      return;
    }

    final cached = ContentCacheService.readSubscriptions();
    if (cached.isNotEmpty) {
      allFeeds.value = cached;
      final cachedNodes = _buildViewNodes(cached);
      viewNodes.value = cachedNodes;
      _syncExpandedState(cachedNodes);
      loadingState.value = Success(cachedNodes);
    } else {
      loadingState.value = const Loading();
    }

    final feedsResult = await FeedHttp.getSubscriptions();
    final inboxesResult = await FeedHttp.getInboxes();

    final sources = <FeedModel>[];
    if (feedsResult is Success<List<FeedModel>>) {
      sources.addAll(feedsResult.response);
    }
    if (inboxesResult is Success<List<Map<String, dynamic>>>) {
      sources.addAll(
        inboxesResult.response.map(FeedModel.fromInboxJson),
      );
    }

    if (sources.isNotEmpty) {
      final combined = _mergeSources(cached, sources);
      allFeeds.value = combined;
      final nodes = _buildViewNodes(combined);
      viewNodes.value = nodes;
      _syncExpandedState(nodes);
      loadingState.value = Success(nodes);
      ContentCacheService.saveSubscriptions(combined);
    } else if (cached.isEmpty) {
      final feedErr = feedsResult is LoadError<List<FeedModel>>
          ? feedsResult.errMsg
          : null;
      final inboxErr = inboxesResult is LoadError<List<Map<String, dynamic>>>
          ? inboxesResult.errMsg
          : null;
      loadingState.value = LoadError<List<SourceViewNode>>(
        feedErr ?? inboxErr ?? '加载失败',
      );
    }
  }

  void updateSearchQuery(String value) {
    searchQuery.value = value.trim().toLowerCase();
  }

  /// 每源未读计数
  final _unreadCounts = <String, int>{}.obs;

  void refreshUnreadCounts() {
    final eid = ArticleStateNotifier.lastEntryId;
    if (eid != null) {
      // 消费后立刻清除，防止后续调用永远走增量路径
      ArticleStateNotifier.clearLastEntryId();
      // 增量：只更新单篇对应的 feedId 计数
      final raw = GStorage.articleDb.get(eid);
      if (raw is Map) {
        final a = ArticleModel.fromCache(Map<String, dynamic>.from(raw));
        if (!a.isRead && !a.isRejectedByAi && a.feedId.isNotEmpty) {
          _unreadCounts[a.feedId] = (_unreadCounts[a.feedId] ?? 0) + 1;
        } else if ((a.isRead || a.isRejectedByAi) && a.feedId.isNotEmpty) {
          final prev = _unreadCounts[a.feedId] ?? 0;
          if (prev > 0) _unreadCounts[a.feedId] = prev - 1;
        }
        _unreadCounts.refresh();
      }
      return;
    }
    // 全量（首屏）
    final all = LocalArticleDbService.readAllArticles();
    final counts = <String, int>{};
    for (final a in all) {
      if (a.isRead || a.isRejectedByAi || a.feedId.isEmpty) continue;
      counts[a.feedId] = (counts[a.feedId] ?? 0) + 1;
    }
    _unreadCounts.value = counts;
  }

  int unreadFor(String feedId) => _unreadCounts[feedId] ?? 0;

  int unreadForCategory(String categoryName, List<FeedModel> feeds) {
    int total = 0;
    for (final f in feeds) {
      total += unreadFor(f.feedId);
    }
    return total;
  }

  int unreadForView(List<SourceCategoryNode> categories) {
    int total = 0;
    for (final cat in categories) {
      total += unreadForCategory(cat.name, cat.feeds);
    }
    return total;
  }

  List<SourceViewNode> get filteredNodes {
    final query = searchQuery.value;
    if (query.isEmpty) return viewNodes;

    final result = <SourceViewNode>[];
    for (final view in viewNodes) {
      final viewMatched =
          view.name.toLowerCase().contains(query) ||
          SourceTaxonomy.viewKeyFromInt(view.view).contains(query);
      if (viewMatched) {
        result.add(view);
        continue;
      }

      final categories = <SourceCategoryNode>[];
      for (final category in view.categories) {
        final catMatched = category.name.toLowerCase().contains(query);
        final feeds = category.feeds.where((feed) {
          final title = feed.title.toLowerCase();
          final url = (feed.url ?? '').toLowerCase();
          final feedCategory = (feed.category ?? '').toLowerCase();
          final feedView = feed.viewLabel.toLowerCase();
          return title.contains(query) ||
              url.contains(query) ||
              feedCategory.contains(query) ||
              feedView.contains(query);
        }).toList();

        if (catMatched) {
          categories.add(category);
        } else if (feeds.isNotEmpty) {
          categories.add(SourceCategoryNode(name: category.name, feeds: feeds));
        }
      }

      if (categories.isNotEmpty) {
        result.add(
          SourceViewNode(view: view.view, name: view.name, categories: categories),
        );
      }
    }

    return result;
  }

  List<SourceViewNode> _buildViewNodes(List<FeedModel> feeds) {
    final viewMap = <int, Map<String, List<FeedModel>>>{};
    for (final feed in feeds) {
      final view = feed.view ?? 0;
      final category = feed.displayCategory;
      viewMap.putIfAbsent(view, () => <String, List<FeedModel>>{});
      viewMap[view]!.putIfAbsent(category, () => []).add(feed);
    }

    final nodes =
        viewMap.entries
            .map(
              (viewEntry) => SourceViewNode(
                view: viewEntry.key,
                name: SourceTaxonomy.viewLabelFromInt(viewEntry.key),
                categories: viewEntry.value.entries
                    .map(
                      (catEntry) => SourceCategoryNode(
                        name: catEntry.key,
                        feeds: catEntry.value..sort(_compareFeeds),
                      ),
                    )
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name)),
              ),
            )
            .toList()
          ..sort((a, b) => SourceTaxonomy.viewOrderFromInt(a.view)
              .compareTo(SourceTaxonomy.viewOrderFromInt(b.view)));
    return nodes;
  }

  List<FeedModel> _mergeSources(List<FeedModel> cached, List<FeedModel> fresh) {
    final byId = <String, FeedModel>{};
    for (final item in cached) {
      if (item.feedId.isNotEmpty) {
        byId[item.feedId] = item;
      }
    }
    for (final item in fresh) {
      if (item.feedId.isNotEmpty) {
        byId[item.feedId] = item;
      }
    }
    return byId.values.toList()..sort(_compareFeeds);
  }

  int _compareFeeds(FeedModel a, FeedModel b) {
    final viewCmp = a.viewOrder.compareTo(b.viewOrder);
    if (viewCmp != 0) return viewCmp;
    final catCmp = a.displayCategory.compareTo(b.displayCategory);
    if (catCmp != 0) return catCmp;
    return a.title.compareTo(b.title);
  }

  bool isExpanded(String key, {bool defaultExpanded = false}) {
    return expandedState[key] ?? defaultExpanded;
  }

  void setExpanded(String key, bool expanded) {
    expandedState[key] = expanded;
  }

  void _syncExpandedState(List<SourceViewNode> nodes) {
    final allowed = <String>{};
    for (final view in nodes) {
      allowed.add('view:${view.name}');
      for (final category in view.categories) {
        allowed.add('cat:${view.name}:${category.name}');
      }
    }
    expandedState.removeWhere((key, value) => !allowed.contains(key));
  }
}
