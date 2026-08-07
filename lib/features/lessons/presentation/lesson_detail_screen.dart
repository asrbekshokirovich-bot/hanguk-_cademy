import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/command_dock.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/providers.dart';
import '../domain/models.dart';

/// "Dars tafsiloti" — a recording with its materials, quiz and homework.
///
/// The player itself is a placeholder surface: it renders the scrubber, times
/// and controls from the design, but does not decode video. Playback lands
/// with the media milestone alongside the live room; wiring a player here
/// before the recordings have real `video_url`s would only hide that.
class LessonDetailScreen extends ConsumerWidget {
  const LessonDetailScreen({super.key, required this.recordingId});

  final String recordingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final async = ref.watch(recordingByIdProvider(recordingId));

    return AppShell(
      destination: HkDestination.recordings,
      title: 'Dars tafsiloti',
      subtitle: 'Yozuv, materiallar va test',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackLink(onTap: () => context.go('/recordings')),
          const SizedBox(height: 18),
          AsyncSection(
            value: async,
            onRetry: () => ref.invalidate(recordingByIdProvider(recordingId)),
            loadingHeight: 360,
            isEmpty: (r) => r == null,
            emptyMessage: 'Yozuv topilmadi',
            builder: (recording) {
              final r = recording!;
              final left = _PlayerColumn(recording: r);
              final right = _SideColumn(recording: r);

              if (layout.isExpanded) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: HkSpace.gridGapWide),
                    SizedBox(width: 360, child: right),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  left,
                  const SizedBox(height: HkSpace.gridGapWide),
                  right,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_back_rounded,
              size: 16,
              color: HkColors.textSecondary,
            ),
            SizedBox(width: 8),
            Text(
              'Yozuvlarga qaytish',
              style: TextStyle(
                fontFamily: HkType.family,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HkColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerColumn extends StatefulWidget {
  const _PlayerColumn({required this.recording});

  final Recording recording;

  @override
  State<_PlayerColumn> createState() => _PlayerColumnState();
}

class _PlayerColumnState extends State<_PlayerColumn> {
  int _tab = 0;
  static const _tabs = ['Tavsif', 'Transkript', 'Izohlar'];

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VideoSurface(recording: r),
        const SizedBox(height: 20),
        Text(r.title, style: HkType.pageTitle),
        const SizedBox(height: 14),
        Wrap(
          spacing: 18,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (r.teacher != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HkAvatar(
                    initials: r.teacher!.initials,
                    size: 32,
                    gradient: r.teacher!.gradient,
                  ),
                  const SizedBox(width: 10),
                  Text(r.teacher!.fullName, style: HkType.label),
                ],
              ),
            Text(
              DateFormat('d-MMMM y', 'uz').format(r.recordedAt),
              style: HkType.body.copyWith(fontSize: 13),
            ),
            if (r.attendeeCount > 0)
              Text(
                '${r.attendeeCount} ta talaba qatnashdi',
                style: HkType.body.copyWith(fontSize: 13),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              _Tab(
                label: _tabs[i],
                active: i == _tab,
                onTap: () => setState(() => _tab = i),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 16),
        GlassPanel(
          child: SizedBox(
            width: double.infinity,
            child: Text(
              switch (_tab) {
                0 => r.description ?? 'Bu dars uchun tavsif kiritilmagan.',
                1 => 'Transkript tayyorlanmoqda.',
                _ => 'Hozircha izohlar yo‘q.',
              },
              style: HkType.body,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: active ? const Color(0x1FFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(HkRadius.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: HkType.family,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? HkColors.textPrimary : HkColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    // Scrubber position follows the student's saved watch progress rather than
    // the design's fixed 19%, so reopening a half-watched lesson looks right.
    final position = Duration(
      seconds: (recording.durationSeconds * recording.progress).round(),
    );

    String fmt(Duration d) {
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HkRadius.card),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: recording.thumbnailGradient),
          child: Stack(
            children: [
              Positioned(
                right: 14,
                top: 14,
                child: HkPill(
                  label: 'Yozuv',
                  background: const Color(0x66000000),
                  foreground: HkColors.textPrimary,
                ),
              ),
              Center(
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: const BoxDecoration(
                    color: HkColors.lime,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 40,
                    color: HkColors.ink,
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Row(
                  children: [
                    Text(
                      fmt(position),
                      style: HkType.monoTime.copyWith(fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HkProgressBar(
                        value: recording.progress,
                        height: 5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      fmt(Duration(seconds: recording.durationSeconds)),
                      style: HkType.monoTime.copyWith(
                        fontSize: 12,
                        color: HkColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideColumn extends ConsumerWidget {
  const _SideColumn({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessonId = recording.lessonId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassPanel(
          radius: HkRadius.cardLarge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Materiallar', style: HkType.sectionTitle),
              const SizedBox(height: 14),
              if (lessonId == null)
                Text(
                  'Bu yozuvga material biriktirilmagan.',
                  style: HkType.body.copyWith(fontSize: 13),
                )
              else
                AsyncSection(
                  value: ref.watch(materialsProvider(lessonId)),
                  onRetry: () =>
                      ref.invalidate(materialsProvider(lessonId)),
                  loadingHeight: 80,
                  isEmpty: (m) => m.isEmpty,
                  emptyMessage: 'Material yo‘q',
                  builder: (materials) => Column(
                    children: [
                      for (final m in materials) ...[
                        _MaterialRow(material: m),
                        if (m != materials.last) const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HkSpace.gridGap),
        if (lessonId != null) ...[
          _QuizCard(lessonId: lessonId),
          const SizedBox(height: HkSpace.gridGap),
          _HomeworkCard(lessonId: lessonId),
        ],
      ],
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({required this.material});

  final LessonMaterial material;

  String? get _sizeLabel {
    final bytes = material.sizeBytes;
    if (bytes == null) return null;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(material.icon, size: 18, color: HkColors.textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                material.name,
                style: HkType.cardTitle.copyWith(fontSize: 13.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_sizeLabel != null) ...[
                const SizedBox(height: 2),
                Text(_sizeLabel!, style: HkType.muted),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: 'Yuklab olish',
          onPressed: material.url.isEmpty
              ? null
              : () {
                  final uri = Uri.tryParse(material.url);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
          icon: const Icon(
            Icons.download_rounded,
            size: 18,
            color: HkColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _QuizCard extends ConsumerWidget {
  const _QuizCard({required this.lessonId});

  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quiz = ref.watch(quizProvider(lessonId)).value;
    if (quiz == null) return const SizedBox.shrink();

    return GlassPanel(
      radius: HkRadius.cardLarge,
      tint: const Color(0x3D1A3A6C),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quiz.title, style: HkType.sectionTitle),
          const SizedBox(height: 6),
          Text(
            '${quiz.questionCount} ta savol',
            style: HkType.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 16),
          LimeButton(
            label: quiz.completed ? 'Natijani ko‘rish' : 'Testni boshlash',
            expand: true,
            height: 46,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Test moduli keyingi bosqichda ulanadi.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeworkCard extends ConsumerWidget {
  const _HomeworkCard({required this.lessonId});

  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignment = ref.watch(assignmentProvider(lessonId)).value;
    if (assignment == null) return const SizedBox.shrink();

    return GlassPanel(
      radius: HkRadius.cardLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Uy vazifasi', style: HkType.sectionTitle),
              ),
              HkPill(
                label: assignment.statusLabel,
                background: assignment.submitted
                    ? const Color(0x2634C77B)
                    : const Color(0x26E08600),
                foreground: assignment.submitted
                    ? HkColors.successBright
                    : HkColors.warningBright,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            assignment.dueAt == null
                ? assignment.title
                : '${assignment.title} · '
                    '${DateFormat('d-MMMM', 'uz').format(assignment.dueAt!)} gacha',
            style: HkType.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Vazifa moduli keyingi bosqichda ulanadi.'),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: HkGlass.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HkRadius.cardSmall),
                ),
              ),
              child: const Text(
                'Vazifani ochish',
                style: TextStyle(
                  fontFamily: HkType.family,
                  fontWeight: FontWeight.w600,
                  color: HkColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
