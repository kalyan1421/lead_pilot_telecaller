import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lead.dart';

/// Persists locally-scheduled follow-up calls to SharedPreferences.
/// Keyed by `follow_ups_v1` as a JSON array.
class LocalFollowUpStore {
  static const _key = 'follow_ups_v1';

  Future<List<FollowUpTask>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>) FollowUpTask.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(FollowUpTask task) async {
    final all = await loadAll();
    await _persist([...all, task]);
  }

  Future<void> markDone(String id) async {
    final all = await loadAll();
    await _persist([
      for (final t in all)
        if (t.id == id) t.copyWith(status: FollowUpStatus.done, dueToday: false)
        else t,
    ]);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    await _persist(all.where((t) => t.id != id).toList());
  }

  Future<void> _persist(List<FollowUpTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final t in tasks) t.toJson()]),
    );
  }
}

final localFollowUpStoreProvider = Provider<LocalFollowUpStore>(
  (_) => LocalFollowUpStore(),
);
