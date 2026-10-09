import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tic_one_scanner/core/network/api_client.dart';
import 'package:tic_one_scanner/core/storage/session_store.dart';
import 'package:tic_one_scanner/features/auth/auth_cubit.dart';
import 'package:tic_one_scanner/features/auth/auth_repository.dart';
import 'package:tic_one_scanner/features/history/scan_history.dart';
import 'package:tic_one_scanner/features/scan/scan_cubit.dart';
import 'package:tic_one_scanner/features/scan/ticket_code_parser.dart';
import 'package:tic_one_scanner/features/scan/ticket_repository.dart';
import 'package:tic_one_scanner/features/scan/ticket_verdict.dart';

import 'helpers/fake_server.dart';

void main() {
  late FakeServer server;
  late MemorySessionStore sessions;
  late ApiClient api;
  late AuthCubit auth;
  late ScanHistoryCubit history;
  late ScanCubit scan;
  final now = DateTime.now();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = FakeServer()
      ..addTicket(
        movieTicketJson(showTime: now.add(const Duration(minutes: 20))),
      )
      ..addTicket(
        movieTicketJson(
          code: 'TIC-2026-136112',
          showTime: now,
          status: 'cancelled',
          payment: 'refunded',
        ),
      )
      ..addTicket(
        busTicketJson(departure: now.add(const Duration(minutes: 40))),
      );
    sessions = MemorySessionStore();
    api = ApiClient(
      sessions,
      dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    );
    auth = AuthCubit(AuthRepository(api, sessions));
    api.onSessionExpired = auth.sessionExpired;
    history = ScanHistoryCubit();
    scan = ScanCubit(TicketRepository(api), history);
    await auth.login(FakeServer.email, FakeServer.password);
  });

  test('wrong admin password is rejected with the server message', () async {
    await auth.logout();
    await auth.login(FakeServer.email, 'nope');
    expect(auth.state.status, AuthStatus.signedOut);
    expect(auth.state.error, 'Invalid admin credentials');
  });

  test('scan → valid → admit → second scan says already used', () async {
    await scan.onScanned('{"code":"TIC-2026-459306"}');
    expect(scan.state.phase, ScanPhase.result);
    expect(scan.state.verdict!.level, VerdictLevel.valid);
    expect(scan.state.ticket!.seats, ['C3', 'C4']);

    await scan.admit();
    expect(scan.state.phase, ScanPhase.admitted);
    expect(history.state.first.outcome, ScanOutcome.admitted);
    expect(history.admittedToday(DateTime.now()), 1);

    scan.reset();
    await scan.onScanned(
      'TICONE DIGITAL CINEMA PASS\nBooking ID: #TIC-2026-459306',
    );
    expect(scan.state.verdict!.headline, 'Already used');
    expect(scan.state.verdict!.canAdmit, isFalse);
  });

  test('losing a race with another gate shows Already used', () async {
    await scan.onScanned('TIC-2026-459306');
    // Another device admits the ticket between lookup and admit.
    server.tickets['TIC-2026-459306']!['checkedInAt'] = DateTime.now()
        .toUtc()
        .toIso8601String();
    await scan.admit();
    expect(scan.state.phase, ScanPhase.result);
    expect(scan.state.verdict!.headline, 'Already used');
    expect(history.state.first.outcome, ScanOutcome.rejected);
  });

  test('cancelled ticket cannot be admitted', () async {
    await scan.onScanned('TIC-2026-136112');
    expect(scan.state.verdict!.headline, 'Cancelled');
    await scan.admit();
    expect(server.calls.where((c) => c.endsWith('/check-in')), isEmpty);
  });

  test('bus ticket by PNR and by legacy numeric id', () async {
    await scan.onCodeEntered('pnr881290');
    expect(scan.state.ticket!.passengers.map((p) => p.name), [
      'Ranjith',
      'Priya Sharma',
    ]);
    expect(scan.state.verdict!.level, VerdictLevel.valid);

    scan.reset();
    await scan.onScanned(
      'TICONE EXPRESS BUS TICKET\nTicket ID: 1\nRoute: Bengaluru to Chennai',
    );
    expect(scan.state.ticket!.bookingCode, 'TIC-BUS-2026-881290');
  });

  test('unknown codes and foreign QR codes fail clearly', () async {
    await scan.onScanned('TIC-2026-000000');
    expect(scan.state.phase, ScanPhase.failed);
    expect(scan.state.title, 'Ticket not found');
    expect(history.state.first.outcome, ScanOutcome.notFound);

    scan.reset();
    await scan.onScanned('https://example.com');
    expect(scan.state.title, 'Not a TicOne ticket');
    expect(server.calls.where((c) => c.contains('example')), isEmpty);
  });

  test('duplicate detections while a result is showing are ignored', () async {
    await scan.onScanned('TIC-2026-459306');
    final calls = server.calls.length;
    await scan.onScanned('TIC-2026-459306');
    await scan.onScanned('TIC-BUS-2026-881290');
    expect(server.calls.length, calls);
    expect(scan.state.ticket!.bookingCode, 'TIC-2026-459306');
  });

  test('network failure offers a retry', () async {
    server.offline = true;
    await scan.onScanned('TIC-2026-459306');
    expect(scan.state.phase, ScanPhase.failed);
    expect(scan.state.canRetry, isTrue);
    expect(scan.state.title, 'No connection');

    server.offline = false;
    await scan.retry();
    expect(scan.state.phase, ScanPhase.result);
  });

  test('expired access token is refreshed transparently', () async {
    final before = await sessions.read();
    server.expireAccessTokens();
    await scan.onScanned('TIC-2026-459306');
    expect(scan.state.phase, ScanPhase.result);
    expect(
      server.calls,
      containsAllInOrder([
        'GET /api/admin/tickets/TIC-2026-459306',
        'POST /auth/refresh-token',
        'GET /api/admin/tickets/TIC-2026-459306',
      ]),
    );
    expect((await sessions.read())!.accessToken, isNot(before!.accessToken));
  });

  test('concurrent 401s share one refresh', () async {
    server.expireAccessTokens();
    final repo = TicketRepository(api);
    await Future.wait([
      repo.lookup(const TicketCode('TIC-2026-459306')),
      repo.lookup(const TicketCode('TIC-BUS-2026-881290')),
    ]);
    expect(
      server.calls.where((c) => c == 'POST /auth/refresh-token'),
      hasLength(1),
    );
  });

  test('rejected refresh token signs staff out', () async {
    server
      ..expireAccessTokens()
      ..tickets.clear();
    final session = await sessions.read();
    await sessions.write(session!.withTokens(access: 'dead', refresh: 'dead'));
    await scan.onScanned('TIC-2026-459306');
    expect(auth.state.status, AuthStatus.signedOut);
    expect(auth.state.error, contains('session expired'));
  });
}
