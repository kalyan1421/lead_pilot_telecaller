import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppSpacing, AppRadius;

import '../models/lead.dart';
import '../services/call_actions.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _filter = 'All';
  final _searchController = TextEditingController();
  String _query = '';

  static const _filters = ['All', 'High Intent', 'New', 'Follow-up', 'Cold'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Lead> _applyFilter(List<Lead> all) => switch (_filter) {
    'High Intent' =>
      all.where((l) => l.intent.toLowerCase().contains('high')).toList(),
    'New' => all.where((l) => l.score <= 0).toList(),
    'Follow-up' =>
      all.where((l) => l.checklist.any((i) => !i.completed)).toList(),
    'Cold' =>
      all
          .where((l) => l.score < 40 || l.intent.toLowerCase().contains('cold'))
          .toList(),
    _ => all,
  };

  List<Lead> _applySearch(List<Lead> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((l) =>
            l.name.toLowerCase().contains(q) ||
            l.phone.toLowerCase().contains(q) ||
            l.intent.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(leadsProvider);
    final filtered = _applySearch(_applyFilter(leads));

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildScrollBody(context, filtered)),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return LpTabHeader(
      title: 'Your Leads',
      subtitle: 'Good morning',
      actions: [
        // Bell → notification centre, with an unread dot.
        TapScale(
          onTap: () => context.push('/notifications'),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.pampas,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.westar),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.notifications_outlined,
                      size: 18,
                      color: AppColors.merlin,
                    ),
                  ),
                ),
                if (ref.watch(followUpsProvider).any(
                  (t) => t.status != FollowUpStatus.done,
                ))
                  Positioned(
                    right: 9,
                    top: 9,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.alizarin,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Add lead.
        TapScale(
          onTap: () => context.push('/outbound/add'),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.blueRibbon,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.blueAction,
            ),
            child: const Center(
              child: Icon(Icons.add, color: AppColors.white, size: 24),
            ),
          ),
        ),
      ],
    );
  }

  // ── Scrollable body ────────────────────────────────────────────────────────

  Widget _buildScrollBody(BuildContext context, List<Lead> leads) {
    return CustomScrollView(
      slivers: [
        // Stats row — computed from real data.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Builder(builder: (_) {
              final callLog = ref.watch(callLogProvider);
              final now = DateTime.now();
              final callsToday = callLog
                  .where((e) =>
                      e.calledAt.year == now.year &&
                      e.calledAt.month == now.month &&
                      e.calledAt.day == now.day)
                  .length;
              final scored =
                  ref.watch(leadsProvider).where((l) => l.score > 0).toList();
              final avgScore = scored.isEmpty
                  ? null
                  : scored.map((l) => l.score).reduce((a, b) => a + b) ~/
                      scored.length;
              return Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.call_outlined,
                      label: 'Calls Today',
                      value: '$callsToday',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.show_chart,
                      label: 'Avg Score',
                      value: avgScore?.toString() ?? '—',
                      valueColor: AppColors.blueRibbon,
                      suffix: avgScore == null ? null : '/100',
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
        // Search bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _buildSearchBar(),
          ),
        ),
        // Filter chips
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _buildFilterChips(),
          ),
        ),
        // Lead list or empty state
        if (leads.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 40, color: AppColors.tide),
                  const SizedBox(height: 8),
                  Text(
                    _filter == 'All' ? 'No leads yet' : 'No $_filter leads',
                    style: AppText.body14.copyWith(
                      color: AppColors.schooner,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _filter == 'All'
                        ? 'Tap + to add your first lead'
                        : 'Try a different filter',
                    style: AppText.caption11,
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
            sliver: SliverList.separated(
              itemCount: leads.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _LeadTile(lead: leads[i]),
            ),
          ),
      ],
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final filterActive = _filter != 'All';
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.only(left: 12, right: 6),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.westar),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 16, color: AppColors.schooner),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    style: AppText.body14.copyWith(color: AppColors.zeus),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Search leads...',
                      hintStyle: AppText.body14.copyWith(
                        color: AppColors.boulder,
                      ),
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    child: const Icon(Icons.close,
                        size: 16, color: AppColors.schooner),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // Filter button — opens the filter sheet; dot shows when a filter is on.
        TapScale(
          onTap: _openFilterSheet,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: filterActive ? AppColors.blueRibbon : AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: filterActive
                          ? AppColors.blueRibbon
                          : AppColors.westar,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.tune,
                      size: 18,
                      color: filterActive ? AppColors.white : AppColors.merlin,
                    ),
                  ),
                ),
                if (filterActive)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.blueRibbon, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.westar,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Filter leads', style: AppText.display20.copyWith(fontSize: 18)),
              const SizedBox(height: 14),
              for (final f in _filters)
                TapScale(
                  onTap: () {
                    setState(() => _filter = f);
                    Navigator.of(sheetContext).pop();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: f == _filter
                          ? AppColors.ribbonSurface
                          : AppColors.pampas,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: f == _filter
                            ? AppColors.blueRibbon
                            : AppColors.westar,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            f,
                            style: AppText.body14.copyWith(
                              fontWeight: FontWeight.w600,
                              color: f == _filter
                                  ? AppColors.blueRibbon
                                  : AppColors.zeus,
                            ),
                          ),
                        ),
                        if (f == _filter)
                          const Icon(Icons.check,
                              size: 18, color: AppColors.blueRibbon),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final active = f == _filter;
          return TapScale(
            onTap: () => setState(() => _filter = f),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? AppColors.blueRibbon : AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: active ? null : Border.all(color: AppColors.westar),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppColors.blueRibbon.withValues(alpha: 0.25),
                          offset: const Offset(0, 2),
                          blurRadius: 3,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  f,
                  style: AppText.body13.copyWith(
                    color: active ? AppColors.white : AppColors.merlin,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.065,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Stat tile ────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.zeus,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.westar),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              Icon(icon, size: 11, color: AppColors.schooner),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppText.label11,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Value row with optional change/suffix
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppText.mono(
                  size: 28,
                  weight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Text(
                  suffix!,
                  style: AppText.body13.copyWith(
                    color: AppColors.schooner,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Lead tile ────────────────────────────────────────────────────────────────

class _LeadTile extends ConsumerWidget {
  const _LeadTile({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TapScale(
      onTap: () {
        ref.read(selectedLeadIdProvider.notifier).set(lead.id);
        context.push('/leads/${lead.id}');
      },
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.westar),
          boxShadow: AppShadows.card,
        ),
        child: Stack(
          children: [
            // Subtle blue glow — top-right decoration
            Positioned(
              right: -20,
              top: -40,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    color: Color(0x121E4AFF),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ScoreRing(score: lead.score, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          lead.name,
                          style: AppText.display16,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        // Phone
                        Row(
                          children: [
                            const Icon(
                              Icons.phone_outlined,
                              size: 11,
                              color: AppColors.schooner,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              lead.phone,
                              style: AppText.mono(
                                size: 12.5,
                                color: AppColors.schooner,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Intent + Source pills
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            if (lead.intent.isNotEmpty)
                              LpMiniPill(
                                label: lead.intent,
                                icon: Icons.bolt,
                                foreground: AppColors.greenHaze,
                                background: AppColors.foam,
                                border: AppColors.iceCold,
                              ),
                            LpMiniPill(
                              label: lead.source.displayName,
                              foreground: AppColors.governorBay,
                              background: AppColors.zircon,
                              border: AppColors.periwinkle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Timestamp · topic
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_outlined,
                              size: 11,
                              color: AppColors.tide,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                _timeStamp(),
                                style: AppText.caption11.copyWith(
                                  color: AppColors.tide,
                                  fontSize: 11.5,
                                  height: 14 / 11.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Call button — taps go directly to caller selector
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _startQuickCall(context, ref),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.blueRibbon,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blueRibbon.withValues(alpha: 0.25),
                            offset: const Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.call,
                          size: 16,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startQuickCall(BuildContext context, WidgetRef ref) async {
    final lastCall = lead.history.isNotEmpty ? lead.history.first : null;
    final result = await startCallWithNotesBubble(
      leadId: lead.id,
      leadName: lead.name,
      phoneNumber: lead.phone,
      leadScore: lead.score,
      temperature: lead.temperature.value,
      intent: lead.intent,
      scriptOpeningLine: lead.script.openingLine,
      memoryFacts: lead.memory.take(4).map((m) => m.text).toList(),
      lastCallTs: lastCall?.calledAt?.toIso8601String() ?? '',
      lastCallScore: lastCall?.score ?? 0,
      lastCallSummary: lastCall?.title ?? '',
    );
    if (!context.mounted) return;

    if (!result.overlayPermissionGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allow display over other apps, then tap quick call again.',
          ),
        ),
      );
      return;
    }

    if (!result.launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No calling app available on this device.'),
        ),
      );
      return;
    }

    // The call is on its way out — log it so it shows in Calls + history.
    await recordOutboundCall(ref, lead);
  }

  String _timeStamp() {
    final diff = DateTime.now().difference(lead.lastContact);
    final String timeStr;
    if (diff.inMinutes < 60) {
      timeStr = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      timeStr = '$h hour${h == 1 ? '' : 's'} ago';
    } else if (diff.inDays == 1) {
      timeStr = '1 day ago';
    } else {
      timeStr = '${diff.inDays} days ago';
    }
    final topic = lead.propertyInterest;
    return (topic != null && topic.isNotEmpty) ? '$timeStr · $topic' : timeStr;
  }
}
