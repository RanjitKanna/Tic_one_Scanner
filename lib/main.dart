import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_store.dart';
import 'features/auth/auth_cubit.dart';
import 'features/auth/auth_repository.dart';
import 'features/history/scan_history.dart';
import 'features/scan/ticket_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final sessions = SecureSessionStore();
  final api = ApiClient(sessions);
  final authCubit = AuthCubit(AuthRepository(api, sessions));
  api.onSessionExpired = authCubit.sessionExpired;

  final historyCubit = ScanHistoryCubit();
  await Future.wait([authCubit.restore(), historyCubit.load()]);

  runApp(
    ScannerApp(
      authCubit: authCubit,
      historyCubit: historyCubit,
      tickets: TicketRepository(api),
    ),
  );
}
