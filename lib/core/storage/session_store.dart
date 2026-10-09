import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A signed-in staff member (an admin account on the middleware).
class StaffSession extends Equatable {
  final String accessToken;
  final String refreshToken;
  final String name;
  final String email;

  const StaffSession({
    required this.accessToken,
    required this.refreshToken,
    required this.name,
    required this.email,
  });

  StaffSession withTokens({required String access, required String refresh}) =>
      StaffSession(
        accessToken: access,
        refreshToken: refresh,
        name: name,
        email: email,
      );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'name': name,
    'email': email,
  };

  factory StaffSession.fromJson(Map<String, dynamic> json) => StaffSession(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
  );

  @override
  List<Object?> get props => [accessToken, refreshToken, name, email];
}

/// Persists the staff session. Tokens are admin credentials, so the default
/// implementation keeps them in the platform keychain / keystore.
abstract class SessionStore {
  Future<StaffSession?> read();
  Future<void> write(StaffSession session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'staff_session';
  final FlutterSecureStorage _storage;

  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<StaffSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return StaffSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(StaffSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemorySessionStore implements SessionStore {
  StaffSession? _session;

  MemorySessionStore([this._session]);

  @override
  Future<StaffSession?> read() async => _session;

  @override
  Future<void> write(StaffSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
