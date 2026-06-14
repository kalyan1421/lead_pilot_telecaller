import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppSpacing, AppRadius;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/lead.dart';
import '../services/user_profile_store.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/leadpilot_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final leads = ref.watch(leadsProvider);
    final callLog = ref.watch(callLogProvider);
    final stages = ref.watch(leadStageProvider);

    final now = DateTime.now();
    final callsThisMonth = callLog
        .where((e) => e.calledAt.year == now.year && e.calledAt.month == now.month)
        .toList();
    final scored = callLog.where((e) => e.score > 0).toList();
    final avgScore = scored.isEmpty
        ? null
        : scored.map((e) => e.score).reduce((a, b) => a + b) ~/ scored.length;
    final qualified =
        leads.where((l) => l.temperature == LeadTemperature.hot).length;
    final booked =
        stages.values.where((s) => s == LeadStage.booked).length;
    final convRate =
        leads.isEmpty ? null : ((booked / leads.length) * 100).round();

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          children: [
            LpTabHeader(
              title: 'Profile',
              subtitle: profile.company.isEmpty ? null : profile.company,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 100),
                children: [
                  _UserCard(profile: profile),
                  const SizedBox(height: AppSpacing.md),

                  // ── Monthly stats (computed) ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('THIS MONTH', style: AppText.label11),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: MetricTile(
                                label: 'Calls Made',
                                value: '${callsThisMonth.length}',
                                mono: true,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: MetricTile(
                                label: 'Hot Leads',
                                value: '$qualified',
                                valueColor: AppColors.governorBay,
                                mono: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: MetricTile(
                                label: 'Avg Score',
                                value: avgScore?.toString() ?? '—',
                                valueColor: AppColors.salem,
                                mono: true,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: MetricTile(
                                label: 'Conv Rate',
                                value: convRate == null ? '—' : '$convRate%',
                                valueColor: AppColors.electricViolet,
                                mono: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // ── Preferences ───────────────────────────────────────────
                  _SettingsSection(
                    title: 'PREFERENCES',
                    children: [
                      _LanguageRow(
                        selected: profile.language,
                        onSelect: (lang) => ref
                            .read(userProfileProvider.notifier)
                            .update(profile.copyWith(language: lang)),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _NotificationsRow(
                        enabled: profile.notificationsEnabled,
                        onChanged: (v) => ref
                            .read(userProfileProvider.notifier)
                            .update(profile.copyWith(notificationsEnabled: v)),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // ── Compliance ────────────────────────────────────────────
                  _SettingsSection(
                    title: 'COMPLIANCE',
                    children: [
                      _SettingsRow(
                        icon: Icons.verified_outlined,
                        label: 'Privacy Policy Compliant',
                        trailing: _GreenBadge('Enabled'),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingsRow(
                        icon: Icons.mic_outlined,
                        label: 'Call Recordings',
                        trailing: Text(
                          '90 days',
                          style:
                              AppText.body13.copyWith(color: AppColors.schooner),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // ── About ─────────────────────────────────────────────────
                  _SettingsSection(
                    title: 'ABOUT',
                    children: [
                      _SettingsRow(
                        icon: Icons.info_outline,
                        label: 'App Version',
                        trailing: Text(
                          '2.6.1 (build 4421)',
                          style: AppText.mono(size: 11, color: AppColors.tide),
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingsRow(
                        icon: Icons.lock_outline,
                        label: 'Privacy Policy',
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _SettingsRow(
                        icon: Icons.logout,
                        label: 'Log out',
                        iconColor: AppColors.alizarin,
                        labelColor: AppColors.alizarin,
                        onTap: () => context.go('/onboarding'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── User card ────────────────────────────────────────────────────────────────

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.westar),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.blueRibbon,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                profile.initials,
                style: AppText.display16.copyWith(
                  color: AppColors.white,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.name, style: AppText.display16),
                Text(
                  profile.role.isEmpty ? 'Telecaller' : profile.role,
                  style: AppText.body13.copyWith(color: AppColors.schooner),
                ),
                if (profile.company.isNotEmpty)
                  Text(
                    profile.company,
                    style: AppText.caption11.copyWith(color: AppColors.tide),
                  ),
              ],
            ),
          ),
          LpIconButton(
            icon: Icons.edit_outlined,
            onTap: () => EditProfileSheet.show(context, profile),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.label11),
          const SizedBox(height: AppSpacing.xs),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.westar),
              boxShadow: AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.iconColor = AppColors.schooner,
    this.labelColor = AppColors.zeus,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppText.body14.copyWith(color: labelColor),
              ),
            ),
            ?trailing,
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 16, color: AppColors.tide),
          ],
        ),
      ),
    );
  }
}

class _NotificationsRow extends StatelessWidget {
  const _NotificationsRow({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.notifications_outlined,
              size: 18, color: AppColors.schooner),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Notifications',
              style: AppText.body14.copyWith(color: AppColors.zeus),
            ),
          ),
          Switch.adaptive(
            value: enabled,
            activeThumbColor: AppColors.blueRibbon,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  static const _scripts = ['తె', 'हि', 'N', 'த', 'ಕ'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.language_outlined,
              size: 18, color: AppColors.schooner),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Language',
              style: AppText.body14.copyWith(color: AppColors.zeus),
            ),
          ),
          for (final script in _scripts)
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: GestureDetector(
                onTap: () => onSelect(script),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: script == selected
                        ? AppColors.ribbonSurface
                        : AppColors.pampas,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(
                      color: script == selected
                          ? AppColors.blueRibbon
                          : AppColors.westar,
                      width: script == selected ? 1.5 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      script,
                      style: AppText.body13.copyWith(
                        fontSize: 12,
                        color: script == selected
                            ? AppColors.blueRibbon
                            : AppColors.merlin,
                        fontWeight: script == selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GreenBadge extends StatelessWidget {
  const _GreenBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.foam,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.iceCold),
      ),
      child: Text(
        label,
        style: AppText.caption11.copyWith(
          color: AppColors.salem,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}
