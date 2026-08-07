import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/lessons_repository.dart';
import '../data/providers.dart';
import '../domain/models.dart';

/// "Jadval" — the week's lessons, with per-lesson auto-record control.
///
/// Editing (the pencil column, "Yangi dars") is staff-only and is gated on
/// `UserProfile.isAdmin`; a student sees the same table read-only rather than
/// buttons that RLS would reject.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final weekStart = ref.watch(scheduleWeekStartProvider);
    final isStaff =
        ref.watch(profileProvider).value?.isStaff ?? false;

    return AppShell(
      title: 'Jadval',
      subtitle: 'Darslarni rejalashtirish va boshqarish',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeekHeader(weekStart: weekStart, isStaff: isStaff),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(weekLessonsProvider),
            onRetry: () => ref.invalidate(weekLessonsProvider),
            loadingHeight: 240,
            isEmpty: (l) => l.isEmpty,
            emptyMessage: 'Bu haftada dars rejalashtirilmagan',
            builder: (lessons) => GlassPanel(
              radius: HkRadius.cardLarge,
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  if (layout.isExpanded) const _TableHeader(),
                  for (final lesson in lessons)
                    _LessonRow(lesson: lesson, isStaff: isStaff),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekHeader extends ConsumerWidget {
  const _WeekHeader({required this.weekStart, required this.isStaff});

  final DateTime weekStart;
  final bool isStaff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final end = weekStart.add(const Duration(days: 6));
    final fmtDay = DateFormat('d', 'uz');
    final fmtFull = DateFormat('d-MMMM, y', 'uz');

    void step(int weeks) {
      ref.read(scheduleWeekStartProvider.notifier).state =
          weekStart.add(Duration(days: 7 * weeks));
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GlassPanel(
          radius: HkRadius.pill,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => step(-1),
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                color: HkColors.textSecondary,
                tooltip: 'Oldingi hafta',
              ),
              Text(
                '${fmtDay.format(weekStart)} – ${fmtFull.format(end)}',
                style: HkType.label,
              ),
              IconButton(
                onPressed: () => step(1),
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                color: HkColors.textSecondary,
                tooltip: 'Keyingi hafta',
              ),
            ],
          ),
        ),
        const HkPill(
          label: 'Avto-yozuv yoniq',
          background: Color(0x26D4E94C),
          foreground: HkColors.lime,
          icon: Icons.fiber_manual_record_rounded,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        ),
        if (isStaff)
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Dars yaratish oynasi keyingi bosqichda qo‘shiladi.',
                    ),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: HkColors.royalBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HkRadius.control),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Yangi dars',
                style: TextStyle(
                  fontFamily: HkType.family,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int flex) => Expanded(
          flex: flex,
          child: Text(label, style: HkType.muted),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          cell('Vaqt', 3),
          cell('Dars', 5),
          cell("O'qituvchi", 4),
          cell('Talabalar', 2),
          cell('Avto-yozuv', 3),
          cell('Holat', 3),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _LessonRow extends ConsumerStatefulWidget {
  const _LessonRow({required this.lesson, required this.isStaff});

  final Lesson lesson;
  final bool isStaff;

  @override
  ConsumerState<_LessonRow> createState() => _LessonRowState();
}

class _LessonRowState extends ConsumerState<_LessonRow> {
  late bool _autoRecord = widget.lesson.autoRecord;
  bool _saving = false;

  Future<void> _toggleAutoRecord(bool value) async {
    // Optimistic: the switch is the only feedback the user gets, and a
    // round trip to Supabase over a slow link makes it feel stuck.
    final previous = _autoRecord;
    setState(() {
      _autoRecord = value;
      _saving = true;
    });
    try {
      await ref
          .read(lessonsRepositoryProvider)
          .setAutoRecord(widget.lesson.id, value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoRecord = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saqlanmadi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = HkLayout.of(context);
    final l = widget.lesson;
    final live = l.status == LessonStatus.live;

    final decoration = BoxDecoration(
      color: live ? const Color(0x14D4E94C) : Colors.transparent,
      borderRadius: BorderRadius.circular(HkRadius.cardSmall),
    );

    if (!layout.isExpanded) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(14),
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  DateFormat('E, HH:mm', 'uz').format(l.startsAt),
                  style: HkType.monoTime.copyWith(fontSize: 13),
                ),
                const Spacer(),
                HkPill(
                  label: l.status.label,
                  background: l.status.pillBackground,
                  foreground: l.status.pillForeground,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l.title, style: HkType.cardTitle),
            const SizedBox(height: 4),
            Text(
              '${l.teacher?.fullName ?? '—'} · ${l.enrolledCount} ta talaba '
              '· ${l.durationMinutes} daq',
              style: HkType.muted,
            ),
            const SizedBox(height: 10),
            _AutoRecordToggle(
              value: _autoRecord,
              enabled: widget.isStaff && !_saving,
              onChanged: _toggleAutoRecord,
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: decoration,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('HH:mm').format(l.startsAt),
                  style: HkType.monoTime,
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('E', 'uz').format(l.startsAt)} · '
                  '${l.durationMinutes} daq',
                  style: HkType.muted,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: l.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.title,
                        style: HkType.cardTitle.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(l.category, style: HkType.muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                if (l.teacher != null) ...[
                  HkAvatar(
                    initials: l.teacher!.initials,
                    size: 30,
                    gradient: l.teacher!.gradient,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    l.teacher?.fullName ?? '—',
                    style: HkType.label.copyWith(fontSize: 12.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${l.enrolledCount}', style: HkType.label),
          ),
          Expanded(
            flex: 3,
            child: _AutoRecordToggle(
              value: _autoRecord,
              enabled: widget.isStaff && !_saving,
              onChanged: _toggleAutoRecord,
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: HkPill(
                label: l.status.label,
                background: l.status.pillBackground,
                foreground: l.status.pillForeground,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: widget.isStaff
                ? IconButton(
                    tooltip: 'Tahrirlash',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Tahrirlash oynasi keyingi bosqichda qo‘shiladi.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 17,
                      color: HkColors.textTertiary,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _AutoRecordToggle extends StatelessWidget {
  const _AutoRecordToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.78,
          child: Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: HkColors.ink,
            activeTrackColor: HkColors.lime,
            inactiveThumbColor: HkColors.textTertiary,
            inactiveTrackColor: const Color(0x14FFFFFF),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          value ? 'Yoniq' : 'O‘chiq',
          style: HkType.chip.copyWith(
            color: value ? HkColors.lime : HkColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
