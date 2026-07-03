import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart' hide AppSpacing, AppRadius;

import '../models/lead.dart';
import '../services/call_actions.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class DialerScreen extends ConsumerStatefulWidget {
  const DialerScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends ConsumerState<DialerScreen> {
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  bool _muted = false;
  bool _speaker = false;

  // Live cues, built from this contact's memory bubble (next_call_strategy,
  // open objections, remembered facts) once `_cuesFuture` resolves — NOT
  // hardcoded. A lead with no call history yet just has no cues to show.
  List<String> _cues = const [];
  bool _cuesLoaded = false;
  int _cueIndex = 0;
  Timer? _cueTimer;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) { if (mounted) setState(() {}); },
    );
    _loadCues();
  }

  Future<void> _loadCues() async {
    try {
      final lead = await ref.read(leadRepositoryProvider).leadDetail(widget.leadId);
      if (!mounted) return;
      setState(() {
        _cues = _buildCues(lead);
        _cuesLoaded = true;
      });
      if (_cues.length > 1) {
        _cueTimer = Timer.periodic(
          const Duration(seconds: 8),
          (_) { if (mounted) setState(() => _cueIndex = (_cueIndex + 1) % _cues.length); },
        );
      }
    } catch (_) {
      // No memory available (offline, or backend error) — leave _cues empty;
      // the UI shows the "no live cues" state rather than stale/fake content.
      if (mounted) setState(() => _cuesLoaded = true);
    }
  }

  /// Opening line + open objections + a couple of remembered facts — all
  /// already computed by the backend's post-call analysis, nothing invented
  /// here. Empty if this is the contact's first-ever call.
  List<String> _buildCues(Lead lead) {
    final cues = <String>[];
    if (lead.script.openingLine.isNotEmpty) cues.add(lead.script.openingLine);
    for (final o in lead.objections) {
      if (o.question.isNotEmpty) cues.add('Address: ${o.question}');
    }
    for (final m in lead.memory.take(2)) {
      if (m.text.isNotEmpty) cues.add(m.text);
    }
    return cues;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cueTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  String get _elapsed {
    final m = _stopwatch.elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == widget.leadId,
      orElse: () => leads.first,
    );

    return Scaffold(
      backgroundColor: AppColors.zeus,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top: launch native dialer ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TapScale(
                    onTap: () => launchPhoneCall(lead.phone),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.open_in_new,
                        color: AppColors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Centre: score + name + timer ─────────────────────────────
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScoreRing(score: lead.score, size: 96),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    lead.name,
                    style: AppText.display20.copyWith(
                      color: AppColors.white,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    lead.phone,
                    style: AppText.mono(size: 15, color: AppColors.tide),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Live timer
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      _elapsed,
                      style: AppText.mono(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Live cue strip — real, lead-specific, only once loaded ────
            if (_cuesLoaded && _cues.isNotEmpty)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Container(
                  key: ValueKey(_cueIndex),
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.violetSurface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.violetBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: AppColors.electricViolet,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _cues[_cueIndex],
                          style: AppText.body13.copyWith(
                            color: AppColors.electricViolet,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_cuesLoaded)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: AppColors.tide),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'First contact — no prior history yet',
                        style: AppText.body13.copyWith(color: AppColors.tide),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: AppSpacing.lg),

            // ── Controls: mute + speaker ─────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DialControl(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  label: _muted ? 'Unmute' : 'Mute',
                  active: _muted,
                  onTap: () => setState(() => _muted = !_muted),
                ),
                const SizedBox(width: 40),
                _DialControl(
                  icon: _speaker ? Icons.volume_up : Icons.volume_down,
                  label: 'Speaker',
                  active: _speaker,
                  onTap: () => setState(() => _speaker = !_speaker),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── End call ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 72, AppSpacing.xxl),
              child: PrimaryButton(
                label: 'End',
                color: AppColors.alizarin,
                onTap: () => context.go('/leads/${widget.leadId}/post-call'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialControl extends StatelessWidget {
  const _DialControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.blueRibbon
                  : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.white, size: 22),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: AppText.caption11.copyWith(color: AppColors.tide),
          ),
        ],
      ),
    );
  }
}
