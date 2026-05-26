import 'package:dio/dio.dart';

import '../common/constants/constants.dart';
import '../models/article.dart';
import '../models/feed.dart';
import 'init.dart';

/// Folo API 封装
class FeedHttp {
  FeedHttp._();

  // ─── 订阅源 ──────────────────────────────────

  /// 获取全部订阅源
  static Future<LoadingState<List<FeedModel>>> getSubscriptions() async {
    try {
      final response = await Request().get(ApiConstants.subscriptions);
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          final data = body['data'] as List<dynamic>? ?? [];
          final feeds = data
              .whereType<Map>()
              .map((e) => FeedModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          return Success(feeds);
        }
        return LoadError(_messageOf(body, fallback: '请求失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  // ─── 文章条目 ────────────────────────────────

  /// 获取条目（view: 0=feeds, 1=social）。read=false=未读。
  static Future<LoadingState<List<ArticleModel>>> getEntries({
    int view = 0,
    int limit = AppConstants.defaultPageSize,
    bool read = false,
    bool withContent = false,
    String? publishedAfter,
    Map<String, FeedModel>? feedMap,
  }) async {
    try {
      final body = <String, dynamic>{
        'read': read,
        'limit': limit,
        'view': view,
        'withContent': withContent,
      };
      if (publishedAfter != null) {
        body['publishedAfter'] = publishedAfter;
      }

      final response = await Request().post(ApiConstants.entries, data: body);

      final bodyMap = _responseMap(response);
      if (response.statusCode == 200 && bodyMap != null) {
        if (_isSuccess(bodyMap)) {
          final data = bodyMap['data'] as List<dynamic>? ?? [];
          final articles = data.whereType<Map>().map((item) {
            final json = Map<String, dynamic>.from(item);
            final feedId =
                (json['feeds'] as Map<String, dynamic>?)?['id'] as String? ??
                '';
            final f = feedMap?[feedId];
            return ArticleModel.fromEntryJson(
              json,
              feedTitle: f?.title,
              feedImage: f?.image,
              subscriptionCategory: f?.category,
              view: view,
              feedView: f?.view,
            );
          }).toList();
          return Success(articles);
        }
        return LoadError(_messageOf(bodyMap, fallback: '请求失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  /// 分页收集条目，适合需要尽量完整回填状态的场景。
  static Future<LoadingState<List<ArticleModel>>> collectEntries({
    int view = 0,
    int limit = AppConstants.defaultPageSize,
    bool read = false,
    bool withContent = false,
    String? publishedAfter,
    Map<String, FeedModel>? feedMap,
  }) async {
    final items = <ArticleModel>[];
    var cursor = publishedAfter;

    while (true) {
      final result = await getEntries(
        view: view,
        limit: limit,
        read: read,
        withContent: withContent,
        publishedAfter: cursor,
        feedMap: feedMap,
      );
      if (result is LoadError<List<ArticleModel>>) {
        return LoadError(result.errMsg ?? '请求失败');
      }
      if (result is! Success<List<ArticleModel>>) {
        return const LoadError('请求失败');
      }

      final batch = result.response;
      if (batch.isEmpty) break;
      items.addAll(batch);

      if (batch.length < limit) break;
      cursor = batch.last.publishedAt;
    }

    final deduped = <String, ArticleModel>{};
    for (final item in items) {
      if (item.entryId.isEmpty) continue;
      deduped[item.entryId] = item;
    }
    return Success(deduped.values.toList());
  }

  /// 收集所有 inbox 的未读条目。
  static Future<LoadingState<List<ArticleModel>>> collectAllInboxEntries({
    int limit = AppConstants.defaultPageSize,
    bool withContent = false,
  }) async {
    final inboxesResult = await getInboxes();
    if (inboxesResult is LoadError<List<Map<String, dynamic>>>) {
      return LoadError(inboxesResult.errMsg ?? '获取收件箱列表失败');
    }
    if (inboxesResult is! Success<List<Map<String, dynamic>>>) {
      return const LoadError('获取收件箱列表失败');
    }

    final inboxes = inboxesResult.response;
    final items = <ArticleModel>[];

    for (final inbox in inboxes) {
      final source = FeedModel.fromInboxJson(inbox);
      final inboxId = source.feedId;
      if (inboxId.isEmpty) continue;

      final result = await getInboxEntries(
        inboxId: inboxId,
        limit: limit,
        withContent: withContent,
        inboxTitle: source.title,
        inboxImage: source.image,
        inboxCategory: source.category,
      );

      if (result is Success<List<ArticleModel>>) {
        items.addAll(result.response);
      }
    }

    final deduped = <String, ArticleModel>{};
    for (final item in items) {
      if (item.entryId.isEmpty) continue;
      deduped[item.entryId] = item;
    }
    return Success(deduped.values.toList());
  }

  // ─── 收件箱 ──────────────────────────────────

  /// 获取收件箱列表
  static Future<LoadingState<List<Map<String, dynamic>>>> getInboxes() async {
    try {
      final response = await Request().get(ApiConstants.inboxesList);
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          final data = body['data'] as List<dynamic>? ?? [];
          final inboxes = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          return Success(inboxes);
        }
        return LoadError(_messageOf(body, fallback: '请求失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  /// 获取指定收件箱的未读条目
  static Future<LoadingState<List<ArticleModel>>> getInboxEntries({
    required String inboxId,
    int limit = AppConstants.defaultPageSize,
    bool withContent = false,
    String? inboxTitle,
    String? inboxImage,
    String? inboxCategory,
  }) async {
    try {
      final body = <String, dynamic>{
        'inboxId': inboxId,
        'read': false,
        'limit': limit,
        'withContent': withContent,
      };

      final response = await Request().post(
        ApiConstants.entriesInbox,
        data: body,
      );

      final bodyMap = _responseMap(response);
      if (response.statusCode == 200 && bodyMap != null) {
        if (_isSuccess(bodyMap)) {
          final data = bodyMap['data'] as List<dynamic>? ?? [];
          final articles = data
              .whereType<Map>()
              .map(
                (item) =>
                    ArticleModel.fromInboxJson(
                      Map<String, dynamic>.from(item),
                      feedTitle: inboxTitle,
                      feedImage: inboxImage,
                      subscriptionCategory: inboxCategory,
                    ),
              )
              .toList();
          return Success(articles);
        }
        return LoadError(_messageOf(bodyMap, fallback: '请求失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  /// 获取指定 inbox 条目的详情（含正文）
  static Future<LoadingState<String>> getInboxEntryDetail({
    required String entryId,
  }) async {
    try {
      final response = await Request().get(
        ApiConstants.entriesInboxDetail,
        queryParameters: {'id': entryId},
      );
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          final data = body['data'] as Map<String, dynamic>?;
          final entries = data?['entries'] as Map<String, dynamic>?;
          final content = entries?['content'] as String? ?? '';
          return Success(content);
        }
        return LoadError(_messageOf(body, fallback: '获取详情失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  // ─── 已读管理 ────────────────────────────────

  /// 标已读（一次最多 50 条）
  static Future<LoadingState<void>> markRead({
    required List<String> entryIds,
    bool isInbox = false,
  }) async {
    try {
      final response = await Request().post(
        ApiConstants.reads,
        data: {'entryIds': entryIds, 'isInbox': isInbox},
      );
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          return const Success(null);
        }
        return LoadError(_messageOf(body, fallback: '标已读失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  /// 批量标已读（50 条一批）
  static Future<LoadingState<Map<String, int>>> batchMarkRead({
    required List<String> entryIds,
  }) async {
    int success = 0;
    int failed = 0;
    for (int i = 0; i < entryIds.length; i += 50) {
      final batch = entryIds.sublist(i, (i + 50).clamp(0, entryIds.length));
      final result = await markRead(entryIds: batch);
      if (result is Success) {
        success += batch.length;
      } else {
        failed += batch.length;
      }
    }
    return Success({'success': success, 'failed': failed});
  }

  /// 标未读
  static Future<LoadingState<void>> markUnread({
    required String entryId,
  }) async {
    try {
      final response = await Request().delete(
        ApiConstants.reads,
        data: {'entryId': entryId},
      );
      final body = _responseMap(response);
      if (response.statusCode == 200 && body != null) {
        if (_isSuccess(body)) {
          return const Success(null);
        }
        return LoadError(_messageOf(body, fallback: '标未读失败'));
      }
      return LoadError('请求失败: ${response.statusCode}');
    } on DioException catch (e) {
      return LoadError('网络错误: ${e.message}');
    }
  }

  static Map<String, dynamic>? _responseMap(Response response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  static bool _isSuccess(Map<String, dynamic> body) =>
      body['code'] == 0 || body['code'] == '0';

  static String _messageOf(
    Map<String, dynamic> body, {
    required String fallback,
  }) {
    final message = body['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }
    return fallback;
  }
}
