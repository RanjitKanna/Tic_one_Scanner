import 'package:dio/dio.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import 'ticket.dart';
import 'ticket_code_parser.dart';

class TicketNotFound implements Exception {
  const TicketNotFound();
}

class CheckInResult {
  final Ticket ticket;
  final bool admitted;

  /// Server reason when not admitted, e.g. `ALREADY_CHECKED_IN`.
  final String? reason;
  final String? message;

  const CheckInResult({
    required this.ticket,
    required this.admitted,
    this.reason,
    this.message,
  });
}

class TicketRepository {
  final ApiClient _api;

  TicketRepository(this._api);

  /// Looks a ticket up without admitting it.
  ///
  /// Throws [TicketNotFound] or [ApiFailure].
  Future<Ticket> lookup(TicketRef ref) async {
    final code = switch (ref) {
      TicketCode(:final code) => code,
      BusBookingId(:final id) => await _busCodeForId(id),
    };
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        ApiConfig.ticket(code),
      );
      return Ticket.fromJson(res.data!['ticket'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const TicketNotFound();
      throw ApiFailure.fromDio(e);
    }
  }

  /// Admits a ticket. The server only allows this once per booking.
  Future<CheckInResult> checkIn(Ticket ticket) async {
    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        ApiConfig.checkIn(ticket.reference),
      );
      return CheckInResult(
        ticket: Ticket.fromJson(res.data!['ticket'] as Map<String, dynamic>),
        admitted: true,
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      if (e.response?.statusCode == 409 && body is Map<String, dynamic>) {
        return CheckInResult(
          ticket: Ticket.fromJson(body['ticket'] as Map<String, dynamic>),
          admitted: false,
          reason: body['reason'] as String?,
          message: body['error'] as String?,
        );
      }
      if (e.response?.statusCode == 404) throw const TicketNotFound();
      throw ApiFailure.fromDio(e);
    }
  }

  /// Old bus passes only carry the numeric booking id; resolve it to a code
  /// through the admin bus-bookings endpoint.
  Future<String> _busCodeForId(int id) async {
    try {
      final res = await _api.dio.get<Map<String, dynamic>>(
        ApiConfig.busBooking(id),
      );
      final code = (res.data?['booking'] as Map?)?['bookingCode'] as String?;
      if (code == null || code.isEmpty) throw const TicketNotFound();
      return code;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const TicketNotFound();
      throw ApiFailure.fromDio(e);
    }
  }
}
