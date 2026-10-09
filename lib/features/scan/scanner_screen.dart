import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/scanner_theme.dart';
import '../auth/auth_cubit.dart';
import '../history/history_screen.dart';
import '../history/scan_history.dart';
import 'scan_cubit.dart';
import 'scan_result_panel.dart';
import 'ticket_verdict.dart';

/// Builds the live camera view; replaced in widget tests.
typedef CameraBuilder =
    Widget Function(
      BuildContext context,
      void Function(String? rawValue) onDetected,
    );

class ScannerScreen extends StatelessWidget {
  final CameraBuilder? cameraBuilder;

  const ScannerScreen({super.key, this.cameraBuilder});

  @override
  Widget build(BuildContext context) {
    final scan = context.read<ScanCubit>();

    return BlocConsumer<ScanCubit, ScanState>(
      listenWhen: (prev, next) => prev.phase != next.phase,
      listener: (context, state) => _haptics(state),
      builder: (context, state) {
        final showPanel = state.phase != ScanPhase.ready;
        return PopScope(
          // Back from a result returns to the camera instead of leaving.
          canPop: !showPanel,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) scan.reset();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                (cameraBuilder ?? _liveCamera)(context, scan.onScanned),
                // Camera controls are hidden (and out of the semantics tree)
                // while a result covers the screen.
                if (!showPanel) ...[
                  const _Viewfinder(),
                  const _TopBar(),
                  _BottomBar(onEnterCode: () => _enterCode(context)),
                ],
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: showPanel
                      ? ScanResultPanel(
                          key: ValueKey('${state.phase}-${state.reference}'),
                          state: state,
                          onAdmit: scan.admit,
                          onNext: scan.reset,
                          onRetry: scan.retry,
                          onEnterCode: () => _enterCode(context),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _liveCamera(
    BuildContext context,
    void Function(String?) onDetected,
  ) => _LiveCamera(onDetected: onDetected);

  void _haptics(ScanState state) {
    switch (state.phase) {
      case ScanPhase.admitted:
        HapticFeedback.mediumImpact();
      case ScanPhase.failed:
        HapticFeedback.heavyImpact();
      case ScanPhase.result:
        state.verdict?.level == VerdictLevel.valid
            ? HapticFeedback.lightImpact()
            : HapticFeedback.heavyImpact();
      default:
        break;
    }
  }

  Future<void> _enterCode(BuildContext context) async {
    final scan = context.read<ScanCubit>();
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ScannerColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ManualEntrySheet(),
    );
    if (code == null || code.trim().isEmpty) return;
    scan.reset();
    await scan.onCodeEntered(code);
  }
}

class _LiveCamera extends StatefulWidget {
  final void Function(String?) onDetected;
  const _LiveCamera({required this.onDetected});

  @override
  State<_LiveCamera> createState() => _LiveCameraState();
}

class _LiveCameraState extends State<_LiveCamera> with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera while the app is in the background.
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.start().catchError((_) {}));
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_controller.stop().catchError((_) {}));
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              if (barcode.rawValue != null) {
                widget.onDetected(barcode.rawValue);
                return;
              }
            }
          },
          errorBuilder: (context, error) => _CameraError(error: error),
        ),
        Positioned(
          right: 16,
          bottom: 150,
          child: Column(
            children: [
              ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, value, _) => _RoundButton(
                  tooltip: 'Torch',
                  icon: value.torchState == TorchState.on
                      ? Icons.flashlight_on_rounded
                      : Icons.flashlight_off_rounded,
                  onPressed: value.torchState == TorchState.unavailable
                      ? null
                      : () => _controller.toggleTorch(),
                ),
              ),
              const SizedBox(height: 12),
              _RoundButton(
                tooltip: 'Switch camera',
                icon: Icons.cameraswitch_rounded,
                onPressed: () => _controller.switchCamera(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  const _CameraError({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: ScannerColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: ScannerColors.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                denied ? 'Camera access is off' : 'Camera unavailable',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Allow camera access for TicOne Scanner in Settings, or enter booking codes by hand below.'
                    : 'The camera could not start. You can still enter booking codes by hand below.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ScannerColors.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dimmed overlay with a square cut-out to aim at the QR.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = (constraints.maxWidth * 0.7).clamp(200.0, 320.0);
          return CustomPaint(
            painter: _ViewfinderPainter(side: side),
            child: Align(
              alignment: const Alignment(0, 0.62),
              child: const Text(
                'Point the camera at the ticket QR code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  final double side;
  _ViewfinderPainter({required this.side});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset(0, -size.height * 0.04));
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: side, height: side),
      const Radius.circular(24),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Corner brackets.
    final paint = Paint()
      ..color = ScannerColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const len = 34.0;
    final r = hole.outerRect;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy * len)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx + dx * len, corner.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.side != side;
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final staff = context.select((AuthCubit c) => c.state.session?.name ?? '');
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scan ticket',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (staff.isNotEmpty)
                      Text(
                        staff,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              _RoundButton(
                tooltip: 'Scan history',
                icon: Icons.history_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HistoryScreen(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _RoundButton(
                tooltip: 'Sign out',
                icon: Icons.logout_rounded,
                onPressed: () => _confirmSignOut(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need the admin password to scan tickets again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await auth.logout();
  }
}

class _BottomBar extends StatelessWidget {
  final VoidCallback onEnterCode;
  const _BottomBar({required this.onEnterCode});

  @override
  Widget build(BuildContext context) {
    final admitted = context.select(
      (ScanHistoryCubit c) => c.admittedToday(DateTime.now()),
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Admitted today on this device: $admitted',
                key: const Key('admitted-today'),
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('enter-code-button'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: onEnterCode,
                icon: const Icon(Icons.keyboard_rounded),
                label: const Text('Enter code or PNR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black.withValues(alpha: 0.25),
        minimumSize: const Size(48, 48),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet();

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter ticket code',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Booking code (TIC-2026-123456, TIC-BUS-2026-123456) or bus PNR.',
            style: TextStyle(color: ScannerColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('manual-code-field'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            decoration: const InputDecoration(
              hintText: 'TIC-2026-…  or  PNR…',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('manual-verify-button'),
            onPressed: _submit,
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }
}
