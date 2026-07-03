import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../data/lead_repository.dart';
import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'leadpilot_widgets.dart';

enum _UpPhase { idle, uploading, processing, done, error }

/// Bottom sheet for uploading a past call recording to an **existing** lead.
///
/// Opens with [show]; on completion calls `leadsProvider.enrich(leadId)` so
/// the lead detail screen refreshes and shows the new call in history.
class UploadRecordingSheet extends ConsumerStatefulWidget {
  const UploadRecordingSheet._({
    required this.leadId,
    required this.leadName,
  });

  final String leadId;
  final String leadName;

  static Future<void> show(BuildContext context, Lead lead) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => UploadRecordingSheet._(
          leadId: lead.id,
          leadName: lead.name,
        ),
      );

  @override
  ConsumerState<UploadRecordingSheet> createState() =>
      _UploadRecordingSheetState();
}

class _UploadRecordingSheetState
    extends ConsumerState<UploadRecordingSheet> {
  _UpPhase _phase = _UpPhase.idle;
  String? _fileName;
  String _stageLabel = '';
  String? _error;
  List<TranscriptTurn> _turns = const [];
  String? _verdict;
  List<String> _keyPoints = const [];
  DateTime _callDate = DateTime.now();

  bool get _busy =>
      _phase == _UpPhase.uploading || _phase == _UpPhase.processing;

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _callDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _callDate = picked);
  }

  Future<void> _pickAndUpload() async {
    if (_busy) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'ogg', 'mpeg', 'mp4'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() {
      _fileName = picked!.files.single.name;
      _phase = _UpPhase.uploading;
      _stageLabel = 'Uploading…';
      _error = null;
      _turns = const [];
      _verdict = null;
      _keyPoints = const [];
    });

    final repo = ref.read(leadRepositoryProvider);
    try {
      final callId = await repo.uploadRecording(
        File(path),
        name: widget.leadName,
        contactKey: widget.leadId,
        callDate: _callDate,
      );
      if (!mounted) return;
      setState(() {
        _phase = _UpPhase.processing;
        _stageLabel = 'Transcribing…';
      });

      await repo.awaitProcessing(
        callId,
        timeout: const Duration(minutes: 10),
        onTick: (s) {
          if (!mounted) return;
          setState(() => _stageLabel =
              '${_stageWord(s.currentStage)}… ${s.percent}%');
        },
      );

      final turns = (await repo.transcript(callId)).turns;
      final analysis = await repo.leadAnalysis(callId);
      if (!mounted) return;
      setState(() {
        _turns = turns;
        _verdict = analysis['lead_verdict']?.toString();
        _keyPoints = (analysis['key_points'] is List)
            ? (analysis['key_points'] as List)
                .map((e) => e.toString())
                .toList()
            : const [];
        _phase = _UpPhase.done;
        _stageLabel = 'Done';
      });
      ref.read(leadsProvider.notifier).enrich(widget.leadId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpPhase.error;
        _error = e.toString();
      });
    }
  }

  static String _stageWord(String key) => switch (key) {
        'transcribe' => 'Transcribing',
        'analyse' => 'Analysing',
        'done' => 'Done',
        _ => 'Processing',
      };

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      margin: EdgeInsets.only(top: topPad + 20),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Color(0x28111827),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          const AppGap.xs(),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.westar,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload Recording',
                          style: AppText.display20),
                      Text(widget.leadName,
                          style: AppText.body14
                              .copyWith(color: AppColors.schooner)),
                    ],
                  ),
                ),
                if (!_busy)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    color: AppColors.schooner,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // ── Date picker ───────────────────────────────────────────
                GestureDetector(
                  onTap: _busy ? null : _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 13),
                    decoration: BoxDecoration(
                      color: AppColors.pampas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.westar),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 15, color: AppColors.schooner),
                        const AppGap.sm(axis: Axis.horizontal),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Recording Date',
                                  style: AppText.label11),
                              Text(_fmtDate(_callDate),
                                  style: AppText.body14),
                            ],
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down,
                            size: 16, color: AppColors.schooner),
                      ],
                    ),
                  ),
                ),
                const AppGap.md(),
                // ── Dropzone ──────────────────────────────────────────────
                _Dropzone(
                  phase: _phase,
                  fileName: _fileName,
                  stageLabel: _stageLabel,
                  onTap: _busy ? null : _pickAndUpload,
                ),
                // ── Transcript preview ────────────────────────────────────
                if (_phase == _UpPhase.done) ...[
                  const AppGap.md(),
                  _TranscriptPreview(
                    turns: _turns,
                    verdict: _verdict,
                    keyPoints: _keyPoints,
                  ),
                ],
                // ── Error ─────────────────────────────────────────────────
                if (_phase == _UpPhase.error) ...[
                  const AppGap.sm(),
                  _ErrorRow(
                    message: _error ?? 'Upload failed',
                    onRetry: _pickAndUpload,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding:
                EdgeInsets.fromLTRB(20, 14, 20, bottomPad + 16),
            child: SizedBox(
              width: double.infinity,
              child: _phase == _UpPhase.done
                  ? PrimaryButton(
                      label: 'Done',
                      icon: Icons.check,
                      color: AppColors.greenHaze,
                      onTap: () => Navigator.of(context).pop(),
                    )
                  : SecondaryButton(
                      label: _busy
                          ? 'Processing… keep open'
                          : 'Cancel',
                      onTap: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dropzone ─────────────────────────────────────────────────────────────────

class _Dropzone extends StatelessWidget {
  const _Dropzone({
    required this.phase,
    required this.fileName,
    required this.stageLabel,
    required this.onTap,
  });

  final _UpPhase phase;
  final String? fileName;
  final String stageLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final busy =
        phase == _UpPhase.uploading || phase == _UpPhase.processing;
    final done = phase == _UpPhase.done;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.pampas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: done ? AppColors.iceCold : AppColors.westar),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: busy
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const AppGap.xs(),
                      Text(stageLabel,
                          style: AppText.body14
                              .copyWith(fontWeight: FontWeight.w700)),
                      Text('Keep this open',
                          style: AppText.caption11
                              .copyWith(color: AppColors.schooner)),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle_outline
                            : Icons.upload_file,
                        size: 26,
                        color: done
                            ? AppColors.greenHaze
                            : AppColors.schooner,
                      ),
                      const AppGap.xs(),
                      Text(
                        fileName ?? 'Tap to upload recording',
                        style: AppText.body14
                            .copyWith(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        done
                            ? 'Tap to replace'
                            : '.mp3 · .wav · .m4a · max 100 MB',
                        style: AppText.caption11
                            .copyWith(color: AppColors.schooner),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Transcript preview ───────────────────────────────────────────────────────

class _TranscriptPreview extends StatelessWidget {
  const _TranscriptPreview({
    required this.turns,
    required this.verdict,
    required this.keyPoints,
  });

  final List<TranscriptTurn> turns;
  final String? verdict;
  final List<String> keyPoints;

  @override
  Widget build(BuildContext context) {
    final preview = turns.length > 6 ? turns.sublist(0, 6) : turns;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.westar),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Transcript', style: AppText.display16),
              const Spacer(),
              if (verdict != null && verdict!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.westar),
                  ),
                  child: Text(verdict!,
                      style: AppText.caption11
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          Text(
            '${turns.length} turns',
            style: AppText.caption11.copyWith(color: AppColors.schooner),
          ),
          const AppGap.sm(),
          for (final t in preview) ...[
            _Bubble(turn: t),
            const AppGap.xs(),
          ],
          if (turns.length > 6)
            Text(
              '+${turns.length - 6} more turns — open call detail to see all',
              style: AppText.caption11.copyWith(color: AppColors.schooner),
            ),
          if (keyPoints.isNotEmpty) ...[
            const AppGap.sm(),
            Text('AI Key Points', style: AppText.display16),
            const AppGap.xs(),
            for (final p in keyPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(p, style: AppText.body14)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn});
  final TranscriptTurn turn;

  @override
  Widget build(BuildContext context) {
    final isAgent = turn.speaker.toUpperCase() == 'AGENT';
    return Align(
      alignment:
          isAgent ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 270),
        decoration: BoxDecoration(
          color: isAgent ? AppColors.white : AppColors.springWood,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.westar),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAgent ? 'You' : 'Lead',
              style: AppText.caption11.copyWith(
                  color: AppColors.schooner,
                  fontWeight: FontWeight.w700),
            ),
            Text(turn.text, style: AppText.body14),
          ],
        ),
      ),
    );
  }
}

// ─── Error row ────────────────────────────────────────────────────────────────

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.redSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.redBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.alizarin),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              message,
              style: AppText.body14.copyWith(color: AppColors.alizarin),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
