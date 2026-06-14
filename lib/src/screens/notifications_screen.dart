import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppSpacing, AppRadius;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

/// Notification centre — surfaces scheduled follow-up reminders (the same
/// tasks that fire device notifications) so the bell has somewhere to go.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(followUpsProvider);
    final now = DateTime.now();

    // Upcoming reminders, soonest first; completed ones drop off.
    final upcoming = tasks
        .where((t) => t.status != FollowUpStatus.done)
        .toList()
      ..sort((a, b) => (a.scheduledAt ?? now).compareTo(b.scheduledAt ?? now));

    return LpScreen(
      title: 'Notifications',
      subtitle: upcoming.isEmpty
          ? 'No reminders scheduled'
          : '${upcoming.length} upcoming reminder${upcoming.length == 1 ? '' : 's'}',
      child: upcoming.isEmpty
          ? const _EmptyNotifications()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: upcoming.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _NotificationTile(task: upcoming[i]),
            ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_none, size: 44, color: AppColors.tide),
          const SizedBox(height: 10),
          Text(
            'You\'re all caught up',
            style: AppText.body14.copyWith(
              color: AppColors.schooner,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Schedule a follow-up to get a reminder here',
            style: AppText.caption11,
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.task});

  final FollowUpTask task;

  @override
  Widget build(BuildContext context) {
    final isOverdue = task.status == FollowUpStatus.overdue;
    final when = task.scheduledAt;
    final whenLabel = when != null
        ? DateFormat('EEE, dd MMM · hh:mm a').format(when)
        : (task.dueLabel ?? '');

    return TapScale(
      onTap: task.leadId != null
          ? () => context.push('/leads/${task.leadId}')
          : null,
      child: LpCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isOverdue ? AppColors.redSurface : AppColors.ribbonSurface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                isOverdue ? Icons.notifications_active : Icons.alarm,
                size: 18,
                color: isOverdue ? AppColors.alizarin : AppColors.blueRibbon,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.taskText,
                    style: AppText.body14.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    task.leadName,
                    style: AppText.body13.copyWith(color: AppColors.schooner),
                  ),
                  if (whenLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 12,
                          color: isOverdue ? AppColors.alizarin : AppColors.tide,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          whenLabel,
                          style: AppText.caption11.copyWith(
                            color: isOverdue
                                ? AppColors.alizarin
                                : AppColors.schooner,
                            fontWeight:
                                isOverdue ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
