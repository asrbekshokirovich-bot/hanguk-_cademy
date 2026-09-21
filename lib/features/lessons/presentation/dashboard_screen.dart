import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/stat_card.dart';
import '../../../design_system/widgets/states.dart';
import '../data/providers.dart';
import '../domain/models.dart';
import '../../../core/env.dart';
import 'material_link.dart';
import 'submit_assignment_dialog.dart';
import '../../../core/clock.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);

    return AppShell(
      title: 'Asosiy',
      subtitle: "Bugungi darslar va so'nggi yozuvlar",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AsyncSection(
            value: ref.watch(liveLessonProvider),
            onRetry: () => ref.invalidate(liveLessonProvider),
            loadingHeight: 190,
            builder: (lesson) => lesson == null
                ? const _NoLiveBanner()
                : LiveHeroBanner(lesson: lesson),
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(dashboardStatsProvider),
            onRetry: () => ref.invalidate(dashboardStatsProvider),
            loadingHeight: 120,
            builder: (stats) => _StatRow(stats: stats),
          ),
          // Above the timetable, because it is the thing with a deadline on
          // it. Homework used to live only on the recording-detail page,
          // which is reachable only through a recording — and there are
          // none, so work a teacher set was invisible to the student who
          // owed it. Renders nothing at all when there is none.
          const _HomeworkCard(),
          const SizedBox(height: HkSpace.gridGapWide),
          if (layout.isExpanded)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 3, child: _TodayScheduleCard()),
                  const SizedBox(width: HkSpace.gridGapWide),
                  const Expanded(flex: 2, child: _RecentRecordingsCard()),
                ],
              ),
            )
          else ...[
            const _TodayScheduleCard(),
            const SizedBox(height: HkSpace.gridGapWide),
            const _RecentRecordingsCard(),
          ],
        ],
      ),
    );
  }
}

/// "Uy vazifalari" — what this student owes, across all their lessons.
///
/// Renders nothing at all when there is no homework rather than an empty
/// panel: a card that says "nothing here" on a dashboard that already has
/// four is noise, and a student with no homework does not need telling.
class _HomeworkCard extends ConsumerWidget {
  const _HomeworkCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(myAssignmentsProvider).value ?? const [];
    final open = assignments.where((a) => !a.submitted).toList();
    if (assignments.isEmpty) return const SizedBox.shrink();

    final now = hkNow();
    return Padding(
      padding: const EdgeInsets.only(top: HkSpace.gridGapWide),
      child: GlassPanel(
        radius: HkRadius.cardLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Uy vazifalari', style: HkType.sectionTitle),
                ),
                if (open.isNotEmpty)
                  HkPill(
                    label: '${open.length} ta topshirilmagan',
                    background: const Color(0x26E08600),
                    foreground: HkColors.warningBright,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            for (final a in assignments) ...[
              _HomeworkRow(assignment: a, now: now),
              if (a != assignments.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeworkRow extends ConsumerWidget {
  const _HomeworkRow({required this.assignment, required this.now});

  final Assignment assignment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = assignment;
    final overdue = a.isOverdueAt(now);
    final compact = HkLayout.of(context).isCompact;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a.title, style: HkType.cardTitle.copyWith(fontSize: 13.5)),
        const SizedBox(height: 3),
        Text(
          [
            if (a.lessonTitle != null) a.lessonTitle!,
            if (a.dueAt != null)
              '${DateFormat('d-MMMM', 'uz').format(a.dueAt!)} gacha',
          ].join(' · '),
          style: HkType.muted,
        ),
        if (a.body != null) ...[
          const SizedBox(height: 6),
          Text(
            a.body!,
            style: HkType.body.copyWith(fontSize: 12.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        // What the teacher handed out with it. `ol_materials` has been read
        // by the recording screen since the first migration and there are no
        // recordings, so a worksheet was effectively invisible; this is the
        // screen a student is actually looking at when they do the homework.
        if (a.lessonId != null) _TeacherMaterials(lessonId: a.lessonId!),
        // What they attached, named back to them. An upload with no
        // acknowledgement is a student wondering whether the photograph went
        // and sending it a second time to be sure.
        if (a.fileName != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                size: 14,
                color: HkColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  a.fileName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HkType.muted,
                ),
              ),
            ],
          ),
        ],
        if (a.feedback != null && a.feedback!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'O‘qituvchi: ${a.feedback}',
            style: HkType.body.copyWith(
              fontSize: 12.5,
              color: HkColors.lime,
            ),
          ),
        ],
      ],
    );

    final trailing = <Widget>[
      // A mark, once there is one. The teacher's grade dialog collects a
      // score and a comment and wrote them where nobody could read them —
      // the student's side of that screen did not exist.
      if (a.isGraded)
        HkPill(
          label: '${a.grade} ball',
          background: const Color(0x26D4E94C),
          foreground: HkColors.lime,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        )
      else if (a.submitted)
        const HkPill(
          label: 'Tekshirilmoqda',
          background: Color(0x2634C77B),
          foreground: HkColors.successBright,
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        )
      else ...[
        if (overdue)
          const HkPill(
            label: 'Muddati o‘tgan',
            background: Color(0x26DC2626),
            foreground: HkColors.dangerBright,
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          ),
        LimeButton(
          label: 'Topshirish',
          onPressed: () async {
            final sent = await showSubmitAssignmentDialog(context, a);
            if (sent == true) ref.invalidate(myAssignmentsProvider);
          },
        ),
      ],
    ];

    return GlassPanel(
      radius: HkRadius.cardSmall,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      tint: overdue ? const Color(0x14DC2626) : null,
      // Stacked on a phone. Side by side, the title, the deadline, an overdue
      // badge and a button do not fit across 390pt — and 'Topshirish' is the
      // one control on the card, so it is not the thing to let overflow.
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 8, children: trailing),
              ],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 12),
                Wrap(spacing: 10, children: trailing),
              ],
            ),
    );
  }
}

/// The teacher's handouts for the lesson this homework belongs to.
///
/// Silent in every state but one: no spinner while it loads and no error row
/// if it fails, because it hangs under a card whose real subject is the
/// homework. A worksheet that cannot be fetched should not turn a piece of
/// homework into an error message.
class _TeacherMaterials extends ConsumerWidget {
  const _TeacherMaterials({required this.lessonId});

  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materials = ref.watch(materialsProvider(lessonId)).value ?? const [];
    if (materials.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in materials) ...[
          const SizedBox(height: 6),
          _MaterialLine(material: m),
        ],
      ],
    );
  }
}

/// One handout: named, and openable when there is something behind it.
///
/// Not a button when the row has no file — the demo fixtures have none, and
/// so does any row somebody created without a URL. A control that cannot do
/// anything is worse than a line of text that does not claim it can.
class _MaterialLine extends ConsumerWidget {
  const _MaterialLine({required this.material});

  final LessonMaterial material;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openable = material.url.isNotEmpty;

    final line = Row(
      children: [
        Icon(
          material.icon,
          size: 14,
          color: openable ? HkColors.lime : HkColors.textTertiary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            material.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: openable
                ? HkType.body.copyWith(fontSize: 12.5, color: HkColors.lime)
                : HkType.muted,
          ),
        ),
      ],
    );

    if (!openable) return line;

    return InkWell(
      onTap: () async {
        final error = await openLessonMaterial(ref, material.url);
        if (error == null || !context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: line,
    );
  }
}

/// The full-width hero: a live lesson with a lime CTA into the room.
class LiveHeroBanner extends StatefulWidget {
  const LiveHeroBanner({super.key, required this.lesson});

  final Lesson lesson;

  @override
  State<LiveHeroBanner> createState() => _LiveHeroBannerState();
}

class _LiveHeroBannerState extends State<LiveHeroBanner> {
  late Timer _tick;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _elapsed = widget.lesson.elapsedAt(hkNow());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = widget.lesson.elapsedAt(hkNow()));
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  String get _elapsedLabel {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return _elapsed.inHours > 0 ? '${_elapsed.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final layout = HkLayout.of(context);
    final lesson = widget.lesson;
    final teacher = lesson.teacher;

    final meta = Wrap(
      spacing: 18,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (teacher != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HkAvatar(
                initials: teacher.initials,
                size: 34,
                gradient: teacher.gradient,
              ),
              const SizedBox(width: 10),
              Text(teacher.fullName, style: HkType.label),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.people_alt_outlined,
              size: 15,
              color: HkColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '${lesson.enrolledCount} ta talaba ulangan',
              style: HkType.body.copyWith(fontSize: 13),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.schedule_rounded,
              size: 15,
              color: HkColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '$_elapsedLabel davom etmoqda',
              style: HkType.body.copyWith(fontSize: 13),
            ),
          ],
        ),
      ],
    );

    final cta = LimeButton(
      label: "Darsga qo'shilish",
      icon: Icons.videocam_rounded,
      height: 56,
      expand: layout.isCompact,
      onPressed: () => context.go('/live'),
    );

    return GlassPanel(
      radius: HkRadius.cardLarge,
      padding: const EdgeInsets.all(26),
      tint: const Color(0x4D2E5FA8),
      child: Stack(
        children: [
          // The soft lime glow behind the CTA corner.
          Positioned(
            right: -60,
            top: -80,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x33D4E94C), Color(0x00D4E94C)],
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  const HkPill(
                    label: 'HOZIR EFIRDA',
                    background: HkColors.lime,
                    foreground: HkColors.ink,
                    dotColor: HkColors.ink,
                    pulsingDot: true,
                  ),
                  // Only when something records. See HkEnv.recordingEnabled:
                  // the flag has been in the schema from the start and the
                  // badge drawn from it since, with nothing behind either.
                  if (HkEnv.recordingEnabled && lesson.autoRecord)
                    const HkPill(
                      label: 'Yozib olinmoqda',
                      dotColor: HkColors.danger,
                      pulsingDot: true,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                lesson.title,
                style: layout.isCompact
                    ? HkType.heroTitle.copyWith(fontSize: 22)
                    : HkType.heroTitle,
              ),
              const SizedBox(height: 16),
              if (layout.isCompact) ...[
                meta,
                const SizedBox(height: 20),
                cta,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: meta),
                    const SizedBox(width: 20),
                    cta,
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoLiveBanner extends StatelessWidget {
  const _NoLiveBanner();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: HkRadius.cardLarge,
      padding: const EdgeInsets.all(26),
      child: Row(
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            color: HkColors.textTertiary,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hozir jonli dars yo‘q',
                  style: HkType.sectionTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  "Keyingi dars boshlanganda bu yerda ko'rinadi.",
                  style: HkType.body.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The four numbers across the top of the student's home.
///
/// Drawn with the design system's own card. There was a second, private copy
/// of [HkStatCard] here — the exact drift that widget's comment says it
/// exists to prevent — and it had already fallen a fix behind: on a phone
/// every label on this screen still read "O'rtacha davo…" after the shared
/// one had been widened.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return HkStatRow(
      cards: [
        HkStatCard(
          label: 'Bugungi darslar',
          value: '${stats.lessonsToday}',
          icon: Icons.event_note_rounded,
          note: 'Bugun rejalashtirilgan',
        ),
        HkStatCard(
          label: 'Faol talabalar',
          value: '${stats.activeStudents}',
          icon: Icons.people_alt_rounded,
          note: "So'nggi 30 kun",
        ),
        HkStatCard(
          label: "O'rtacha davomat",
          value: '${(stats.averageAttendance * 100).round()}%',
          icon: Icons.trending_up_rounded,
          note: 'Yakunlangan darslar bo\u2018yicha',
          highlight: true,
        ),
        HkStatCard(
          label: 'Yozuvlar',
          value: '${stats.recordingCount}',
          icon: Icons.video_library_rounded,
          note: 'Arxivda mavjud',
        ),
      ],
    );
  }
}


class _TodayScheduleCard extends ConsumerWidget {
  const _TodayScheduleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassPanel(
      radius: HkRadius.cardLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bugungi jadval', style: HkType.sectionTitle),
          const SizedBox(height: 16),
          AsyncSection(
            value: ref.watch(todaysLessonsProvider),
            onRetry: () => ref.invalidate(todaysLessonsProvider),
            isEmpty: (l) => l.isEmpty,
            emptyMessage: 'Bugun dars rejalashtirilmagan',
            builder: (lessons) => Column(
              children: [
                for (final lesson in lessons) ...[
                  _ScheduleRow(lesson: lesson),
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

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final live = lesson.status == LessonStatus.live;
    // On a phone the row has ~240pt left after the time column and the accent
    // bar. A status pill such as "Rejalashtirilgan" eats 110 of them from the
    // trailing edge, which cut the lesson title down to "Koreys tili · Suhb…".
    // The title is the one thing the row exists to show, so on compact the
    // pill drops to the second line and shares it with the teacher's name.
    final compact = HkLayout.of(context).isCompact;
    final pill = HkPill(
      label: lesson.status.label,
      background: lesson.status.pillBackground,
      foreground: lesson.status.pillForeground,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: live ? const Color(0x14D4E94C) : const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        border: Border.all(
          color: live ? const Color(0x33D4E94C) : const Color(0x0FFFFFFF),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              DateFormat('HH:mm').format(lesson.startsAt),
              style: HkType.monoTime,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 3,
            height: 34,
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
                  // Two lines on a phone. Even with the whole row to itself
                  // a 320pt screen leaves about 140pt for the title, and
                  // "Koreys tili · Suhbat amaliyoti" needs 190 — so one line
                  // is an ellipsis whatever else is on the row.
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                if (compact)
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          lesson.teacher?.fullName ?? '—',
                          style: HkType.muted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      pill,
                    ],
                  )
                else
                  Text(
                    lesson.teacher?.fullName ?? '—',
                    style: HkType.muted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!compact) ...[const SizedBox(width: 10), pill],
        ],
      ),
    );
  }
}

class _RecentRecordingsCard extends ConsumerWidget {
  const _RecentRecordingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassPanel(
      radius: HkRadius.cardLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("So'nggi yozuvlar", style: HkType.sectionTitle),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.go('/recordings'),
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
            value: ref.watch(recentRecordingsProvider),
            onRetry: () => ref.invalidate(recentRecordingsProvider),
            isEmpty: (r) => r.isEmpty,
            emptyMessage: 'Yozuvlar hali mavjud emas',
            builder: (recordings) => Column(
              children: [
                for (final r in recordings) ...[
                  _MiniRecordingRow(recording: r),
                  if (r != recordings.last) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRecordingRow extends StatelessWidget {
  const _MiniRecordingRow({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go('/recordings/${recording.id}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 78,
              height: 52,
              decoration: BoxDecoration(
                gradient: recording.thumbnailGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: HkColors.lime,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 16,
                  color: HkColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recording.title,
                    style: HkType.cardTitle.copyWith(fontSize: 13.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${recording.teacher?.fullName ?? '—'} · '
                    '${DateFormat('d-MMMM', 'uz').format(recording.recordedAt)}',
                    style: HkType.muted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  HkProgressBar(
                    value: recording.progress,
                    color: recording.progressColor,
                    height: 3,
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
