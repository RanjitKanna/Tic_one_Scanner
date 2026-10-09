import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_client.dart';
import '../history/scan_history.dart';
import 'ticket.dart';
import 'ticket_code_parser.dart';
import 'ticket_repository.dart';
import 'ticket_verdict.dart';

enum ScanPhase {
  /// Camera live, waiting for a QR.
  ready,
  verifying,

  /// A ticket was found; [ScanState.verdict] says whether to admit it.
  result,
  admitting,
  admitted,

  /// Unreadable QR, unknown ticket or network problem.
  failed,
}

class ScanState extends Equatable {
  final ScanPhase phase;
  final String? reference;
  final Ticket? ticket;
  final TicketVerdict? verdict;
  final String? title;
  final String? message;

  /// The last failure was a network/server error worth retrying.
  final bool canRetry;

  const ScanState({
    this.phase = ScanPhase.ready,
    this.reference,
    this.ticket,
    this.verdict,
    this.title,
    this.message,
    this.canRetry = false,
  });

  bool get isBusy =>
      phase == ScanPhase.verifying || phase == ScanPhase.admitting;

  @override
  List<Object?> get props => [
    phase,
    reference,
    ticket,
    verdict,
    title,
    message,
    canRetry,
  ];
}

class ScanCubit extends Cubit<ScanState> {
  final TicketRepository _tickets;
  final ScanHistoryCubit _history;
  final DateTime Function() _now;

  TicketRef? _lastRef;

  ScanCubit(this._tickets, this._history, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now,
      super(const ScanState());

  /// Handles a raw QR value. Ignored unless the scanner is ready, so a QR
  /// held in front of the camera is processed once.
  Future<void> onScanned(String? raw) async {
    if (state.phase != ScanPhase.ready) return;
    final ref = TicketCodeParser.parse(raw);
    if (ref == null) {
      final busPass = TicketCodeParser.isUnverifiableBusPass(raw);
      _fail(
        reference: 'Unknown QR',
        title: busPass ? 'Enter the PNR' : 'Not a TicOne ticket',
        message: busPass
            ? "This bus pass's QR has no booking reference. Type the PNR shown on the ticket."
            : "This QR code isn't a TicOne movie or bus ticket.",
        outcome: ScanOutcome.rejected,
      );
      return;
    }
    await verify(ref);
  }

  /// Handles a booking code or PNR typed by staff.
  Future<void> onCodeEntered(String input) async {
    final ref =
        TicketCodeParser.parse(input) ??
        (input.trim().isEmpty ? null : TicketCode(input.trim().toUpperCase()));
    if (ref == null) return;
    await verify(ref);
  }

  Future<void> verify(TicketRef ref) async {
    _lastRef = ref;
    emit(ScanState(phase: ScanPhase.verifying, reference: ref.label));
    try {
      final ticket = await _tickets.lookup(ref);
      final verdict = evaluateTicket(ticket, _now());
      emit(
        ScanState(
          phase: ScanPhase.result,
          reference: ticket.bookingCode,
          ticket: ticket,
          verdict: verdict,
        ),
      );
      _history.add(
        ScanRecord(
          reference: ticket.bookingCode,
          title: ticket.title,
          type: ticket.type.name,
          outcome: switch (verdict.level) {
            VerdictLevel.valid => ScanOutcome.valid,
            VerdictLevel.warning => ScanOutcome.warning,
            VerdictLevel.invalid => ScanOutcome.rejected,
          },
          detail: verdict.headline,
          at: _now(),
        ),
      );
    } on TicketNotFound {
      _fail(
        reference: ref.label,
        title: 'Ticket not found',
        message: 'No TicOne booking matches ${ref.label}. Do not admit.',
        outcome: ScanOutcome.notFound,
      );
    } on ApiFailure catch (e) {
      _fail(
        reference: ref.label,
        title: e.isNetworkError ? 'No connection' : 'Could not verify',
        message: e.message,
        outcome: ScanOutcome.error,
        canRetry: true,
      );
    }
  }

  Future<void> admit() async {
    final ticket = state.ticket;
    if (state.phase != ScanPhase.result || ticket == null) return;
    if (!(state.verdict?.canAdmit ?? false)) return;

    emit(
      ScanState(
        phase: ScanPhase.admitting,
        reference: state.reference,
        ticket: ticket,
        verdict: state.verdict,
      ),
    );
    try {
      final result = await _tickets.checkIn(ticket);
      if (result.admitted) {
        emit(
          ScanState(
            phase: ScanPhase.admitted,
            reference: result.ticket.bookingCode,
            ticket: result.ticket,
            verdict: TicketVerdict(
              VerdictLevel.valid,
              'Admitted',
              '${result.ticket.admitLabel} checked in',
            ),
          ),
        );
        _history.updateLatest(
          ticket.bookingCode,
          ScanOutcome.admitted,
          'Admitted',
        );
        return;
      }
      // Lost a race with another gate, or the booking changed meanwhile.
      final verdict = evaluateTicket(result.ticket, _now());
      emit(
        ScanState(
          phase: ScanPhase.result,
          reference: result.ticket.bookingCode,
          ticket: result.ticket,
          verdict: verdict.canAdmit
              ? TicketVerdict(
                  VerdictLevel.invalid,
                  'Not admitted',
                  result.message ?? 'The server refused this ticket.',
                )
              : verdict,
        ),
      );
      _history.updateLatest(
        ticket.bookingCode,
        ScanOutcome.rejected,
        verdict.headline,
      );
    } on TicketNotFound {
      _fail(
        reference: ticket.bookingCode,
        title: 'Ticket not found',
        message: 'This booking no longer exists. Do not admit.',
        outcome: ScanOutcome.notFound,
      );
    } on ApiFailure catch (e) {
      emit(
        ScanState(
          phase: ScanPhase.result,
          reference: state.reference,
          ticket: ticket,
          verdict: state.verdict,
          message: 'Check-in failed: ${e.message}',
        ),
      );
    }
  }

  Future<void> retry() async {
    final ref = _lastRef;
    if (ref != null && state.phase == ScanPhase.failed) await verify(ref);
  }

  /// Back to the camera for the next ticket.
  void reset() {
    if (state.isBusy) return;
    emit(const ScanState());
  }

  void _fail({
    required String reference,
    required String title,
    required String message,
    required ScanOutcome outcome,
    bool canRetry = false,
  }) {
    emit(
      ScanState(
        phase: ScanPhase.failed,
        reference: reference,
        title: title,
        message: message,
        canRetry: canRetry,
      ),
    );
    if (outcome != ScanOutcome.error) {
      _history.add(
        ScanRecord(
          reference: reference,
          title: title,
          type: null,
          outcome: outcome,
          detail: message,
          at: _now(),
        ),
      );
    }
  }
}
