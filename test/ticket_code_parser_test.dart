import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tic_one_scanner/features/scan/ticket_code_parser.dart';

String b64(Object json) => base64Encode(utf8.encode(jsonEncode(json)));

void main() {
  group('TicketCodeParser', () {
    test('reads server movie qrCodeData', () {
      // Sample from API_DOCUMENTATION.md §6.1.
      expect(
        TicketCodeParser.parse(
          'eyJjb2RlIjoiVElDLTIwMjYtMjE2MTc1Iiwic2hvd0lkIjoxLCJ1c2VySWQiOjEsInNlYXRzIjpbIkMzIiwiQzQiXX0=',
        ),
        const TicketCode('TIC-2026-216175'),
      );
    });

    test('reads server bus qrCodeData', () {
      expect(
        TicketCodeParser.parse(
          'eyJjb2RlIjoiVElDLUJVUy0yMDI2LTY2NTE0MSIsInBuciI6IlBOUjc1NDc1NzUiLCJ0cmlwSWQiOjEsInVzZXJJZCI6MSwic2VhdHMiOlsiTDQiLCJMNSJdfQ==',
        ),
        const TicketCode('TIC-BUS-2026-665141'),
      );
    });

    test('reads unpadded base64 and plain JSON', () {
      final padded = b64({'code': 'TIC-2026-1'});
      expect(
        TicketCodeParser.parse(padded.replaceAll('=', '')),
        const TicketCode('TIC-2026-1'),
      );
      expect(
        TicketCodeParser.parse('{"code":"tic-2026-1"}'),
        const TicketCode('TIC-2026-1'),
      );
    });

    test('reads the text pass from My Bookings', () {
      const qr = '''TICONE DIGITAL CINEMA PASS
Booking ID: #TIC-2026-459306
Movie: Dune: Part Two
Format: IMAX
Theater: Grand IMAX
Showtime: 7:45 PM
Seats: C7
Status: CONFIRMED & ACTIVE''';
      expect(TicketCodeParser.parse(qr), const TicketCode('TIC-2026-459306'));
    });

    test('reads the booking-success text pass with seat tier etc.', () {
      const qr =
          'TICONE DIGITAL CINEMA PASS\nBooking ID: TIC-2026-12\nSeats: C7 (1 Seat)\nTier: Gold';
      expect(TicketCodeParser.parse(qr), const TicketCode('TIC-2026-12'));
    });

    test('reads the bus pass by numeric booking id', () {
      const qr = '''TICONE EXPRESS BUS TICKET
Ticket ID: 12
Route: Bengaluru to Chennai
Seats: L1, L2''';
      expect(TicketCodeParser.parse(qr), const BusBookingId(12));
      expect(TicketCodeParser.isUnverifiableBusPass(qr), isFalse);
    });

    test('flags a bus pass with no reference so staff type the PNR', () {
      const qr =
          'TICONE EXPRESS BUS TICKET\nTicket ID: \nRoute: Bengaluru to Chennai';
      expect(TicketCodeParser.parse(qr), isNull);
      expect(TicketCodeParser.isUnverifiableBusPass(qr), isTrue);
    });

    test('accepts typed codes and PNRs in any case', () {
      expect(
        TicketCodeParser.parse('  tic-bus-2026-881290 '),
        const TicketCode('TIC-BUS-2026-881290'),
      );
      expect(
        TicketCodeParser.parse('pnr881290'),
        const TicketCode('PNR881290'),
      );
    });

    test('rejects QR codes that are not TicOne tickets', () {
      expect(TicketCodeParser.parse('https://example.com'), isNull);
      expect(TicketCodeParser.parse('WIFI:S:cafe;T:WPA;P:secret;;'), isNull);
      expect(TicketCodeParser.parse(b64({'foo': 'bar'})), isNull);
      expect(TicketCodeParser.parse(''), isNull);
    });
  });
}
