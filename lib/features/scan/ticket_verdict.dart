import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import 'ticket.dart';

enum VerdictLevel { valid, warning, invalid }

class TicketVerdict extends Equatable {
  final VerdictLevel level;
  final String headline;
  final String detail;

  const TicketVerdict(this.level, this.headline, this.detail);

  /// Staff may admit valid tickets, and warnings after confirming.
  bool get canAdmit => level != VerdictLevel.invalid;

  @override
  List<Object?> get props => [level, headline, detail];
}

/// Entry windows relative to the show time / departure.
class EntryWindow {
  /// Movie gates open this long before the show…
  static const movieOpensBefore = Duration(hours: 1);

  /// …and late entry is allowed until roughly the end of the film.
  static const movieClosesAfter = Duration(hours: 3);

  /// Boarding can start this long before departure…
  static const busOpensBefore = Duration(hours: 2);

  /// …and later boarding points are reached until arrival (or this long
  /// after departure when the arrival time is unknown).
  static const busFallbackClosesAfter = Duration(hours: 12);
}

final _when = DateFormat('EEE d MMM, h:mm a');
final _time = DateFormat('h:mm a');

TicketVerdict evaluateTicket(Ticket t, DateTime now) {
  final isMovie = t.type == TicketType.movie;

  if (t.checkedInAt != null || t.bookingStatus == 'checked_in') {
    final at = t.checkedInAt;
    final by = t.checkedInBy;
    return TicketVerdict(
      VerdictLevel.invalid,
      'Already used',
      [
        if (at != null)
          'Checked in ${_isSameDay(at, now) ? 'today at ${_time.format(at)}' : _when.format(at)}',
        if (by != null && by.isNotEmpty) 'by $by',
      ].join(' ').ifEmpty('This ticket has already been checked in.'),
    );
  }
  if (t.bookingStatus == 'cancelled') {
    return const TicketVerdict(
      VerdictLevel.invalid,
      'Cancelled',
      'This booking was cancelled and refunded.',
    );
  }
  if (t.paymentStatus != 'completed') {
    return TicketVerdict(
      VerdictLevel.invalid,
      'Payment not completed',
      'Payment status: ${t.paymentStatus.ifEmpty('unknown')}.',
    );
  }
  if (t.bookingStatus != 'confirmed') {
    return TicketVerdict(
      VerdictLevel.invalid,
      'Not valid for entry',
      'Booking status: ${t.bookingStatus.ifEmpty('unknown')}.',
    );
  }

  final opens = t.startsAt.subtract(
    isMovie ? EntryWindow.movieOpensBefore : EntryWindow.busOpensBefore,
  );
  final closes = isMovie
      ? t.startsAt.add(EntryWindow.movieClosesAfter)
      : t.endsAt ?? t.startsAt.add(EntryWindow.busFallbackClosesAfter);
  final startLabel =
      '${isMovie ? 'Show' : 'Departure'}: ${_when.format(t.startsAt)}';

  if (now.isAfter(closes)) {
    return TicketVerdict(
      VerdictLevel.invalid,
      isMovie ? 'Show is over' : 'Trip completed',
      'Expired ticket. $startLabel',
    );
  }
  if (now.isBefore(opens)) {
    return TicketVerdict(
      VerdictLevel.warning,
      _isSameDay(t.startsAt, now) ? 'Too early' : 'Different day',
      '$startLabel. Check before admitting.',
    );
  }

  return TicketVerdict(
    VerdictLevel.valid,
    'Valid ticket',
    'Admit ${t.admitLabel} · $startLabel',
  );
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
