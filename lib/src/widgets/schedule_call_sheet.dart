import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/lead.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'leadpilot_widgets.dart';

class ScheduleCallSheet extends ConsumerStatefulWidget {
  const ScheduleCallSheet({super.key, required this.lead, this.defaultDaysAhead = 1});

  final Lead lead;
  final int defaultDaysAhead;

  static Future<void> show(BuildContext context, Lead lead, {int daysAhead = 1}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => ScheduleCallSheet(lead: lead, defaultDaysAhead: daysAhead),
      );

  @override
  ConsumerState<ScheduleCallSheet> createState() => _ScheduleCallSheetState();
}

class _ScheduleCallSheetState extends ConsumerState<ScheduleCallSheet> {
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now().add(Duration(days: widget.defaultDaysAhead));
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final scheduledAt = DateTime(
      _date.year, _date.month, _date.day, _time.hour, _time.minute,
    );
    final today = DateTime.now();
    final isToday = scheduledAt.year == today.year &&
        scheduledAt.month == today.month &&
        scheduledAt.day == today.day;
    final isOverdue = scheduledAt.isBefore(today);

    final id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final task = FollowUpTask(
      id: id,
      taskText: _noteController.text.trim().isEmpty
          ? 'Follow-up call with ${widget.lead.name}'
          : _noteController.text.trim(),
      leadName: widget.lead.name,
      phone: widget.lead.phone,
      leadId: widget.lead.id,
      status: isOverdue ? FollowUpStatus.overdue : FollowUpStatus.pending,
      dueLabel: DateFormat('dd MMM · hh:mm a').format(scheduledAt),
      dueToday: isToday,
      scheduledAt: scheduledAt,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    await ref.read(followUpsProvider.notifier).schedule(task);

    // Schedule a device notification at the chosen time.
    if (!isOverdue) {
      await NotificationService.instance.scheduleFollowUp(
        notifId: id.hashCode.abs() % 100000,
        title: 'Follow-up: ${widget.lead.name}',
        body: task.taskText,
        scheduledAt: scheduledAt,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, dd MMM yyyy');
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.westar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Schedule Call', style: AppText.display20.copyWith(fontSize: 18)),
          Text(
            widget.lead.name,
            style: AppText.body13.copyWith(color: AppColors.schooner),
          ),
          const AppGap.lg(),
          Row(
            children: [
              Expanded(
                child: ScheduleCallPickerTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: dateFmt.format(_date),
                  onTap: _pickDate,
                ),
              ),
              const AppGap.sm(axis: Axis.horizontal),
              Expanded(
                child: ScheduleCallPickerTile(
                  icon: Icons.access_time_outlined,
                  label: 'Time',
                  value: _time.format(context),
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const AppGap.md(),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add a note (optional)',
              hintStyle: AppText.body13.copyWith(color: AppColors.tide),
              filled: true,
              fillColor: AppColors.pampas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.westar),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.westar),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const AppGap.lg(),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: _saving ? 'Saving…' : 'Schedule Call',
              icon: Icons.calendar_today_outlined,
              onTap: _saving ? () {} : _save,
            ),
          ),
        ],
      ),
    );
  }
}

class ScheduleCallPickerTile extends StatelessWidget {
  const ScheduleCallPickerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.pampas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.westar),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.blueRibbon),
            const AppGap.xs(axis: Axis.horizontal),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.label11),
                  Text(
                    value,
                    style: AppText.body13.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
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
