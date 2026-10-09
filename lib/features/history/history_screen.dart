import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../core/theme/scanner_theme.dart';
import 'scan_history.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<ScanHistoryCubit>();
    final records = history.state;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan history'),
        actions: [
          if (records.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      body: records.isEmpty
          ? const Center(
              child: Text(
                'No scans yet',
                style: TextStyle(color: ScannerColors.textMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _Summary(
                  admitted: history.admittedToday(now),
                  scanned: records
                      .where((r) => DateUtils.isSameDay(r.at, now))
                      .length,
                ),
                const SizedBox(height: 12),
                for (final r in records) _RecordTile(record: r),
              ],
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final history = context.read<ScanHistoryCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear scan history?'),
        content: const Text(
          'This only clears the list on this device. Check-ins stay recorded on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) history.clear();
  }
}

class _Summary extends StatelessWidget {
  final int admitted;
  final int scanned;
  const _Summary({required this.admitted, required this.scanned});

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int value, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ScannerColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ScannerColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(label, style: const TextStyle(color: ScannerColors.textMuted)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        stat('Admitted today', admitted, ScannerColors.valid),
        const SizedBox(width: 12),
        stat('Scans today', scanned, Colors.white),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  final ScanRecord record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (record.outcome) {
      ScanOutcome.admitted => (
        ScannerColors.valid,
        Icons.verified_rounded,
        'Admitted',
      ),
      ScanOutcome.valid => (
        ScannerColors.valid,
        Icons.check_circle_outline_rounded,
        'Valid · not admitted',
      ),
      ScanOutcome.warning => (
        ScannerColors.warning,
        Icons.warning_amber_rounded,
        'Warning · not admitted',
      ),
      ScanOutcome.rejected => (
        ScannerColors.invalid,
        Icons.cancel_rounded,
        'Rejected',
      ),
      ScanOutcome.notFound => (
        ScannerColors.invalid,
        Icons.search_off_rounded,
        'Not found',
      ),
      ScanOutcome.error => (
        ScannerColors.textMuted,
        Icons.error_outline_rounded,
        'Error',
      ),
    };
    final typeIcon = switch (record.type) {
      'movie' => Icons.movie_outlined,
      'bus' => Icons.directions_bus_outlined,
      _ => Icons.qr_code_2_rounded,
    };

    return Card(
      color: ScannerColors.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: ScannerColors.outline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: color, size: 30),
        title: Text(
          record.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(typeIcon, size: 14, color: ScannerColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${record.reference} · ${record.outcome == ScanOutcome.rejected ? record.detail : label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: Text(
          DateFormat(
            DateUtils.isSameDay(record.at, DateTime.now()) ? 'h:mm a' : 'd MMM',
          ).format(record.at),
          style: const TextStyle(color: ScannerColors.textMuted),
        ),
      ),
    );
  }
}
