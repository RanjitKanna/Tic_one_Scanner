import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/scanner_theme.dart';
import 'features/auth/auth_cubit.dart';
import 'features/auth/login_screen.dart';
import 'features/history/scan_history.dart';
import 'features/scan/scan_cubit.dart';
import 'features/scan/scanner_screen.dart';
import 'features/scan/ticket_repository.dart';

class ScannerApp extends StatelessWidget {
  final AuthCubit authCubit;
  final ScanHistoryCubit historyCubit;
  final TicketRepository tickets;
  final CameraBuilder? cameraBuilder;

  const ScannerApp({
    super.key,
    required this.authCubit,
    required this.historyCubit,
    required this.tickets,
    this.cameraBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: authCubit),
        BlocProvider.value(value: historyCubit),
      ],
      child: MaterialApp(
        title: 'TicOne Scanner',
        debugShowCheckedModeBanner: false,
        theme: buildScannerTheme(),
        home: BlocBuilder<AuthCubit, AuthState>(
          buildWhen: (prev, next) =>
              (prev.status == AuthStatus.signedIn) !=
                  (next.status == AuthStatus.signedIn) ||
              (prev.status == AuthStatus.unknown) !=
                  (next.status == AuthStatus.unknown),
          builder: (context, state) => switch (state.status) {
            AuthStatus.unknown => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            AuthStatus.signedIn => BlocProvider(
              create: (_) => ScanCubit(tickets, historyCubit),
              child: ScannerScreen(cameraBuilder: cameraBuilder),
            ),
            _ => const LoginScreen(),
          },
        ),
      ),
    );
  }
}
