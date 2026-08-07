import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/clock.dart';
import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/stat_card.dart';
import '../../../design_system/widgets/states.dart';
import '../../lessons/data/providers.dart';
import '../../lessons/domain/models.dart';
import '../data/staff_providers.dart';
import '../domain/staff_models.dart';

/// "Asosiy" for a teacher: today's lessons and the homework waiting to be
/// marked.
///
/// Deliberately not the student dashboard with different numbers. A teacher
/// opens this to answer two questions — what am I teaching next, and what is
/// piling up — so those are the only two panels below the stat row.
class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final profile = ref.watch(profileProvider).value;

    return AppShell(
      title: 'Asosiy',
      subtitle: profile == null
          ? 'Bugungi darslar va vazifalar'
          : '${profile.fullName} · bugungi darslar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AsyncSection(
            value: ref.watch(teacherStatsProvider),
            onRetry: () => ref.invalidate(teacherStatsProvider),
            loadingHeight: 120,
            builder: (stats) => HkStatRow(
              cards: [
                HkStatCard(
                  label: 'Bugungi darslar',
                  value: '${stats.lessonsToday}',
                  icon: Icons.event_note_rounded,
                  note: 'Bugun rejalashtirilgan',
                ),
                HkStatCard(
                  label: 'Talabalarim',
                  value: '${stats.students}',
                  icon: Icons.people_alt_rounded,
                  note: 'Guruhlarim bo‘yicha',
                ),
                HkStatCard(
                  label: 'Tekshirilmagan',
                  value: '${stats.ungraded}',
                  icon: Icons.assignment_late_outlined,
                  note: 'vazifa kutilmoqda',
                  valueColor: stats.ungraded > 0
                      ? HkColors.warningBright
                      : HkColors.textPrimary,
                ),
                HkStatCard(
                  label: "O'rtacha davomat",
                  value: hkPercent(stats.averageAttendance),
                  icon: Icons.trending_up_rounded,
                  note: 'Talabalarim bo‘yicha',
                  highlight: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          if (layout.isExpanded)
            IntrinsicHeight(
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _TodayLessonsCard()),
                  SizedBox(width: HkSpace.gridGapWide),
                  Expanded(flex: 2, child: _GradingQueueCard()),
                ],
              ),
            )
          else ...[
            const _TodayLessonsCard(),
            const SizedBox(height: HkSpace.gridGapWide),
            const _GradingQueueCard(),
          ],
        ],
      ),
    );
  }
}

class _TodayLessonsCard extends ConsumerWidget {
  const _TodayLessonsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassPanel(
      radius: HkRadius.cardLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bugungi darslarim', style: HkType.sectionTitle),
          const SizedBox(height: 16),
          AsyncSection(
            value: ref.watch(todaysLessonsProvider),
            onRetry: () => ref.invalidate(todaysLessonsProvider),
            isEmpty: (l) => l.isEmpty,
            emptyMessage: 'Bugun darsingiz yo‘q',
            builder: (lessons) => Column(
              children: [
                for (final lesson in lessons) ...[
                  _LessonRow(lesson: lesson),
                  if (lesson != lessons.last) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final live = lesson.status == LessonStatus.live;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: live ? const Color(0x24D4E94C) : const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        border: Border.all(
          color: live ? const Color(0x47D4E94C) : const Color(0x0FFFFFFF),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('HH:mm').format(lesson.startsAt),
                  style: HkType.monoTime,
                ),
                const SizedBox(height: 2),
                Text('${lesson.durationMinutes} daq', style: HkType.muted),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: lesson.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.title,
                  style: HkType.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${lesson.category} · ${lesson.enrolledCount} talaba',
                  style: HkType.muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (live)
            LimeButton(
              label: 'Darsni boshlash',
              height: 38,
              onPressed: () => context.go('/live'),
            )
          else
            HkPill(
              label: lesson.status.label,
              background: lesson.status.pillBackground,
              foreground: lesson.status.pillForeground,
            ),
        ],
      ),
    );
  }
}

class _GradingQueueCard extends ConsumerWidget {
  const _GradingQueueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = hkNow();

    return GlassPanel(
      radius: HkRadius.cardLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tekshirish kutilmoqda',
                  style: HkType.sectionTitle,
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.go('/teacher/grading'),
                  child: const Text(
                    'Barchasi',
                    style: TextStyle(
                      fontFamily: HkType.family,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HkColors.lime,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AsyncSection(
            value: ref.watch(submissionsProvider),
            onRetry: () => ref.invalidate(submissionsProvider),
            isEmpty: (s) => s.every((x) => x.isGraded),
            emptyMessage: 'Hammasi tekshirilgan',
            builder: (all) {
              final pending = all.where((s) => !s.isGraded).take(4).toList();
              return Column(
                children: [
                  for (final s in pending) ...[
                    _PendingRow(submission: s, now: now),
                    if (s != pending.last) const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.submission, required this.now});

  final Submission submission;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final waitingDays = now.difference(submission.submittedAt).inDays;
    // A day old is normal; two days is the teacher falling behind, and the
    // design colours it accordingly.
    final late = waitingDays >= 2;

    return Row(
      children: [
        HkAvatar(
          initials: submission.initials,
          size: 34,
          gradient: submission.gradient,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                submission.studentName,
                style: HkType.cardTitle.copyWith(fontSize: 13.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                submission.lessonTitle == null
                    ? submission.assignmentTitle
                    : '${submission.assignmentTitle} · '
                        '${submission.lessonTitle}',
                style: HkType.muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        HkPill(
          label: hkRelative(submission.submittedAt, now: now),
          background: late ? const Color(0x29F2746A) : const Color(0x24D4E94C),
          foreground: late ? HkColors.dangerBright : HkColors.lime,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        ),
      ],
    );
  }
}
