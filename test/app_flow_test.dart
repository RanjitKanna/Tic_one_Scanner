import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tic_one_scanner/app.dart';
import 'package:tic_one_scanner/core/network/api_client.dart';
import 'package:tic_one_scanner/core/storage/session_store.dart';
import 'package:tic_one_scanner/features/auth/auth_cubit.dart';
import 'package:tic_one_scanner/features/auth/auth_repository.dart';
import 'package:tic_one_scanner/features/history/scan_history.dart';
import 'package:tic_one_scanner/features/scan/ticket_repository.dart';

import 'helpers/fake_server.dart';

/// Stands in for the camera: each button "detects" one QR value.
Widget fakeCamera(BuildContext context, void Function(String?) onDetected) =>
    ColoredBox(
      color: Colors.black,
      child: Align(
        alignment: const Alignment(0, -0.3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: const Key('qr-movie'),
              onPressed: () => onDetected(
                'TICONE DIGITAL CINEMA PASS\nBooking ID: #TIC-2026-459306',
              ),
              child: const Text('movie'),
            ),
            TextButton(
              key: const Key('qr-foreign'),
              onPressed: () => onDetected('https://example.com'),
              child: const Text('foreign'),
            ),
          ],
        ),
      ),
    );

void main() {
  late FakeServer server;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    server = FakeServer()
      ..addTicket(
        movieTicketJson(showTime: now.add(const Duration(minutes: 20))),
      )
      ..addTicket(
        busTicketJson(departure: now.add(const Duration(minutes: 40))),
      );
    final sessions = MemorySessionStore();
    final api = ApiClient(
      sessions,
      dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    );
    final auth = AuthCubit(AuthRepository(api, sessions));
    await auth.restore();

    await tester.pumpWidget(
      ScannerApp(
        authCubit: auth,
        historyCubit: ScanHistoryCubit(),
        tickets: TicketRepository(api),
        cameraBuilder: fakeCamera,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(
    WidgetTester tester, {
    String password = FakeServer.password,
  }) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Admin email'),
      FakeServer.email,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      password,
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('wrong password shows the error and stays on login', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, password: 'wrong');
    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('Invalid admin credentials'), findsOneWidget);
  });

  testWidgets('scan, admit, then the same ticket is rejected', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    expect(find.text('Scan ticket'), findsOneWidget);
    expect(find.text('TicOne Super Admin'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qr-movie')));
    await tester.pumpAndSettle();
    expect(find.text('VALID TICKET'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('C3'), findsOneWidget);
    expect(find.text('Admit 2 guests'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admit-button')));
    await tester.pumpAndSettle();
    expect(find.text('ADMITTED'), findsOneWidget);
    expect(find.byKey(const Key('admit-button')), findsNothing);

    await tester.tap(find.byKey(const Key('scan-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('Admitted today on this device: 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qr-movie')));
    await tester.pumpAndSettle();
    expect(find.text('ALREADY USED'), findsOneWidget);
    expect(find.byKey(const Key('admit-button')), findsNothing);
  });

  testWidgets('foreign QR is rejected; manual PNR entry finds the bus ticket', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester);

    await tester.tap(find.byKey(const Key('qr-foreign')));
    await tester.pumpAndSettle();
    expect(find.text('NOT A TICONE TICKET'), findsOneWidget);

    await tester.tap(find.text('Enter code or PNR'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manual-code-field')),
      'pnr881290',
    );
    await tester.tap(find.byKey(const Key('manual-verify-button')));
    await tester.pumpAndSettle();

    expect(find.text('VALID TICKET'), findsOneWidget);
    expect(find.text('Bengaluru → Chennai'), findsOneWidget);
    expect(find.text('Priya Sharma'), findsOneWidget);
    expect(find.text('Admit 2 passengers'), findsOneWidget);
  });

  testWidgets('history lists scans and sign-out returns to login', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.byKey(const Key('qr-movie')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-next-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Scan history'));
    await tester.pumpAndSettle();
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.textContaining('Valid · not admitted'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });
}
