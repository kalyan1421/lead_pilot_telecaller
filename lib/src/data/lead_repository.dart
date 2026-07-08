import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/api/api_endpoints.dart';
import '../core/api/api_exception.dart';
import '../models/lead.dart';

/// Talks to the FastAPI "AI layer" backend (`voicesummary-main`) and maps its
/// snake_case JSON into the app's domain models.
///
/// The backend keys everything by `contact_key` — today a name-slug derived
/// from the call_id (the dataset has no phone field). In this app a [Lead.id]
/// IS that contact_key, so detail / memory lookups round-trip cleanly.
class LeadRepository {
  const LeadRepository(this._client, {String? Function()? getToken}) : _getToken = getToken;

  final ApiClient _client;

  /// Returns the current session's JWT, or null when logged out. Needed here
  /// (in addition to [_client]) because [uploadRecording] builds its own
  /// `http.MultipartRequest` instead of going through [ApiClient] — without
  /// this, the upload carries no Authorization header, so the backend can't
  /// stamp org_id/telecaller_id on the created call and it never shows up in
  /// this telecaller's `/api/inbox` (which is org-scoped).
  final String? Function()? _getToken;

  // ── Inbox ──────────────────────────────────────────────────────────────

  /// `GET /api/inbox` → one thin [Lead] card per contact (list-level fields).
  /// Rich fields (memory, history, script, objections) arrive via [leadDetail].
  Future<List<Lead>> fetchInbox({String? bucket}) async {
    final body = await _client.get(
      ApiEndpoints.inbox,
      query: bucket == null ? null : {'bucket': bucket},
    );
    final cards = (body is Map ? body['leads'] : null);
    if (cards is! List) return const [];
    return cards
        .whereType<Map<String, dynamic>>()
        .map(_leadFromCard)
        .toList(growable: false);
  }

  /// `GET /api/inbox` header block (totals + bucket counts) for the home header.
  Future<InboxHeader> fetchInboxHeader() async {
    final body = await _client.get(ApiEndpoints.inbox);
    final header = (body is Map ? body['header'] : null);
    return InboxHeader.fromJson(header is Map<String, dynamic> ? header : const {});
  }

  // ── Lead detail (card + memory bubble + call history) ───────────────────

  /// `GET /api/leads/{contact_key}` → a fully-enriched [Lead].
  Future<Lead> leadDetail(String contactKey) async {
    final body = await _client.get(ApiEndpoints.leadDetail(contactKey));
    if (body is! Map<String, dynamic>) {
      throw ApiException('Unexpected lead-detail payload for $contactKey');
    }
    return _leadFromDetail(body);
  }

  /// Same as [leadDetail] but also returns the authoritative server
  /// `pipeline_stage`, so the caller can read back a stage moved on the web
  /// dashboard / another device. Separate method so the plain [leadDetail]
  /// callers stay untouched.
  Future<({Lead lead, String? stage})> leadDetailWithStage(String contactKey) async {
    final body = await _client.get(ApiEndpoints.leadDetail(contactKey));
    if (body is! Map<String, dynamic>) {
      throw ApiException('Unexpected lead-detail payload for $contactKey');
    }
    final stage = body['pipeline_stage'];
    return (lead: _leadFromDetail(body), stage: stage is String ? stage : null);
  }

  // ── Outbound lead creation + dedup ──────────────────────────────────────

  /// `GET /api/leads/dedupe?phone=` → true if this number is already a lead.
  Future<DedupeResult> dedupe(String phone) async {
    final body = await _client.get(
      ApiEndpoints.dedupeLead,
      query: {'phone': phone},
    );
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    return DedupeResult(
      duplicate: map['duplicate'] == true,
      contactKey: map['contact_key'] as String?,
      name: map['name'] as String?,
    );
  }

  /// `POST /api/leads` (Save Lead). Returns the created/existing contact_key.
  Future<String> createLead(OutboundLeadDraft draft) async {
    final body = await _client.post(ApiEndpoints.createLead, body: draft.toJson());
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    return (map['contact_key'] ?? '').toString();
  }

  // ── Pipeline stage ──────────────────────────────────────────────────────

  /// `PATCH /api/leads/by-contact/{contact_key}/stage` — moves a lead's kanban
  /// stage, so a stage change made in this app becomes visible on the
  /// founder's web Kanban board. `dealValue`/`listPrice`/`discountPct` are
  /// only meaningful (and only sent) when [stage] is Closed Won.
  Future<void> updateLeadStage(
    String contactKey,
    LeadStage stage, {
    int? dealValue,
    int? listPrice,
    double? discountPct,
  }) async {
    await _client.patch(
      ApiEndpoints.leadStage(contactKey),
      body: {
        'stage': stage.value,
        if (dealValue != null) 'deal_value': dealValue,
        if (listPrice != null) 'list_price': listPrice,
        if (discountPct != null) 'discount_pct': discountPct,
      },
    );
  }

  // ── Telecaller score ────────────────────────────────────────────────────

  /// `GET /api/telecaller/score?window_days=` for the Profile / Score tab.
  Future<TelecallerScore> telecallerScore({int windowDays = 7}) async {
    final body = await _client.get(
      ApiEndpoints.telecallerScore,
      query: {'window_days': windowDays},
    );
    return TelecallerScore.fromJson(
      body is Map<String, dynamic> ? body : const {},
    );
  }

  // ── Per-call analysis + processing stepper ──────────────────────────────

  /// `GET /api/calls/{id}/lead-analysis` (post-call Summary + Score tabs).
  Future<Map<String, dynamic>> leadAnalysis(String callId) async {
    final body = await _client.get(ApiEndpoints.leadAnalysis(callId));
    return body is Map<String, dynamic> ? body : const {};
  }

  /// `PATCH /api/calls/{id}/lead-analysis` — telecaller correction to key
  /// points. Does not re-run AI analysis or touch any other analysis field.
  Future<void> updateKeyPoints(String callId, List<String> keyPoints) async {
    await _client.patch(
      ApiEndpoints.leadAnalysis(callId),
      body: {'key_points': keyPoints},
    );
  }

  /// `GET /api/calls/{id}/transcript` → diarized turns (speaker + text).
  Future<TranscriptResult> transcript(String callId) async {
    final body = await _client.get(ApiEndpoints.transcript(callId));
    final t = (body is Map ? body['transcript'] : null);
    final turns = (t is Map ? t['turns'] : null);
    return TranscriptResult(
      language: (t is Map ? t['language'] : null)?.toString(),
      turns: [
        if (turns is List)
          for (final raw in turns.whereType<Map>()) _turnFromJson(raw),
      ],
    );
  }

  /// `GET /api/calls/{id}/transcript/translate?target=en` ("View English" toggle).
  Future<List<TranscriptTurn>> translatedTranscript(String callId) async {
    final body = await _client.get(ApiEndpoints.translate(callId));
    final turns = (body is Map ? body['turns'] : null);
    return [
      if (turns is List)
        for (final raw in turns.whereType<Map>()) _translatedTurnFromJson(raw),
    ];
  }

  static TranscriptTurn _turnFromJson(Map raw) => TranscriptTurn(
    speaker: (raw['role'] ?? raw['speaker'] ?? '').toString(),
    text: (raw['content'] ?? raw['text'] ?? '').toString(),
    timestamp: raw['timestamp']?.toString(),
  );

  /// Same as [_turnFromJson] but prefers the translated text — the
  /// `/transcript/translate` response keeps `content` as the original-
  /// language text and puts the English translation in `content_translated`.
  static TranscriptTurn _translatedTurnFromJson(Map raw) => TranscriptTurn(
    speaker: (raw['role'] ?? raw['speaker'] ?? '').toString(),
    text: (raw['content_translated'] ?? raw['content'] ?? raw['text'] ?? '')
        .toString(),
    timestamp: raw['timestamp']?.toString(),
  );

  /// `GET /api/calls/{id}/score` — the consolidated Score-tab payload (hero
  /// score, 4 rings, 5-dimension breakdown, sentiment timeline).
  Future<Map<String, dynamic>> callScore(String callId) async {
    final body = await _client.get(ApiEndpoints.callScore(callId));
    return body is Map<String, dynamic> ? body : const {};
  }

  /// `POST /api/memory/{contact_key}/rebuild` — recompute this contact's
  /// memory bubble from all of their calls. Returns the fresh bubble map.
  Future<Map<String, dynamic>> rebuildMemory(String contactKey) async {
    final body = await _client.post(ApiEndpoints.rebuildMemory(contactKey));
    return body is Map<String, dynamic> ? body : const {};
  }

  /// `GET /api/calls/{id}/processing-status` (Upload→Transcribe→Analyse→Done).
  Future<ProcessingStatus> processingStatus(String callId) async {
    final body = await _client.get(ApiEndpoints.processingStatus(callId));
    return ProcessingStatus.fromJson(
      body is Map<String, dynamic> ? body : const {},
    );
  }

  /// Poll [processingStatus] until done or failed (or timeout). Used by the
  /// "Analysing call…" screen after an upload.
  Future<ProcessingStatus> awaitProcessing(
    String callId, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 5),
    void Function(ProcessingStatus)? onTick,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final status = await processingStatus(callId);
      onTick?.call(status);
      if (status.failed || status.currentStage == 'done' || status.percent >= 100) {
        return status;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw ApiException('Processing timed out for call $callId');
      }
      await Future<void>.delayed(interval);
    }
  }

  // ── Outbound recording upload (multipart) ───────────────────────────────

  /// `POST /api/calls/upload` (multipart). The [ApiClient] interface is JSON
  /// only, so the multipart request is built here directly. Returns the
  /// `call_id` the caller then polls with [awaitProcessing].
  Future<String> uploadRecording(
    File audio, {
    String? name,
    String? phone,
    String? source,
    DateTime? callDate,
    String? contactKey,
  }) async {
    final uri = ApiConfig.uri(ApiEndpoints.uploadRecording);
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          audio.path,
          contentType: _audioContentType(audio.path),
        ),
      );
    if (name != null) request.fields['name'] = name;
    if (phone != null) request.fields['phone'] = phone;
    if (source != null) request.fields['source'] = source;
    if (callDate != null) request.fields['call_date'] = callDate.toIso8601String();
    if (contactKey != null) request.fields['contact_key_override'] = contactKey;
    final token = _getToken?.call();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    try {
      final streamed = await request.send().timeout(ApiConfig.timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'Upload failed: ${response.body}',
          statusCode: response.statusCode,
        );
      }
      final map = jsonDecode(response.body);
      return (map is Map && map['call_id'] != null) ? map['call_id'].toString() : '';
    } on SocketException catch (e) {
      throw ApiException('Network error during upload', cause: e);
    }
  }

  /// Explicit content-type by extension so the backend/storage layer doesn't
  /// have to guess from bytes — extensions like `.opus` (WhatsApp voice
  /// notes) otherwise fall back to `application/octet-stream`, which some
  /// transcription pipelines reject.
  static MediaType? _audioContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp3':
      case 'mpeg':
        return MediaType('audio', 'mpeg');
      case 'wav':
        return MediaType('audio', 'wav');
      case 'm4a':
        return MediaType('audio', 'mp4');
      case 'mp4':
        return MediaType('video', 'mp4');
      case 'ogg':
        return MediaType('audio', 'ogg');
      case 'opus':
        return MediaType('audio', 'opus');
      case 'aac':
        return MediaType('audio', 'aac');
      default:
        return null; // let http fall back to its own sniffing
    }
  }

  // ── JSON → model adapters ───────────────────────────────────────────────

  /// Inbox card → thin [Lead]. Card shape:
  /// `{contact_key, name, lead_score, intent_bucket, verdict, tags, total_calls}`
  Lead _leadFromCard(Map<String, dynamic> j) {
    final score = _toInt(j['lead_score']);
    return Lead(
      id: (j['contact_key'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      score: score,
      temperature: _temperature(j['verdict']),
      source: _source(j['source'], j['tags']),
      intent: _intentLabel(j['intent_bucket']),
      lastContact: _parseTs(j['last_call_at']) ?? DateTime.now(),
      totalCalls: _toInt(j['total_calls']),
      averageScore: score,
      memory: const [],
      script: const AiScript(
        generatedAgo: '',
        openingLine: '',
        keyPoints: [],
        steps: [],
      ),
      objections: const [],
      checklist: const [],
      history: const [],
      propertyInterest: null,
    );
  }

  /// `GET /api/leads/{contact_key}` → fully-enriched [Lead].
  /// Response = inbox card fields + `phone, reason, status, memory{…}, calls[]`.
  Lead _leadFromDetail(Map<String, dynamic> j) {
    final memory = j['memory'] is Map<String, dynamic>
        ? j['memory'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final facts = memory['facts'];
    final openObjections = memory['open_objections'];
    final calls = j['calls'];
    final score = _toInt(j['lead_score']);

    final factInsights = <MemoryInsight>[
      if (facts is List)
        for (final f in facts.whereType<Map<String, dynamic>>())
          MemoryInsight(
            text: (f['text'] ?? '').toString(),
            callLabel: f['call_index'] != null ? 'Call #${f['call_index']}' : '',
            colorKey: (f['category'] ?? '').toString(),
          ),
    ];

    final objections = <Objection>[
      if (openObjections is List)
        for (final o in openObjections)
          if (o != null) Objection(question: o.toString(), response: ''),
    ];

    final contactKey = (j['contact_key'] ?? '').toString();

    final history = <CallRecord>[
      if (calls is List)
        for (final c in calls.whereType<Map<String, dynamic>>())
          CallRecord(
            title: _callTitle(c),
            duration: Duration.zero, // backend doesn't store call duration yet
            score: _toInt(c['score'] ?? c['bant_score']),
            calledAt: _parseTs(c['timestamp']),
            leadId: contactKey,
            callId: (c['call_id'] ?? '').toString().isEmpty
                ? null
                : c['call_id'].toString(),
          ),
    ];

    final strategy = (memory['next_call_strategy'] ?? '').toString();
    final headline = (memory['headline'] ?? '').toString();

    return Lead(
      id: contactKey,
      name: (j['name'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      score: score,
      temperature: _temperature(j['verdict'] ?? memory['running_verdict']),
      source: _source(j['source'], j['tags']),
      intent: _intentLabel(j['intent_bucket']),
      lastContact: _parseTs(memory['updated_at']) ?? DateTime.now(),
      totalCalls: _toInt(j['total_calls']),
      averageScore: score,
      memory: factInsights,
      script: AiScript(
        generatedAgo: '',
        openingLine: strategy,
        keyPoints: [
          for (final f in factInsights.take(4)) f.text,
        ],
        steps: const [],
      ),
      objections: objections,
      checklist: const [],
      history: history,
      propertyInterest: headline.isEmpty ? null : headline,
    );
  }

  static String _callTitle(Map<String, dynamic> c) {
    final verdict = c['lead_verdict'];
    final ts = _parseTs(c['timestamp']);
    if (ts != null) {
      final d = ts.toLocal();
      final date = '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}';
      return verdict != null ? '$date · $verdict' : 'Call $date';
    }
    return verdict?.toString() ?? 'Call';
  }

  static LeadTemperature _temperature(Object? verdict) {
    switch ((verdict ?? '').toString().toLowerCase()) {
      case 'hot':
        return LeadTemperature.hot;
      case 'warm':
        return LeadTemperature.warm;
      default:
        return LeadTemperature.cold; // cold / junk / null
    }
  }

  static String _intentLabel(Object? bucket) {
    switch ((bucket ?? '').toString()) {
      case 'high_intent':
        return 'High Intent';
      case 'follow_up':
        return 'Follow-up';
      case 'cold':
        return 'Cold';
      case 'new':
        return 'New Lead';
      default:
        return '';
    }
  }

  static LeadSource _source(Object? source, Object? tags) {
    if (source != null && source.toString().isNotEmpty) {
      return LeadSourceX.fromValue(source.toString().toLowerCase());
    }
    // Fall back to a source-like tag if present (e.g. "GOOGLE", "META").
    if (tags is List) {
      for (final t in tags) {
        final v = t.toString().toLowerCase();
        final match = LeadSource.values.where((s) => s.name == v);
        if (match.isNotEmpty) return match.first;
      }
    }
    return LeadSource.organic;
  }

  static int _toInt(Object? v) => v is num ? v.round() : 0;

  static DateTime? _parseTs(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;
}

// ── Lightweight value types for non-Lead responses ────────────────────────

class InboxHeader {
  const InboxHeader({
    required this.totalLeads,
    required this.avgScore,
    required this.buckets,
  });

  final int totalLeads;
  final int avgScore;
  final Map<String, int> buckets; // {high_intent, follow_up, cold, ...}

  factory InboxHeader.fromJson(Map<String, dynamic> j) {
    final raw = j['buckets'];
    return InboxHeader(
      totalLeads: j['total_leads'] is num ? (j['total_leads'] as num).round() : 0,
      avgScore: j['avg_score'] is num ? (j['avg_score'] as num).round() : 0,
      buckets: {
        if (raw is Map)
          for (final e in raw.entries)
            e.key.toString(): e.value is num ? (e.value as num).round() : 0,
      },
    );
  }
}

class DedupeResult {
  const DedupeResult({required this.duplicate, this.contactKey, this.name});

  final bool duplicate;
  final String? contactKey;
  final String? name;
}

/// One diarized turn of a call transcript.
class TranscriptTurn {
  const TranscriptTurn({required this.speaker, required this.text, this.timestamp});

  final String speaker; // AGENT | USER (telecaller vs lead)
  final String text;
  /// Elapsed time into the call as `MM:SS`, if the backend provided one.
  final String? timestamp;
}

/// `GET /api/calls/{id}/transcript` response: turns + the detected source
/// language (e.g. `"hi"`, `"te"`) used to drive the "View English" toggle.
class TranscriptResult {
  const TranscriptResult({required this.turns, this.language});

  final List<TranscriptTurn> turns;
  final String? language;
}

class TelecallerScore {
  const TelecallerScore({
    required this.score,
    required this.trend,
    required this.trendDirection,
    required this.calls,
    required this.avgLeadScore,
    required this.hotLeads,
    required this.windowDays,
  });

  final int score;
  final int? trend; // null until a prior window exists
  final String trendDirection; // up / down / flat
  final int calls;
  final int avgLeadScore;
  final int hotLeads;
  final int windowDays;

  factory TelecallerScore.fromJson(Map<String, dynamic> j) {
    int toInt(Object? v) => v is num ? v.round() : 0;
    return TelecallerScore(
      score: toInt(j['telecaller_score']),
      trend: j['trend'] is num ? (j['trend'] as num).round() : null,
      trendDirection: (j['trend_direction'] ?? 'flat').toString(),
      calls: toInt(j['calls']),
      avgLeadScore: toInt(j['avg_lead_score']),
      hotLeads: toInt(j['hot_leads']),
      windowDays: toInt(j['window_days']),
    );
  }
}

class ProcessingStage {
  const ProcessingStage({required this.key, required this.label, required this.status});

  final String key; // upload | transcribe | analyse | done
  final String label;
  final String status; // done | active | pending | failed

  factory ProcessingStage.fromJson(Map<String, dynamic> j) => ProcessingStage(
    key: (j['key'] ?? '').toString(),
    label: (j['label'] ?? '').toString(),
    status: (j['status'] ?? 'pending').toString(),
  );
}

class ProcessingStatus {
  const ProcessingStatus({
    required this.callId,
    required this.currentStage,
    required this.percent,
    required this.failed,
    required this.error,
    required this.stages,
  });

  final String callId;
  final String currentStage;
  final int percent;
  final bool failed;
  final String? error;
  final List<ProcessingStage> stages;

  factory ProcessingStatus.fromJson(Map<String, dynamic> j) {
    final raw = j['stages'];
    return ProcessingStatus(
      callId: (j['call_id'] ?? '').toString(),
      currentStage: (j['current_stage'] ?? '').toString(),
      percent: j['percent'] is num ? (j['percent'] as num).round() : 0,
      failed: j['failed'] == true,
      error: j['error']?.toString(),
      stages: [
        if (raw is List)
          for (final s in raw.whereType<Map<String, dynamic>>())
            ProcessingStage.fromJson(s),
      ],
    );
  }
}
