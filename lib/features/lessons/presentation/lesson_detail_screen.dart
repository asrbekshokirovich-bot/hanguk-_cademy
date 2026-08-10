import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/lessons_repository.dart';
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

class _VideoSurface extends ConsumerStatefulWidget {
  const _VideoSurface({required this.recording});

  final Recording recording;

  @override
  ConsumerState<_VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends ConsumerState<_VideoSurface> {
  VideoPlayerController? _controller;
  bool _initialising = false;
  String? _error;
  Duration _lastSaved = Duration.zero;

  Recording get _recording => widget.recording;

  bool get _hasVideo => (_recording.videoUrl ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_hasVideo) _open();
  }

  Future<void> _open() async {
    setState(() => _initialising = true);
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(_recording.videoUrl!));
    try {
      await controller.initialize();
      // Resume where the student stopped, which is the whole point of storing
      // progress. Within a few seconds of the end, start again from zero
      // rather than dropping them on the credits.
      final resume = Duration(
        seconds: (_recording.durationSeconds * _recording.progress).round(),
      );
      if (resume > Duration.zero &&
          resume < controller.value.duration - const Duration(seconds: 5)) {
        await controller.seekTo(resume);
      }
      controller.addListener(_onTick);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initialising = false;
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _initialising = false;
      });
    }
  }

  /// Saves the position every ten seconds of playback, not every frame: the
  /// listener fires several times a second and each save is a round trip.
  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final position = c.value.position;
    if ((position - _lastSaved).abs() < const Duration(seconds: 10)) {
      setState(() {}); // keep the scrubber moving
      return;
    }
    _lastSaved = position;
    ref.read(lessonsRepositoryProvider).saveProgress(
          _recording.id,
          position.inSeconds,
          c.value.duration.inSeconds,
        );
    setState(() {});
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      c.removeListener(_onTick);
      // One last save on the way out, so closing the screen mid-lesson does
      // not lose up to ten seconds of progress.
      if (c.value.isInitialized) {
        ref.read(lessonsRepositoryProvider).saveProgress(
              _recording.id,
              c.value.position.inSeconds,
              c.value.duration.inSeconds,
            );
      }
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final duration = ready
        ? c.value.duration
        : Duration(seconds: _recording.durationSeconds);
    final position = ready
        ? c.value.position
        : Duration(
            seconds: (_recording.durationSeconds * _recording.progress).round(),
          );

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HkRadius.card),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: _recording.thumbnailGradient),
          child: Stack(
            children: [
              if (ready) Positioned.fill(child: VideoPlayer(c)),
              Positioned(
                right: 14,
                top: 14,
                child: HkPill(
                  label: 'Yozuv',
                  background: const Color(0x66000000),
                  foreground: HkColors.textPrimary,
                ),
              ),
              Center(child: _centrepiece(ready)),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Row(
                  children: [
                    Text(
                      _fmt(position),
                      style: HkType.monoTime.copyWith(fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ready
                          ? SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 5,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                activeTrackColor: HkColors.lime,
                                inactiveTrackColor: const Color(0x33FFFFFF),
                                thumbColor: HkColors.lime,
                              ),
                              child: Slider(
                                value: position.inMilliseconds
                                    .clamp(0, duration.inMilliseconds)
                                    .toDouble(),
                                max: duration.inMilliseconds.toDouble(),
                                onChanged: (v) => c.seekTo(
                                  Duration(milliseconds: v.round()),
                                ),
                              ),
                            )
                          : HkProgressBar(
                              value: _recording.progress,
                              height: 5,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _fmt(duration),
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

  Widget _centrepiece(bool ready) {
    if (_initialising) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }
    if (!_hasVideo || _error != null) {
      // Says which of the two it is. Most recordings in this system have no
      // file yet, and "yuklanmadi" for those would send the owner hunting for
      // a fault that is not there.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          _hasVideo ? 'Video yuklanmadi' : 'Bu darsning yozuvi hali yo‘q',
          textAlign: TextAlign.center,
          style: HkType.body.copyWith(fontSize: 13),
        ),
      );
    }

    final playing = ready && _controller!.value.isPlaying;
    return GestureDetector(
      onTap: () {
        final c = _controller;
        if (c == null) return;
        playing ? c.pause() : c.play();
        setState(() {});
      },
      child: Container(
        width: 74,
        height: 74,
        decoration: const BoxDecoration(
          color: HkColors.lime,
          shape: BoxShape.circle,
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 40,
          color: HkColors.ink,
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
