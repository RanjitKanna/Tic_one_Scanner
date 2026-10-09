import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScanOutcome { admitted, valid, warning, rejected, notFound, error }

class ScanRecord extends Equatable {
  final String reference;
  final String title;

  /// `movie`, `bus` or null when the ticket was never resolved.
  final String? type;
  final ScanOutcome outcome;
  final String detail;
  final DateTime at;

  const ScanRecord({
    required this.reference,
    required this.title,
    required this.type,
    required this.outcome,
    required this.detail,
    required this.at,
  });

  ScanRecord copyWith({ScanOutcome? outcome, String? detail}) => ScanRecord(
    reference: reference,
    title: title,
    type: type,
    outcome: outcome ?? this.outcome,
    detail: detail ?? this.detail,
    at: at,
  );

  Map<String, dynamic> toJson() => {
    'reference': reference,
    'title': title,
    'type': type,
    'outcome': outcome.name,
    'detail': detail,
    'at': at.toIso8601String(),
  };

  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
    reference: json['reference'] as String,
    title: json['title'] as String? ?? '',
    type: json['type'] as String?,
    outcome: ScanOutcome.values.firstWhere(
      (o) => o.name == json['outcome'],
      orElse: () => ScanOutcome.error,
    ),
    detail: json['detail'] as String? ?? '',
    at: DateTime.parse(json['at'] as String),
  );

  @override
  List<Object?> get props => [reference, title, type, outcome, detail, at];
}

/// Recent scans on this device, newest first.
class ScanHistoryCubit extends Cubit<List<ScanRecord>> {
  static const _key = 'scan_history';
  static const maxRecords = 200;

  ScanHistoryCubit() : super(const []);

  int admittedToday(DateTime now) => state
      .where(
        (r) =>
            r.outcome == ScanOutcome.admitted &&
            r.at.year == now.year &&
            r.at.month == now.month &&
            r.at.day == now.day,
      )
      .length;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      emit(
        (jsonDecode(raw) as List)
            .map((e) => ScanRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      // Corrupt history is not worth blocking the gate over.
    }
  }

  void add(ScanRecord record) =>
      _save([record, ...state].take(maxRecords).toList());

  /// Updates the latest record for [reference] (e.g. once it is admitted).
  void updateLatest(String reference, ScanOutcome outcome, String detail) {
    final i = state.indexWhere((r) => r.reference == reference);
    if (i < 0) return;
    final next = [...state]
      ..[i] = state[i].copyWith(outcome: outcome, detail: detail);
    _save(next);
  }

  void clear() => _save(const []);

  void _save(List<ScanRecord> records) {
    emit(records);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(
        _key,
        jsonEncode(records.map((r) => r.toJson()).toList()),
      ),
      onError: (_) {},
    );
  }
}
