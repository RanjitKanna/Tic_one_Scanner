import 'package:flutter_test/flutter_test.dart';
import 'package:tic_one_scanner/features/scan/ticket.dart';
import 'package:tic_one_scanner/features/scan/ticket_verdict.dart';

import 'helpers/fake_server.dart';

void main() {
  final now = DateTime(2026, 10, 9, 19, 30);

  Ticket movie({
    Duration showIn = const Duration(minutes: 15),
    String status = 'confirmed',
    String payment = 'completed',
    String? checkedInAt,
  }) => Ticket.fromJson(
    movieTicketJson(
      showTime: now.add(showIn),
      status: status,
      payment: payment,
      checkedInAt: checkedInAt,
    ),
  );

  Ticket bus({Duration departsIn = const Duration(minutes: 30)}) =>
      Ticket.fromJson(busTicketJson(departure: now.add(departsIn)));

  test('a confirmed ticket for a show starting soon is valid', () {
    final v = evaluateTicket(movie(), now);
    expect(v.level, VerdictLevel.valid);
    expect(v.detail, startsWith('Admit 2 guests'));
    expect(v.canAdmit, isTrue);
  });

  test('late arrival during the show is still valid', () {
    expect(
      evaluateTicket(movie(showIn: -const Duration(hours: 1)), now).level,
      VerdictLevel.valid,
    );
  });

  test('an already checked-in ticket is rejected and says when', () {
    final v = evaluateTicket(
      movie(
        checkedInAt: now
            .subtract(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String(),
      ),
      now,
    );
    expect(v.level, VerdictLevel.invalid);
    expect(v.headline, 'Already used');
    expect(v.detail, contains('today at 7:25 PM'));
    expect(v.detail, contains('Gate 2'));
    expect(v.canAdmit, isFalse);
  });

  test('cancelled and unpaid tickets are rejected', () {
    expect(
      evaluateTicket(movie(status: 'cancelled'), now).headline,
      'Cancelled',
    );
    expect(
      evaluateTicket(movie(payment: 'pending'), now).headline,
      'Payment not completed',
    );
  });

  test('a ticket for a finished show is expired', () {
    final v = evaluateTicket(movie(showIn: -const Duration(hours: 4)), now);
    expect(v.level, VerdictLevel.invalid);
    expect(v.headline, 'Show is over');
  });

  test('a ticket for another day is a warning staff can override', () {
    final v = evaluateTicket(movie(showIn: const Duration(days: 2)), now);
    expect(v.level, VerdictLevel.warning);
    expect(v.headline, 'Different day');
    expect(v.canAdmit, isTrue);
  });

  test('bus boarding is valid until arrival, expired after', () {
    expect(evaluateTicket(bus(), now).detail, startsWith('Admit 2 passengers'));
    expect(
      evaluateTicket(bus(departsIn: -const Duration(hours: 5)), now).level,
      VerdictLevel.valid,
    );
    expect(
      evaluateTicket(bus(departsIn: -const Duration(hours: 7)), now).headline,
      'Trip completed',
    );
  });
}
