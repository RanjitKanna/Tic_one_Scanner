import 'dart:async';

import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../storage/session_store.dart';

/// A request failure with a message fit to show gate staff.
class ApiFailure implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? body;

  const ApiFailure(this.message, {this.statusCode, this.body});

  bool get isNetworkError => statusCode == null;

  factory ApiFailure.fromDio(DioException e) {
    final response = e.response;
    if (response == null) {
      return const ApiFailure(
        "Can't reach the TicOne server. Check the connection and try again.",
      );
    }
    final data = response.data;
    final body = data is Map<String, dynamic> ? data : null;
    final message = body?['error'] ?? body?['message'];
    return ApiFailure(
      message is String && message.isNotEmpty
          ? message
          : 'Server error (${response.statusCode})',
      statusCode: response.statusCode,
      body: body,
    );
  }

  @override
  String toString() => 'ApiFailure($statusCode, $message)';
}

/// Dio wrapper that attaches the staff access token and transparently
/// refreshes it (access tokens live 15 minutes; a gate shift is longer).
class ApiClient {
  final Dio dio;
  final SessionStore _sessions;

  /// Called when the session can no longer be refreshed.
  void Function()? onSessionExpired;

  /// Interceptor-free twin used for refresh and retry: requests sent through
  /// [dio] from inside its own queued error handler would deadlock.
  late final Dio _plain = Dio(dio.options)
    ..httpClientAdapter = dio.httpClientAdapter;

  Future<String?>? _refreshing;

  ApiClient(this._sessions, {Dio? dio, String? baseUrl})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? ApiConfig.baseUrl,
              connectTimeout: ApiConfig.timeout,
              receiveTimeout: ApiConfig.timeout,
              sendTimeout: ApiConfig.timeout,
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            ),
          ) {
    this.dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: _attachToken,
        onError: _refreshOnUnauthorized,
      ),
    );
  }

  static const _skipAuth = 'skipAuth';
  static const _retried = 'retried';

  /// Options for calls that must not carry or refresh a token (login etc.).
  static Options get anonymous => Options(extra: {_skipAuth: true});

  Future<void> _attachToken(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_skipAuth] != true) {
      final session = await _sessions.read();
      if (session != null) {
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    }
    handler.next(options);
  }

  Future<void> _refreshOnUnauthorized(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final options = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        options.extra[_skipAuth] == true ||
        options.extra[_retried] == true) {
      return handler.next(error);
    }

    // Errors are handled one at a time: if an earlier 401 already refreshed
    // the session, reuse that token instead of refreshing again.
    final current = (await _sessions.read())?.accessToken;
    final sent = options.headers['Authorization'];
    final token = current != null && sent != 'Bearer $current'
        ? current
        : await _refreshAccessToken();
    if (token == null) {
      onSessionExpired?.call();
      return handler.next(error);
    }

    try {
      options.extra[_retried] = true;
      options.headers['Authorization'] = 'Bearer $token';
      handler.resolve(await _plain.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Exchanges the refresh token for a new pair. Concurrent callers share a
  /// single in-flight refresh.
  Future<String?> _refreshAccessToken() {
    return _refreshing ??= () async {
      try {
        final session = await _sessions.read();
        if (session == null) return null;
        final res = await _plain.post<Map<String, dynamic>>(
          ApiConfig.refreshToken,
          data: {'refreshToken': session.refreshToken},
        );
        final body = res.data ?? const {};
        final payload = body['data'] is Map<String, dynamic>
            ? body['data'] as Map<String, dynamic>
            : body;
        final access = payload['accessToken'] as String?;
        final refresh = payload['refreshToken'] as String?;
        if (access == null || refresh == null) return null;
        await _sessions.write(
          session.withTokens(access: access, refresh: refresh),
        );
        return access;
      } catch (_) {
        return null;
      } finally {
        _refreshing = null;
      }
    }();
  }
}
