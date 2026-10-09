import 'package:flutter/foundation.dart';

/// Mirrors the TicOne customer app's configuration so both apps can point at
/// the same middleware.
class ApiConfig {
  /// Set per launch config via --dart-define=IS_PRODUCTION=true|false.
  static const bool isProduction = bool.fromEnvironment(
    'IS_PRODUCTION',
    defaultValue: false,
  );

  /// Optional override, e.g. --dart-define=API_BASE_URL=http://192.168.1.20:8080
  /// to reach a dev machine from a physical phone on the same network.
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  static const String productionBaseUrl =
      'https://ticonemiddleware-production.up.railway.app';

  /// The Android emulator reaches the host machine via 10.0.2.2.
  static const String _localBaseUrl = 'http://localhost:8080';
  static const String _androidEmulatorBaseUrl = 'http://10.0.2.2:8080';

  static String get baseUrl {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    if (isProduction) return productionBaseUrl;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _androidEmulatorBaseUrl;
    }
    return _localBaseUrl;
  }

  static const String adminLogin = '/api/admin/auth/login';
  static const String refreshToken = '/auth/refresh-token';
  static const String logout = '/auth/logout';

  static String ticket(String code) =>
      '/api/admin/tickets/${Uri.encodeComponent(code)}';
  static String checkIn(String code) => '${ticket(code)}/check-in';
  static String busBooking(int id) => '/api/admin/bus-bookings/$id';

  static const Duration timeout = Duration(seconds: 15);
}
