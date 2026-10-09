import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/scanner_theme.dart';
import 'scan_cubit.dart';
import 'ticket.dart';
import 'ticket_verdict.dart';

/// Full-screen verdict shown after a scan: big colour-coded status first, so
/// staff can decide at a glance, then the booking details to check against.
class ScanResultPanel extends StatelessWidget {
  final ScanState state;
  final VoidCallback onAdmit;
  final VoidCallback onNext;
  final VoidCallback onRetry;
  final VoidCallback onEnterCode;

  const ScanResultPanel({
    super.key,
    required this.state,
    required this.onAdmit,
    required this.onNext,
    required this.onRetry,
    required this.onEnterCode,
  });

  @override
  Widget build(BuildContext context) {
    if (state.phase == ScanPhase.verifying) {
      return _Verifying(reference: state.reference);
    }

    final verdict = state.verdict;
    final level = verdict?.level ?? VerdictLevel.invalid;
    final color = ScannerColors.forLevel(level);
    final ticket = state.ticket;

    return ColoredBox(
      color: ScannerColors.background,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  _VerdictBanner(
                    color: color,
                    icon: state.phase == ScanPhase.admitted
                        ? Icons.verified_rounded
                        : ScannerColors.iconForLevel(level),
                    headline: verdict?.headline ?? state.title ?? 'Not valid',
                    detail: verdict?.detail ?? state.message ?? '',
                  ),
                  if (ticket != null) ...[
                    const SizedBox(height: 14),
                    _TicketDetails(ticket: ticket),
                  ],
                  if (ticket != null && state.message != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      state.message!,
                      style: const TextStyle(
                        color: ScannerColors.invalid,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _actions(level, color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(VerdictLevel level, Color color) {
    final ticket = state.ticket;
    final canAdmit =
        ticket != null &&
        (state.phase == ScanPhase.result ||
            state.phase == ScanPhase.admitting) &&
        (state.verdict?.canAdmit ?? false);
    final admitting = state.phase == ScanPhase.admitting;

    return [
      if (canAdmit) ...[
        FilledButton.icon(
          key: const Key('admit-button'),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: level == VerdictLevel.warning
                ? Colors.black
                : Colors.white,
          ),
          onPressed: admitting ? null : onAdmit,
          icon: admitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.how_to_reg_rounded),
          label: Text(
            level == VerdictLevel.warning
                ? 'Admit anyway'
                : 'Admit ${ticket.admitLabel}',
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (state.phase == ScanPhase.failed && state.canRetry) ...[
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
        const SizedBox(height: 10),
      ],
      if (state.phase == ScanPhase.failed) ...[
        OutlinedButton.icon(
          onPressed: onEnterCode,
          icon: const Icon(Icons.keyboard_rounded),
          label: const Text('Enter code or PNR'),
        ),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        key: const Key('scan-next-button'),
        onPressed: admitting ? null : onNext,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan next'),
      ),
    ];
  }
}

class _Verifying extends StatelessWidget {
  final String? reference;
  const _Verifying({this.reference});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ScannerColors.background.withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 4),
            ),
            const SizedBox(height: 20),
            const Text(
              'Verifying ticket…',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (reference != null) ...[
              const SizedBox(height: 6),
              Text(
                reference!,
                style: const TextStyle(color: ScannerColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String headline;
  final String detail;

  const _VerdictBanner({
    required this.color,
    required this.icon,
    required this.headline,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final onColor = color == ScannerColors.warning
        ? Colors.black
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 72, color: onColor),
          const SizedBox(height: 10),
          Text(
            headline.toUpperCase(),
            key: const Key('verdict-headline'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onColor.withValues(alpha: 0.9),
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketDetails extends StatelessWidget {
  final Ticket ticket;
  const _TicketDetails({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final isMovie = ticket.type == TicketType.movie;
    final when = DateFormat('EEE d MMM yyyy · h:mm a').format(ticket.startsAt);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ScannerColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ScannerColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Chip(
                icon: isMovie
                    ? Icons.movie_rounded
                    : Icons.directions_bus_rounded,
                label: isMovie ? 'MOVIE' : 'BUS',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ticket.bookingCode,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ScannerColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            ticket.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _Line(icon: Icons.schedule_rounded, text: when),
          if (ticket.venue.isNotEmpty)
            _Line(
              icon: isMovie ? Icons.theaters_rounded : Icons.business_rounded,
              text: ticket.venue,
            ),
          if (ticket.subVenue.isNotEmpty)
            _Line(icon: Icons.info_outline_rounded, text: ticket.subVenue),
          if (ticket.boardingPoint != null && ticket.boardingPoint!.isNotEmpty)
            _Line(
              icon: Icons.place_outlined,
              text:
                  'Boarding: ${ticket.boardingPoint}${ticket.boardingTime == null ? '' : ' · ${ticket.boardingTime}'}',
            ),
          if (ticket.pnr != null)
            _Line(icon: Icons.tag_rounded, text: ticket.pnr!),
          const Divider(height: 28, color: ScannerColors.outline),
          if (isMovie) ...[
            Text(
              '${ticket.seats.length} ${ticket.seats.length == 1 ? 'SEAT' : 'SEATS'}',
              style: const TextStyle(
                color: ScannerColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final s in ticket.seats) _SeatBadge(s)],
            ),
          ] else ...[
            Text(
              '${ticket.passengers.length} ${ticket.passengers.length == 1 ? 'PASSENGER' : 'PASSENGERS'}',
              style: const TextStyle(
                color: ScannerColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            for (final p in ticket.passengers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    _SeatBadge(p.seat),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      [
                        if (p.age != null) '${p.age}',
                        if (p.gender.isNotEmpty) p.gender[0].toUpperCase(),
                      ].join(' · '),
                      style: const TextStyle(color: ScannerColors.textMuted),
                    ),
                  ],
                ),
              ),
          ],
          if (ticket.customerName.isNotEmpty) ...[
            const Divider(height: 28, color: ScannerColors.outline),
            _Line(
              icon: Icons.person_outline_rounded,
              text: [
                ticket.customerName,
                ticket.customerPhone,
              ].where((s) => s.isNotEmpty).join(' · '),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ScannerColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ScannerColors.brand.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: ScannerColors.brand),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: ScannerColors.brand,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatBadge extends StatelessWidget {
  final String seat;
  const _SeatBadge(this.seat);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ScannerColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ScannerColors.outline),
      ),
      child: Text(
        seat,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );
  }
}
