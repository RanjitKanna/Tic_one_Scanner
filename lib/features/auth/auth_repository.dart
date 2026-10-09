import 'package:dio/dio.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';

/// Staff sign in with the same admin account as the TicOne Admin console.
class AuthRepository {
  final ApiClient _api;
  final SessionStore _sessions;

  AuthRepository(this._api, this._sessions);

  Future<StaffSession?> restore() => _sessions.read();

  /// Throws [ApiFailure] with the server's message (wrong password, account
  /// not an admin, disabled account…).
  Future<StaffSession> login(String email, String password) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        ApiConfig.adminLogin,
        data: {'email': email.trim(), 'password': password},
        options: ApiClient.anonymous,
      );
      final body = res.data ?? const {};
      final user = body['user'] as Map<String, dynamic>? ?? const {};
      final session = StaffSession(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
        name: user['name']?.toString() ?? '',
        email: user['email']?.toString() ?? email.trim(),
      );
      await _sessions.write(session);
      return session;
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    }
  }

  /// Revokes the refresh token on the server (best effort) and forgets the
  /// session locally.
  Future<void> logout() async {
    final session = await _sessions.read();
    await _sessions.clear();
    if (session == null) return;
    try {
      await _api.dio.post<void>(
        ApiConfig.logout,
        data: {'refreshToken': session.refreshToken},
        options: ApiClient.anonymous.copyWith(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
    } catch (_) {
      // Already signed out locally; an expired token is fine to leave.
    }
  }
}
