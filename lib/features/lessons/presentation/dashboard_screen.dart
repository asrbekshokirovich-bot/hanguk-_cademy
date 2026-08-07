import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/command_dock.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/providers.dart';
import '../domain/models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);

    return AppShell(
      destination: HkDestination.dashboard,
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
            builder: (stats) => _StatRow(stats: stats, layout: layout),
          ),
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
    _elapsed = widget.lesson.elapsedAt(DateTime.now());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = widget.lesson.elapsedAt(DateTime.now()));
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
                  if (lesson.autoRecord)
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

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats, required this.layout});

  final DashboardStats stats;
  final HkLayout layout;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _StatCard(
        label: 'Bugungi darslar',
        value: '${stats.lessonsToday}',
        icon: Icons.event_note_rounded,
        delta: 'Bugun rejalashtirilgan',
      ),
      _StatCard(
        label: 'Faol talabalar',
        value: '${stats.activeStudents}',
        icon: Icons.people_alt_rounded,
        delta: "So'nggi 30 kun",
      ),
      _StatCard(
        label: "O'rtacha davomat",
        value: '${(stats.averageAttendance * 100).round()}%',
        icon: Icons.trending_up_rounded,
        delta: 'Yakunlangan darslar bo‘yicha',
        highlight: true,
      ),
      _StatCard(
        label: 'Yozuvlar',
        value: '${stats.recordingCount}',
        icon: Icons.video_library_rounded,
        delta: 'Arxivda mavjud',
      ),
    ];

    return GridView.count(
      crossAxisCount: layout.statColumns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: HkSpace.gridGap,
      crossAxisSpacing: HkSpace.gridGap,
      childAspectRatio: layout.isCompact ? 1.45 : 1.75,
      children: cards,
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.delta,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final String delta;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      tint: highlight ? const Color(0x1AD4E94C) : null,
      borderColor: highlight ? const Color(0x3DD4E94C) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: HkType.body.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: highlight
                      ? const Color(0x33D4E94C)
                      : const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: highlight ? HkColors.lime : HkColors.textSecondary,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: HkType.display.copyWith(
                color: highlight ? HkColors.lime : HkColors.textPrimary,
              ),
            ),
          ),
          Text(
            delta,
            style: HkType.muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  lesson.teacher?.fullName ?? '—',
                  style: HkType.muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
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
