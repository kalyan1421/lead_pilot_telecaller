import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api/api_config.dart';
import '../core/api/api_endpoints.dart';
import '../core/api/api_exception.dart';
import '../models/call_recording.dart';

/// One diarized speaker turn in a transcript.
class TranscriptEntry {
  const TranscriptEntry({
    required this.speakerId,
    required this.text,
    this.textEn,
    this.start,
    this.end,
  });

  final String speakerId;
  final String text;
  final String? textEn;
  final double? start;
  final double? end;

  factory TranscriptEntry.fromJson(Map<String, dynamic> json) {
    double? toDouble(Object? v) => v is num ? v.toDouble() : null;
    return TranscriptEntry(
      speakerId: (json['speakerId'] ?? '0').toString(),
      text: (json['text'] ?? '').toString(),
      textEn: json['textEn']?.toString(),
      start: toDouble(json['start']),
      end: toDouble(json['end']),
    );
  }
}

/// LLM scores for the call (each 0–100).
class AnalysisScores {
  const AnalysisScores({
    required this.overall,
    required this.telecaller,
    required this.leadQuality,
    required this.sentiment,
  });

  final int overall;
  final int telecaller;
  final int leadQuality;
  final int sentiment;

  factory AnalysisScores.fromJson(Map<String, dynamic> json) {
    int toInt(Object? v) => v is num ? v.round() : 0;
    return AnalysisScores(
      overall: toInt(json['overall']),
      telecaller: toInt(json['telecaller']),
      leadQuality: toInt(json['leadQuality']),
      sentiment: toInt(json['sentiment']),
    );
  }
}

/// One row of the call score breakdown (score out of 20).
class AnalysisBreakdownItem {
  const AnalysisBreakdownItem({
    required this.label,
    required this.score,
    required this.note,
  });

  final String label;
  final int score; // 0–20
  final String note;

  double get progress => (score / 20).clamp(0, 1);
  bool get good => score >= 14; // ≥70%

  factory AnalysisBreakdownItem.fromJson(Map<String, dynamic> json) {
    return AnalysisBreakdownItem(
      label: (json['label'] ?? '').toString(),
      score: json['score'] is num ? (json['score'] as num).round() : 0,
      note: (json['note'] ?? '').toString(),
    );
  }
}

/// A suggested follow-up action.
class AnalysisNextStep {
  const AnalysisNextStep({required this.title, required this.action});

  final String title;
  final String action;

  factory AnalysisNextStep.fromJson(Map<String, dynamic> json) {
    return AnalysisNextStep(
      title: (json['title'] ?? '').toString(),
      action: (json['action'] ?? 'Note').toString(),
    );
  }
}

/// Structured analysis of the call (what the Score & Summary tabs render).
class CallAnalysis {
  const CallAnalysis({
    required this.summary,
    required this.keyPoints,
    required this.nextSteps,
    required this.scores,
    required this.breakdown,
    required this.sentimentNote,
    required this.followUpSuggestion,
  });

  final String summary;
  final List<String> keyPoints;
  final List<AnalysisNextStep> nextSteps;
  final AnalysisScores scores;
  final List<AnalysisBreakdownItem> breakdown;
  final String sentimentNote;
  final String followUpSuggestion;

  factory CallAnalysis.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) f) => [
      if (raw is List)
        for (final e in raw)
          if (e is Map<String, dynamic>) f(e),
    ];
    return CallAnalysis(
      summary: (json['summary'] ?? '').toString(),
      keyPoints: [
        if (json['keyPoints'] is List)
          for (final p in json['keyPoints'] as List)
            if (p != null) p.toString(),
      ],
      nextSteps: list(json['nextSteps'], AnalysisNextStep.fromJson),
      scores: AnalysisScores.fromJson(
        (json['scores'] as Map<String, dynamic>?) ?? const {},
      ),
      breakdown: list(json['breakdown'], AnalysisBreakdownItem.fromJson),
      sentimentNote: (json['sentimentNote'] ?? '').toString(),
      followUpSuggestion: (json['followUpSuggestion'] ?? '').toString(),
    );
  }
}

/// The text + diarization + analysis produced by the backend for a recording.
class CallTranscription {
  const CallTranscription({
    required this.transcript,
    required this.entries,
    this.language,
    this.transcriptEn,
    this.analysis,
  });

  final String transcript;
  final String? transcriptEn;
  final String? language;
  final List<TranscriptEntry> entries;
  final CallAnalysis? analysis;

  factory CallTranscription.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final entries = <TranscriptEntry>[
      if (rawEntries is List)
        for (final e in rawEntries)
          if (e is Map<String, dynamic>) TranscriptEntry.fromJson(e),
    ];
    final rawAnalysis = json['analysis'];
    return CallTranscription(
      transcript: (json['transcript'] ?? '').toString(),
      transcriptEn: json['transcriptEn']?.toString(),
      language: json['languageCode']?.toString(),
      entries: entries,
      analysis: rawAnalysis is Map<String, dynamic>
          ? CallAnalysis.fromJson(rawAnalysis)
          : null,
    );
  }
}

/// Uploads a captured [CallRecording] to the Python backend and waits for
/// the transcribe → analyse pipeline to finish.
///
/// Backend contract (FastAPI, port 8000):
///   * `POST /api/calls/upload` multipart (`file`, `name`) → `{ call_id }`.
///   * poll `GET /api/calls/{id}/processing-status` until `done`/`failed`.
///   * `GET /api/calls/{id}/transcript` + `/lead-analysis` → assemble result.
class TranscriptionService {
  const TranscriptionService();

  static const Duration _pollInterval = Duration(seconds: 3);
  static const Duration _pollTimeout = Duration(minutes: 5);

  /// [onProgress] is called on every poll tick with the backend's current
  /// stage key (e.g. `"transcribe"`, `"analyse"`) and a 0–100 percent value.
  Future<CallTranscription> transcribe({
    required CallRecording recording,
    required String leadId,
    void Function(String stage, int percent)? onProgress,
  }) async {
    onProgress?.call('upload', 5);
    final callId = await _upload(recording: recording, leadId: leadId);
    onProgress?.call('upload', 20);
    await _pollUntilProcessed(callId, onProgress: onProgress);
    return _assemble(callId);
  }

  Future<String> _upload({
    required CallRecording recording,
    required String leadId,
  }) async {
    final file = recording.file;
    if (!file.existsSync()) {
      throw ApiException('Recording file no longer exists: ${recording.path}');
    }

    final uri = ApiConfig.uri(ApiEndpoints.uploadRecording);
    final request = http.MultipartRequest('POST', uri)
      // The backend slugifies `name` into the contact_key it keys analysis +
      // memory by. Passing the lead id keeps this call grouped with the lead.
      ..fields['name'] = leadId
      ..files.add(await http.MultipartFile.fromPath('file', recording.path));

    http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(ApiConfig.timeout);
    } catch (e) {
      throw ApiException('Could not reach the backend for upload.', cause: e);
    }

    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException(
        'Could not start transcription (${streamed.statusCode}).',
        statusCode: streamed.statusCode,
      );
    }

    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final callId = decoded['call_id']?.toString();
      if (callId == null || callId.isEmpty) {
        throw const ApiException('Backend did not return a call_id.');
      }
      return callId;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Unexpected upload response.', cause: e);
    }
  }

  Future<void> _pollUntilProcessed(
    String callId, {
    void Function(String stage, int percent)? onProgress,
  }) async {
    final deadline = DateTime.now().add(_pollTimeout);
    final uri = ApiConfig.uri(ApiEndpoints.processingStatus(callId));

    while (true) {
      await Future<void>.delayed(_pollInterval);

      http.Response res;
      try {
        res = await http
            .get(uri, headers: ApiConfig.defaultHeaders)
            .timeout(ApiConfig.timeout);
      } catch (e) {
        if (DateTime.now().isAfter(deadline)) {
          throw ApiException('Transcription timed out.', cause: e);
        }
        continue; // transient network hiccup — keep polling until the deadline
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(
          'Transcription status check failed (${res.statusCode}).',
          statusCode: res.statusCode,
        );
      }

      final Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (e) {
        throw ApiException('Unexpected status response.', cause: e);
      }

      if (decoded['failed'] == true) {
        throw ApiException(
          decoded['error']?.toString() ?? 'Transcription failed.',
        );
      }
      final stage = decoded['current_stage']?.toString() ?? '';
      final percent =
          decoded['percent'] is num ? (decoded['percent'] as num).round() : 0;

      onProgress?.call(stage, percent);

      if (stage == 'done' || percent >= 100) return;

      if (DateTime.now().isAfter(deadline)) {
        throw const ApiException(
          'Transcription is taking too long. Please try again.',
        );
      }
    }
  }

  /// Fetch transcript + analysis, shape into [CallTranscription].
  ///
  /// Calls two backend endpoints concurrently:
  ///   - `/lead-analysis` → summary, key points, next steps, follow-up script
  ///   - `/score`         → rings with real telecaller value, breakdown notes, trends
  ///
  /// Either can 404 without breaking the other (analysis may not be ready yet).
  Future<CallTranscription> _assemble(String callId) async {
    final tBody = await _getJson(ApiEndpoints.transcript(callId));
    final transcript = tBody['transcript'] is Map<String, dynamic>
        ? tBody['transcript'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final turns = transcript['turns'];

    final entries = <Map<String, dynamic>>[
      if (turns is List)
        for (final t in turns.whereType<Map<String, dynamic>>())
          {
            'speakerId':
                (t['role']?.toString().toUpperCase() == 'AGENT') ? '0' : '1',
            'text': (t['content'] ?? t['text'] ?? '').toString(),
          },
    ];

    final results = await Future.wait([
      _getJsonOrEmpty(ApiEndpoints.leadAnalysis(callId)),
      _getJsonOrEmpty(ApiEndpoints.callScore(callId)),
    ]);
    final la = results[0];
    final scoreData = results[1];

    return CallTranscription.fromJson({
      'transcript': transcript['full_text'] ?? '',
      'languageCode': transcript['language'],
      'entries': entries,
      'analysis': la.isEmpty && scoreData.isEmpty
          ? null
          : _buildAnalysis(la, scoreData),
    });
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final res = await http
        .get(ApiConfig.uri(path), headers: ApiConfig.defaultHeaders)
        .timeout(ApiConfig.timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('GET $path failed (${res.statusCode}).',
          statusCode: res.statusCode);
    }
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  Future<Map<String, dynamic>> _getJsonOrEmpty(String path) async {
    try {
      return await _getJson(path);
    } catch (_) {
      return const {};
    }
  }

  /// Merges `/lead-analysis` (narrative) + `/score` (rings + notes) into the
  /// camelCase shape [CallAnalysis.fromJson] expects.
  ///
  /// `/score` is authoritative for all numeric rings (includes the proper rolling
  /// telecaller score and real breakdown notes). `/lead-analysis` provides the
  /// narrative: summary, key points, next steps, follow-up suggestion. Each is
  /// treated as optional — graceful degradation when one endpoint is unavailable.
  Map<String, dynamic> _buildAnalysis(
    Map<String, dynamic> la,
    Map<String, dynamic> scoreData,
  ) {
    int pct(Object? v) => v is num ? v.round() : 0;

    // Narrative fields from /lead-analysis
    final summary = la['call_summary'] is Map<String, dynamic>
        ? la['call_summary'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final nextAction = la['next_action'] is Map<String, dynamic>
        ? la['next_action'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final debrief = la['agent_debrief'] is Map<String, dynamic>
        ? la['agent_debrief'] as Map<String, dynamic>
        : const <String, dynamic>{};

    // Ring values from /score — includes rolling telecaller (not just this call).
    // Falls back to /lead-analysis debrief if /score was unavailable.
    final rings = scoreData['rings'] is Map<String, dynamic>
        ? scoreData['rings'] as Map<String, dynamic>
        : const <String, dynamic>{};
    int ringVal(String key) {
      final r = rings[key];
      return r is Map ? pct(r['value']) : 0;
    }

    final hasScore = rings.isNotEmpty;

    // Breakdown from /score includes real per-dimension notes from the LLM debrief.
    // Falls back to debrief scores with empty notes when /score is unavailable.
    final rawBreakdown = scoreData['breakdown'];
    final breakdown = rawBreakdown is List
        ? [
            for (final b in rawBreakdown.whereType<Map<String, dynamic>>())
              {
                'label': (b['label'] ?? '').toString(),
                'score': pct(b['score']),
                'note': (b['note'] ?? '').toString(),
              },
          ]
        : [
            {'label': 'Opening', 'score': pct(debrief['opening_score']), 'note': ''},
            {'label': 'Discovery', 'score': pct(debrief['discovery_score']), 'note': ''},
            {'label': 'Pitch', 'score': pct(debrief['pitch_score']), 'note': ''},
            {
              'label': 'Objection Handling',
              'score': pct(debrief['objection_handling_score']),
              'note': '',
            },
            {'label': 'Closing', 'score': pct(debrief['closing_score']), 'note': ''},
          ];

    return {
      'summary': (summary['headline'] ?? la['lead_verdict_reason'] ?? '').toString(),
      'keyPoints': la['key_points'] is List ? la['key_points'] : const [],
      'nextSteps': [
        if (la['next_steps'] is List)
          for (final s in (la['next_steps'] as List).whereType<Map>())
            {
              'title': (s['text'] ?? '').toString(),
              'action': (s['action_label'] ?? 'Note').toString(),
            },
      ],
      'scores': {
        'overall': hasScore ? ringVal('overall') : pct(debrief['total_score']),
        'telecaller': ringVal('telecaller'),
        'leadQuality': hasScore ? ringVal('lead_quality') : pct(la['bant_score']),
        'sentiment': ringVal('sentiment'),
      },
      'breakdown': breakdown,
      'sentimentNote': (summary['overall_tone'] ?? '').toString(),
      'followUpSuggestion':
          (nextAction['follow_up_script'] ?? nextAction['recommended_action'] ?? '')
              .toString(),
    };
  }
}
