import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/providers.dart';
import '../domain/models.dart';
import 'material_link.dart';
import 'submit_assignment_dialog.dart';

/// "Dars tafsiloti" — a recording with its materials, quiz and homework.
///
/// There is no player yet, and the screen says so.
///
/// It used to draw the design's play button and scrubber over a gradient —
/// a control that could be pressed for ever with no handler behind it, above
/// a position for a video that cannot be opened. Nothing records lessons yet
/// (see `HkEnv.recordingEnabled`) and there is no storage bucket to read one
/// from, so the surface states that plainly and keeps the length, which is
/// the one number on it that is real.
class LessonDetailScreen extends ConsumerWidget {
  const LessonDetailScreen({super.key, required this.recordingId});

  final String recordingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final async = ref.watch(recordingByIdProvider(recordingId));

    return AppShell(
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

class _VideoSurface extends ConsumerWidget {
  const _VideoSurface({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              // Where the play button was.
              //
              // It was a lime circle with a play triangle in it and no tap
              // handler at all: it could be clicked for ever and nothing
              // would happen. There is a file behind some of these rows now
              // — a teacher's own capture, uploaded from "Yozuvlar" — and
              // where there is one it opens, handed to whatever the machine
              // plays video with. The app still has no decoder of its own,
              // so this is a door rather than a screen, and it says which.
              if (recording.videoUrl != null &&
                  recording.videoUrl!.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(40),
                          onTap: () async {
                            final error = await openRecording(ref, recording);
                            if (error == null || !context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error)),
                            );
                          },
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: HkColors.lime,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 32,
                              color: HkColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Ochish',
                          style: HkType.body.copyWith(
                            fontSize: 12.5,
                            color: HkColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0x33000000),
                          shape: BoxShape.circle,
                          border: Border.all(color: HkGlass.border),
                        ),
                        child: const Icon(
                          Icons.videocam_off_rounded,
                          size: 28,
                          color: HkColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Ijro etish hali mavjud emas',
                        style: HkType.cardTitle,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bu yozuvga fayl biriktirilmagan. O‘qituvchi uni '
                        '“Yozuvlar” bo‘limidan qo‘shishi mumkin.',
                        textAlign: TextAlign.center,
                        style: HkType.body.copyWith(
                          fontSize: 12.5,
                          color: HkColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // The length is real — it comes off the row. A position
                    // and a progress bar would not be.
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

class _MaterialRow extends ConsumerWidget {
  const _MaterialRow({required this.material});

  final LessonMaterial material;

  String? get _sizeLabel {
    final bytes = material.sizeBytes;
    if (bytes == null) return null;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // Through the helper, not `launchUrl` directly: a row written by
          // the set-homework dialog holds an object path in a private
          // bucket, and launching that string at the browser does nothing
          // visible at all.
          onPressed: material.url.isEmpty
              ? null
              : () async {
                  final error = await openLessonMaterial(ref, material.url);
                  if (error == null || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error)),
                  );
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
          const SizedBox(height: 10),
          // A full-width lime button reads as the thing to press, and this
          // one only ever produced a snackbar saying the module was not
          // built. The sentence is the honest version of the same news, and
          // it does not invite the tap first.
          Text(
            'Testni yechish hali mavjud emas.',
            style: HkType.muted.copyWith(fontSize: 12.5),
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
          const SizedBox(height: 10),
          // It was an apology for something that works: the dialog exists and
          // the dashboard offers the same assignment with a button that
          // hands it in. Only this copy of the card said it could not.
          if (assignment.submitted)
            Text(
              assignment.isGraded
                  ? 'Topshirilgan · ${assignment.grade} ball'
                  : 'Topshirilgan · tekshirilmoqda',
              style: HkType.muted.copyWith(fontSize: 12.5),
            )
          else
            LimeButton(
              label: 'Topshirish',
              onPressed: () async {
                final sent =
                    await showSubmitAssignmentDialog(context, assignment);
                if (sent == true) ref.invalidate(assignmentProvider(lessonId));
              },
            ),
        ],
      ),
    );
  }
}
