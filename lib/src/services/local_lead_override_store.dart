import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lead.dart';

/// A locally-edited override of a lead's editable fields. Applied on top of the
/// backend/mock lead so manual edits persist across restarts and reflect
/// everywhere the lead is shown. Null fields leave the original value intact.
class LeadOverride {
  const LeadOverride({
    this.name,
    this.phone,
    this.intent,
    this.source,
    this.temperature,
  });

  final String? name;
  final String? phone;
  final String? intent;
  final LeadSource? source;
  final LeadTemperature? temperature;

  factory LeadOverride.fromJson(Map<String, dynamic> j) => LeadOverride(
        name: j['name'] as String?,
        phone: j['phone'] as String?,
        intent: j['intent'] as String?,
        source: j['source'] != null
            ? LeadSourceX.fromValue(j['source'] as String?)
            : null,
        temperature: j['temperature'] != null
            ? LeadTemperatureX.fromValue(j['temperature'] as String?)
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (intent != null) 'intent': intent,
        if (source != null) 'source': source!.value,
        if (temperature != null) 'temperature': temperature!.value,
      };

  /// Returns a copy of [lead] with this override's non-null fields applied.
  Lead applyTo(Lead lead) => Lead(
        id: lead.id,
        name: name ?? lead.name,
        phone: phone ?? lead.phone,
        score: lead.score,
        temperature: temperature ?? lead.temperature,
        source: source ?? lead.source,
        intent: intent ?? lead.intent,
        lastContact: lead.lastContact,
        totalCalls: lead.totalCalls,
        averageScore: lead.averageScore,
        memory: lead.memory,
        script: lead.script,
        objections: lead.objections,
        checklist: lead.checklist,
        history: lead.history,
        propertyInterest: lead.propertyInterest,
        nextStep: lead.nextStep,
        pendingCommitments: lead.pendingCommitments,
      );
}

class LocalLeadOverrideStore {
  static const _key = 'lead_overrides_v1';

  Future<Map<String, LeadOverride>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value is Map<String, dynamic>)
            e.key: LeadOverride.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> put(String leadId, LeadOverride override) async {
    final all = {...await loadAll(), leadId: override};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
    );
  }
}

final localLeadOverrideStoreProvider =
    Provider<LocalLeadOverrideStore>((_) => LocalLeadOverrideStore());
