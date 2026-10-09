import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// In-memory stand-in for the middleware's admin auth + ticket endpoints,
/// plugged into Dio as its HTTP adapter.
class FakeServer implements HttpClientAdapter {
  static const email = 'admin@ticone.com';
  static const password = 'Admin@123';

  final Map<String, Map<String, dynamic>> tickets = {};
  final Set<String> _validAccess = {};
  final Set<String> _validRefresh = {};
  final List<String> calls = [];
  int _tokenSeq = 0;

  /// When set, every request fails as if the network were down.
  bool offline = false;

  void addTicket(Map<String, dynamic> ticket) {
    tickets[ticket['bookingCode'] as String] = ticket;
  }

  /// Simulates the 15-minute access token running out.
  void expireAccessTokens() => _validAccess.clear();

  (String, String) issueTokens() {
    _tokenSeq++;
    final access = 'access-$_tokenSeq';
    final refresh = 'refresh-$_tokenSeq';
    _validAccess.add(access);
    _validRefresh.add(refresh);
    return (access, refresh);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    calls.add('${options.method} $path');
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final body = options.data is Map ? options.data as Map : const {};

    if (path == '/api/admin/auth/login') {
      if (body['email'] != email || body['password'] != password) {
        return _json(401, {'error': 'Invalid admin credentials'});
      }
      final (access, refresh) = issueTokens();
      return _json(200, {
        'accessToken': access,
        'refreshToken': refresh,
        'user': {'name': 'TicOne Super Admin', 'email': email, 'role': 'admin'},
      });
    }
    if (path == '/auth/refresh-token') {
      final token = body['refreshToken'];
      if (!_validRefresh.remove(token)) {
        return _json(401, {'error': 'Invalid refresh token'});
      }
      final (access, refresh) = issueTokens();
      return _json(200, {'accessToken': access, 'refreshToken': refresh});
    }
    if (path == '/auth/logout') {
      _validRefresh.remove(body['refreshToken']);
      return _json(200, {'message': 'ok'});
    }

    final auth = options.headers['Authorization']?.toString() ?? '';
    if (!_validAccess.contains(auth.replaceFirst('Bearer ', ''))) {
      return _json(401, {
        'status': 'error',
        'message': 'Authentication required',
      });
    }

    final match = RegExp(
      r'^/api/admin/tickets/([^/]+)(/check-in)?$',
    ).firstMatch(path);
    if (match != null) {
      final code = Uri.decodeComponent(match.group(1)!).toUpperCase();
      final ticket =
          tickets[code] ??
          tickets.values.where((t) => t['pnrNumber'] == code).firstOrNull;
      if (ticket == null) {
        return _json(404, {'error': 'Ticket not found', 'reason': 'NOT_FOUND'});
      }
      if (match.group(2) == null) return _json(200, {'ticket': ticket});

      if (ticket['checkedInAt'] != null) {
        return _json(409, {
          'error': 'Ticket has already been used',
          'reason': 'ALREADY_CHECKED_IN',
          'ticket': ticket,
        });
      }
      if (ticket['bookingStatus'] != 'confirmed') {
        return _json(409, {
          'error': 'Ticket was cancelled',
          'reason': 'CANCELLED',
          'ticket': ticket,
        });
      }
      ticket['checkedInAt'] = DateTime.now().toUtc().toIso8601String();
      ticket['checkedInBy'] = 'TicOne Super Admin';
      return _json(200, {'message': 'Ticket checked in', 'ticket': ticket});
    }

    final bus = RegExp(r'^/api/admin/bus-bookings/(\d+)$').firstMatch(path);
    if (bus != null) {
      final id = int.parse(bus.group(1)!);
      final ticket = tickets.values
          .where((t) => t['type'] == 'bus' && t['id'] == id)
          .firstOrNull;
      return ticket == null
          ? _json(404, {'error': 'Bus booking not found'})
          : _json(200, {'booking': ticket});
    }

    return _json(404, {'error': 'No route'});
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> movieTicketJson({
  String code = 'TIC-2026-459306',
  required DateTime showTime,
  String status = 'confirmed',
  String payment = 'completed',
  String? checkedInAt,
}) => {
  'type': 'movie',
  'id': 36,
  'bookingCode': code,
  'userName': 'Ranjith',
  'userPhone': '9876543210',
  'movieTitle': 'Dune: Part Two',
  'movieLanguage': 'English',
  'movieFormat': 'IMAX 70MM',
  'theaterName': 'Grand IMAX Dolby Suite',
  'screenName': 'Audi 1',
  'showTime': showTime.toUtc().toIso8601String(),
  'paymentStatus': payment,
  'bookingStatus': status,
  'seats': [
    {'seatIdentifier': 'C3', 'tierName': 'Gold', 'price': 438.0},
    {'seatIdentifier': 'C4', 'tierName': 'Gold', 'price': 438.0},
  ],
  'checkedInAt': checkedInAt,
  'checkedInBy': checkedInAt == null ? null : 'Gate 2',
};

Map<String, dynamic> busTicketJson({
  String code = 'TIC-BUS-2026-881290',
  String pnr = 'PNR881290',
  int id = 1,
  required DateTime departure,
  String status = 'confirmed',
}) => {
  'type': 'bus',
  'id': id,
  'bookingCode': code,
  'pnrNumber': pnr,
  'userName': 'Ranjith',
  'contactPhone': '9876543210',
  'busName': 'IntrCity SmartBus Volvo',
  'busNumber': 'KA-01-AJ-4001',
  'operatorName': 'IntrCity SmartBus',
  'sourceCity': 'Bengaluru',
  'destinationCity': 'Chennai',
  'departureTime': departure.toUtc().toIso8601String(),
  'arrivalTime': departure
      .add(const Duration(hours: 6))
      .toUtc()
      .toIso8601String(),
  'boardingName': 'Majestic - Anand Rao Circle',
  'boardingTime': '10:30 PM',
  'paymentStatus': 'completed',
  'bookingStatus': status,
  'passengers': [
    {
      'seatNumber': 'L1',
      'passengerName': 'Ranjith',
      'age': 28,
      'gender': 'Male',
    },
    {
      'seatNumber': 'L2',
      'passengerName': 'Priya Sharma',
      'age': 26,
      'gender': 'Female',
    },
  ],
  'checkedInAt': null,
  'checkedInBy': null,
};
