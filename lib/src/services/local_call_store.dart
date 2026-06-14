import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lead.dart';

/// Persists calls placed from inside the app to SharedPreferences, so the call
/// log and a lead's history survive even when the backend hasn't ingested a
/// recording yet. Keyed by `local_calls_v1` as a JSON array of [CallLogEntry].
class LocalCallStore {
  static const _key = 'local_calls_v1';

  Future<List<CallLogEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) CallLogEntry.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(CallLogEntry entry) async {
    final all = await loadAll();
    await _persist([entry, ...all]);
  }

  Future<void> _persist(List<CallLogEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }
}

final localCallStoreProvider = Provider<LocalCallStore>((_) => LocalCallStore());

/// Reactive list of locally-recorded calls (newest first).
final localCallsProvider =
    NotifierProvider<LocalCallsController, List<CallLogEntry>>(
  LocalCallsController.new,
);

class LocalCallsController extends Notifier<List<CallLogEntry>> {
  @override
  List<CallLogEntry> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    state = await ref.read(localCallStoreProvider).loadAll();
  }

  /// Records a call that was just placed for [entry]'s lead.
  Future<void> record(CallLogEntry entry) async {
    await ref.read(localCallStoreProvider).add(entry);
    await _load();
  }
}
