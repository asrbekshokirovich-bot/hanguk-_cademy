import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../../staff/presentation/lesson_dialog.dart';
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
    final profile = ref.watch(profileProvider).value;
    final isStaff = profile?.isStaff ?? false;
    // Scheduling is the admin's job: they own the timetable, teachers teach
    // what is on it. Auto-record stays open to any staff member.
    final isAdmin = profile?.isAdmin ?? false;

    return AppShell(
      title: 'Jadval',
      subtitle: 'Darslarni rejalashtirish va boshqarish',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WeekHeader(weekStart: weekStart, isAdmin: isAdmin),
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
                    _LessonRow(
                      lesson: lesson,
                      isStaff: isStaff,
                      isAdmin: isAdmin,
                    ),
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
  const _WeekHeader({required this.weekStart, required this.isAdmin});

  final DateTime weekStart;
  final bool isAdmin;

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
        if (isAdmin)
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: () async {
                final saved = await showLessonDialog(context);
                if (saved == true) ref.invalidate(weekLessonsProvider);
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
  const _LessonRow({
    required this.lesson,
    required this.isStaff,
    required this.isAdmin,
  });

  final Lesson lesson;
  final bool isStaff;
  final bool isAdmin;

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

  /// Put the lesson on air, or take it off.
  ///
  /// The live room shows whichever lesson carries status 'live'. Nothing ever
  /// wrote that value, so the room was unreachable and the schedule was a
  /// list of intentions with no way to act on one.
  Future<void> _toggleLive() async {
    final l = widget.lesson;
    final next =
        l.status == LessonStatus.live ? LessonStatus.ended : LessonStatus.live;

    setState(() => _saving = true);
    try {
      await ref.read(lessonsRepositoryProvider).setLessonStatus(l.id, next);
      if (!mounted) return;
      // The row's own pill and the live room both read the lesson, and the
      // teacher is about to open the second one.
      ref.invalidate(weekLessonsProvider);
      ref.invalidate(liveLessonProvider);
      if (next == LessonStatus.live) context.go('/live');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bajarilmadi: $e')),
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
            if (widget.isStaff && l.status != LessonStatus.cancelled) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: _LiveButton(
                  live: live,
                  onPressed: _saving ? null : _toggleLive,
                ),
              ),
            ],
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
          if (widget.isStaff && l.status != LessonStatus.cancelled)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _LiveButton(
                live: live,
                onPressed: _saving ? null : _toggleLive,
              ),
            ),
          SizedBox(
            width: 40,
            child: widget.isAdmin
                ? IconButton(
                    tooltip: 'Tahrirlash',
                    onPressed: () async {
                      final saved =
                          await showLessonDialog(context, lesson: widget.lesson);
                      if (saved == true) ref.invalidate(weekLessonsProvider);
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

/// "Darsni boshlash" / "Darsni tugatish".
class _LiveButton extends StatelessWidget {
  const _LiveButton({required this.live, required this.onPressed});

  final bool live;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Ending a lesson is destructive-ish and starting one is the happy path,
    // so they do not look alike: filled lime to go on air, outlined red to
    // come off it.
    return live
        ? OutlinedButton.icon(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0x33DC2626)),
              foregroundColor: HkColors.dangerBright,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HkRadius.control),
              ),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 17),
            label: const Text('Tugatish'),
          )
        : FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: HkColors.lime,
              foregroundColor: HkColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HkRadius.control),
              ),
            ),
            icon: const Icon(Icons.play_circle_outline, size: 17),
            label: const Text('Boshlash'),
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
