import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../common/constants/constants.dart';
import '../utils/storage.dart';

/// HTTP 请求单例
class Request {
  static final Request _instance = Request._internal();
  static late final Dio dio;

  factory Request() => _instance;

  Request._internal() {
    final options = BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(milliseconds: AppConstants.defaultTimeout),
      receiveTimeout: const Duration(milliseconds: AppConstants.defaultTimeout),
      sendTimeout: const Duration(milliseconds: AppConstants.defaultTimeout),
      headers: {
        'Origin': 'https://app.folo.is',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-App-Platform': 'mobile/android',
        'X-App-Name': 'autofolo',
        'X-App-Version': '1.0.0',
      },
    );

    dio = Dio(options);

    if (!kIsWeb) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
            ..idleTimeout = const Duration(seconds: 15);
          if (kDebugMode) {
            client.badCertificateCallback = (cert, host, port) => true;
          }
          return client;
        },
      );
    }

    dio.interceptors.add(_AuthInterceptor());

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: true,
          requestBody: true,
          responseHeader: false,
          responseBody: true,
          error: true,
        ),
      );
    }
  }

  Future<Response> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return dio.get(
      url,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response> post(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return dio.post(
      url,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response> delete(
    String url, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return dio.delete(
      url,
      data: data,
      options: options,
      cancelToken: cancelToken,
    );
  }
}

/// 认证拦截器 — 注入 Folo session token
class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token =
        GStorage.setting.get(StorageKeys.sessionToken, defaultValue: '')
            as String;
    final clientId =
        GStorage.setting.get(StorageKeys.clientId, defaultValue: '') as String;
    final sessionId =
        GStorage.setting.get(StorageKeys.sessionId, defaultValue: '') as String;

    if (token.isNotEmpty) {
      options.headers['Cookie'] =
          '__Secure-better-auth.session_token=$token; '
          'better-auth.last_used_login_method=google';
    }
    if (clientId.isNotEmpty) {
      options.headers['X-Client-Id'] = clientId;
    }
    if (sessionId.isNotEmpty) {
      options.headers['X-Session-Id'] = sessionId;
    }

    handler.next(options);
  }
}

/// 加载状态密封类
sealed class LoadingState<T> {
  const LoadingState();

  bool get isSuccess => this is Success<T>;
  bool get isLoading => this is Loading<T>;

  T get data => switch (this) {
    Success(:final response) => response,
    _ => throw StateError('Not in success state'),
  };

  T? get dataOrNull => switch (this) {
    Success(:final response) => response,
    _ => null,
  };
}

class Loading<T> extends LoadingState<T> {
  const Loading();
}

class Success<T> extends LoadingState<T> {
  final T response;
  const Success(this.response);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Success<T> && response == other.response;
  }

  @override
  int get hashCode => response.hashCode;
}

class LoadError<T> extends LoadingState<T> {
  final int? code;
  final String? errMsg;
  const LoadError(this.errMsg, {this.code});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LoadError && errMsg == other.errMsg && code == other.code;
  }

  @override
  int get hashCode => Object.hash(errMsg, code);

  @override
  String toString() => errMsg ?? code?.toString() ?? '未知错误';
}
