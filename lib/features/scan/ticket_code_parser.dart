import 'dart:convert';

import 'package:equatable/equatable.dart';

/// What a scanned QR (or typed code) points at.
sealed class TicketRef extends Equatable {
  const TicketRef();

  /// Human-readable form shown while verifying and in history.
  String get label;
}

/// A booking code (`TIC-…`, `TIC-BUS-…`) or a bus PNR (`PNR…`).
class TicketCode extends TicketRef {
  final String code;
  const TicketCode(this.code);

  @override
  String get label => code;

  @override
  List<Object?> get props => [code];
}

/// Older TicOne bus passes only carry the internal bus booking id.
class BusBookingId extends TicketRef {
  final int id;
  const BusBookingId(this.id);

  @override
  String get label => 'Bus ticket #$id';

  @override
  List<Object?> get props => [id];
}

/// Extracts a [TicketRef] from every QR format the TicOne app has issued:
///
/// * server `qrCodeData` — base64 JSON `{"code": "TIC-…", …}`
/// * plain JSON with a `code` field
/// * text passes (`TICONE DIGITAL CINEMA PASS\nBooking ID: #TIC-…`,
///   `TICONE EXPRESS BUS TICKET\nTicket ID: 12`)
/// * a bare booking code or PNR, e.g. typed in by staff
///
/// Returns null when the input is not a TicOne ticket.
class TicketCodeParser {
  static final _codePattern = RegExp(
    r'TIC-(?:BUS-)?\d{4}-\d+',
    caseSensitive: false,
  );
  static final _pnrPattern = RegExp(r'\bPNR\d+\b', caseSensitive: false);
  static final _busTicketId = RegExp(
    r'^Ticket ID:\s*(\d+)\s*$',
    multiLine: true,
    caseSensitive: false,
  );

  static TicketRef? parse(String? raw) {
    final input = raw?.trim() ?? '';
    if (input.isEmpty) return null;

    final fromJson = _codeFromJson(input) ?? _codeFromJson(_tryBase64(input));
    if (fromJson != null) return TicketCode(fromJson.toUpperCase());

    final code =
        _codePattern.firstMatch(input) ?? _pnrPattern.firstMatch(input);
    if (code != null) return TicketCode(code.group(0)!.toUpperCase());

    if (input.toUpperCase().contains('TICONE EXPRESS BUS')) {
      final id = int.tryParse(_busTicketId.firstMatch(input)?.group(1) ?? '');
      if (id != null) return BusBookingId(id);
    }
    return null;
  }

  /// True for a TicOne bus pass that has no usable reference in its QR, so
  /// staff should type the PNR printed on the ticket instead.
  static bool isUnverifiableBusPass(String? raw) =>
      (raw ?? '').toUpperCase().contains('TICONE EXPRESS BUS') &&
      parse(raw) == null;

  static String? _codeFromJson(String? text) {
    if (text == null || !text.trimLeft().startsWith('{')) return null;
    try {
      final decoded = jsonDecode(text);
      final code = decoded is Map ? decoded['code'] ?? decoded['pnr'] : null;
      return code is String && code.trim().isNotEmpty ? code.trim() : null;
    } catch (_) {
      return null;
    }
  }

  static String? _tryBase64(String text) {
    try {
      return utf8.decode(base64Decode(base64.normalize(text)));
    } catch (_) {
      return null;
    }
  }
}
