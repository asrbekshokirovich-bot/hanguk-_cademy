import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../data/demo_data.dart';
import '../data/providers.dart';
import '../domain/models.dart';
import '../../../core/clock.dart';
import '../../live/data/live_session.dart';

/// "Jonli dars" — the live lesson room.
///
/// The room chrome is complete and driven by real lesson data: who is
/// teaching, how long it has been running, whether it is being recorded.
///
/// Audio and video are real: joining publishes to a LiveKit room whose token
/// is minted by the `livekit-token` Edge Function. The chat and the captions
/// strip are still seeded from `DemoData` — they are the next milestone, and
/// the room says which parts are live rather than presenting controls that
/// quietly do nothing.
class LiveRoomScreen extends ConsumerStatefulWidget {
  const LiveRoomScreen({super.key});

  @override
  ConsumerState<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends ConsumerState<LiveRoomScreen> {
  bool _handRaised = false;
  bool _showChat = true;
  bool _showCaptions = true;

  @override
  Widget build(BuildContext context) {
    final layout = HkLayout.of(context);
    final lesson = ref.watch(liveLessonProvider).value;
    final session = ref.watch(liveSessionProvider);

    // Join as soon as there is a lesson to join. Not in initState: the lesson
    // arrives asynchronously, and on a phone the user often lands here before
    // the query returns.
    if (lesson != null && session.stage == LiveStage.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(liveSessionProvider.notifier).connect(lesson.id);
      });
    }

    return AppShell(
      title: 'Jonli dars',
      subtitle: lesson?.title ?? 'Hozir efirda dars yo‘q',
      scrollable: layout.isCompact,
      child: lesson == null
          ? const _NoLiveLesson()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConnectionNotice(session: session, lessonId: lesson.id),
                const SizedBox(height: 14),
                if (layout.isExpanded)
                  // Expanded, not the design's literal 620: the shell gives
                  // this column a bounded height, and 620 + the notice + the
                  // control bar + the 150px chrome inset overflows a 920px
                  // window — the exact size the design is drawn at.
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _Stage(
                            lesson: lesson,
                            showCaptions: _showCaptions,
                          ),
                        ),
                        const SizedBox(width: HkSpace.gridGap),
                        SizedBox(
                          width: 330,
                          child: _RightRail(showChat: _showChat),
                        ),
                      ],
                    ),
                  )
                else ...[
                  SizedBox(
                    height: 360,
                    child: _Stage(lesson: lesson, showCaptions: _showCaptions),
                  ),
                  const SizedBox(height: HkSpace.gridGap),
                  SizedBox(height: 420, child: _RightRail(showChat: _showChat)),
                ],
                const SizedBox(height: HkSpace.gridGap),
                _ControlBar(
                  micOn: session.micOn,
                  cameraOn: session.cameraOn,
                  handRaised: _handRaised,
                  chatOn: _showChat,
                  captionsOn: _showCaptions,
                  // Disabled until the room is joined, rather than toggling a
                  // local boolean that publishes nothing.
                  onMic: session.isConnected
                      ? () => ref
                            .read(liveSessionProvider.notifier)
                            .setMicrophone(!session.micOn)
                      : null,
                  onCamera: session.isConnected
                      ? () => ref
                            .read(liveSessionProvider.notifier)
                            .setCamera(!session.cameraOn)
                      : null,
                  onHand: () => setState(() => _handRaised = !_handRaised),
                  onChat: () => setState(() => _showChat = !_showChat),
                  onCaptions: () =>
                      setState(() => _showCaptions = !_showCaptions),
                  onLeave: () => context.go('/'),
                ),
              ],
            ),
    );
  }
}

class _NoLiveLesson extends StatelessWidget {
  const _NoLiveLesson();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: HkRadius.cardLarge,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 26),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              size: 38,
              color: HkColors.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text('Hozir jonli dars yo‘q', style: HkType.sectionTitle),
            const SizedBox(height: 8),
            Text(
              "Keyingi darsni jadvaldan ko'rishingiz mumkin.",
              style: HkType.body.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 22),
            LimeButton(
              label: 'Jadvalga o‘tish',
              height: 46,
              onPressed: () => context.go('/schedule'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line on why the room looks the way it does: joining, joined, or a
/// reason it could not join. A student staring at a still avatar needs to
/// know whether to wait or to call the office.
class _ConnectionNotice extends ConsumerWidget {
  const _ConnectionNotice({required this.session, required this.lessonId});

  final LiveState session;
  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (tint, border, colour, icon, message) = switch (session.stage) {
      LiveStage.connecting => (
        const Color(0x1A6EA0E0),
        const Color(0x336EA0E0),
        HkColors.infoText,
        Icons.wifi_tethering_rounded,
        'Darsga ulanmoqda…',
      ),
      LiveStage.connected => (
        const Color(0x1A15A05A),
        const Color(0x3315A05A),
        HkColors.successBright,
        Icons.check_circle_outline_rounded,
        'Ulandi. Mikrofon va kamerani pastdagi tugmalardan yoqasiz.',
      ),
      LiveStage.failed => (
        const Color(0x1ADC2626),
        const Color(0x33DC2626),
        HkColors.dangerBright,
        Icons.error_outline_rounded,
        session.error ?? 'Ulanib bo‘lmadi',
      ),
      LiveStage.idle => (
        const Color(0x1AE08600),
        const Color(0x33E08600),
        HkColors.warningBright,
        Icons.info_outline_rounded,
        'Ulanish kutilmoqda',
      ),
    };

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      radius: HkRadius.cardSmall,
      tint: tint,
      borderColor: border,
      child: Row(
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: HkType.body.copyWith(fontSize: 12.5)),
          ),
          if (session.stage == LiveStage.failed)
            TextButton(
              onPressed: () =>
                  ref.read(liveSessionProvider.notifier).connect(lessonId),
              child: const Text('Qayta urinish'),
            ),
        ],
      ),
    );
  }
}

class _Stage extends ConsumerStatefulWidget {
  const _Stage({required this.lesson, required this.showCaptions});

  final Lesson lesson;
  final bool showCaptions;

  @override
  ConsumerState<_Stage> createState() => _StageState();
}

class _StageState extends ConsumerState<_Stage> {
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

  String get _clock {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return _elapsed.inHours > 0 ? '${_elapsed.inHours}:$m:$s' : '$m:$s';
  }

  /// The track the stage shows: the first remote camera in the room, and the
  /// local one only if nobody else is publishing. A teacher alone in the room
  /// still sees themselves; a student sees the teacher, not their own face.
  lk.VideoTrack? _stageTrack(lk.Room? room) {
    if (room == null) return null;

    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track != null && !publication.muted) return track;
      }
    }
    for (final publication
        in room.localParticipant?.videoTrackPublications ?? const []) {
      final track = publication.track;
      if (track != null && !publication.muted) return track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final teacher = widget.lesson.teacher;
    final compact = HkLayout.of(context).isCompact;
    final track = _stageTrack(ref.watch(liveSessionProvider).room);

    return ClipRRect(
      borderRadius: BorderRadius.circular(HkRadius.cardLarge),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [HkColors.royalBlue800, Color(0xFF05070F)],
          ),
        ),
        child: Stack(
          children: [
            // Whoever is on camera. Falls back to the initials disc while
            // nobody is publishing video — an audio-only lesson is normal
            // here, and a black rectangle would read as a failure.
            if (track != null)
              Positioned.fill(
                child: lk.VideoTrackRenderer(
                  track,
                  fit: lk.VideoViewFit.contain,
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SpeakingAvatar(
                      initials: teacher?.initials ?? '?',
                      gradient: teacher?.gradient,
                      size: compact ? 104 : 144,
                    ),
                  ],
                ),
              ),
            // Top bar
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  const HkPill(
                    label: 'LIVE',
                    background: HkColors.danger,
                    foreground: Colors.white,
                  ),
                  if (widget.lesson.autoRecord)
                    HkPill(
                      label: 'Yozib olinmoqda · $_clock',
                      dotColor: HkColors.danger,
                      pulsingDot: true,
                      foreground: HkColors.textPrimary,
                    ),
                  if (!compact)
                    HkPill(
                      label: widget.lesson.title,
                      foreground: HkColors.textSecondary,
                    ),
                ],
              ),
            ),
            // Nameplate
            if (teacher != null)
              Positioned(
                left: 16,
                bottom: 16,
                child: HkPill(
                  label: teacher.fullName,
                  icon: Icons.mic_rounded,
                  background: const Color(0x66000000),
                  foreground: HkColors.textPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
              ),
            // Captions
            if (widget.showCaptions)
              Positioned(
                left: 0,
                right: 0,
                bottom: compact ? 66 : 78,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: BorderRadius.circular(HkRadius.chip),
                    ),
                    child: Text(
                      '오늘은 자기소개를 연습하겠습니다 — Bugun o‘zini tanishtirishni mashq qilamiz.',
                      textAlign: TextAlign.center,
                      style: HkType.body.copyWith(
                        fontSize: 13,
                        color: HkColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            // Self PiP
            if (!compact)
              Positioned(
                right: 16,
                bottom: 16,
                child: Container(
                  width: 158,
                  height: 104,
                  decoration: BoxDecoration(
                    color: const Color(0x1AD4E94C),
                    borderRadius: BorderRadius.circular(HkRadius.chip),
                    border: Border.all(color: const Color(0x33D4E94C)),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Siz',
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
      ),
    );
  }
}

/// The teacher's avatar with the design's animated lime speaking ring.
class _SpeakingAvatar extends StatefulWidget {
  const _SpeakingAvatar({
    required this.initials,
    required this.size,
    this.gradient,
  });

  final String initials;
  final double size;
  final Gradient? gradient;

  @override
  State<_SpeakingAvatar> createState() => _SpeakingAvatarState();
}

class _SpeakingAvatarState extends State<_SpeakingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        return SizedBox(
          width: widget.size * 1.6,
          height: widget.size * 1.6,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Two rings, offset in phase, expanding outward and fading.
              for (final phase in [0.0, 0.5])
                Opacity(
                  opacity: (1 - ((t + phase) % 1)) * 0.5,
                  child: Container(
                    width: widget.size * (1 + ((t + phase) % 1) * 0.55),
                    height: widget.size * (1 + ((t + phase) % 1) * 0.55),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: HkColors.lime.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              child!,
            ],
          ),
        );
      },
      child: HkAvatar(
        initials: widget.initials,
        size: widget.size,
        gradient: widget.gradient,
      ),
    );
  }
}

class _RightRail extends StatelessWidget {
  const _RightRail({required this.showChat});

  final bool showChat;

  @override
  Widget build(BuildContext context) {
    final participants = DemoData.participants();

    return GlassPanel(
      radius: HkRadius.cardLarge,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ishtirokchilar · ${participants.length}',
                  style: HkType.sectionTitle.copyWith(fontSize: 14),
                ),
              ),
              const HkPill(
                label: 'Davomat 100%',
                background: Color(0x2634C77B),
                foreground: HkColors.successBright,
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: showChat ? 3 : 1,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: participants.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) =>
                  _ParticipantRow(participant: participants[i]),
            ),
          ),
          if (showChat) ...[
            const Divider(color: HkGlass.border, height: 24),
            const Text('Suhbat', style: HkType.sectionTitle),
            const SizedBox(height: 10),
            Expanded(flex: 2, child: _ChatList()),
            const SizedBox(height: 10),
            const _ChatComposer(),
          ],
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    return Row(
      children: [
        HkAvatar(initials: p.initials, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  p.name,
                  style: HkType.label.copyWith(fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (p.roleLabel != null) ...[
                const SizedBox(width: 6),
                Text(p.roleLabel!, style: HkType.muted.copyWith(fontSize: 11)),
              ],
            ],
          ),
        ),
        if (p.handRaised)
          const HkPill(
            label: "Qo'l",
            background: Color(0x26D4E94C),
            foreground: HkColors.lime,
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          )
        else
          Icon(
            p.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            size: 16,
            color: p.micOn ? HkColors.lime : HkColors.dangerBright,
          ),
      ],
    );
  }
}

class _ChatList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final messages = DemoData.chat();
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final m = messages[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    m.author,
                    style: HkType.chip.copyWith(color: HkColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('HH:mm').format(m.sentAt),
                  style: HkType.muted.copyWith(fontSize: 10.5),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(m.text, style: HkType.body.copyWith(fontSize: 12.5)),
          ],
        );
      },
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(HkRadius.pill),
              border: Border.all(color: HkGlass.border),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              // Sending is part of the media milestone; the field is left
              // enabled so the layout is real, but nothing is delivered yet.
              enabled: false,
              style: HkType.body.copyWith(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Xabar yozing…',
                hintStyle: HkType.muted.copyWith(fontSize: 12.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            gradient: kLimeGradient,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.send_rounded, size: 17, color: HkColors.ink),
        ),
      ],
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.micOn,
    required this.cameraOn,
    required this.handRaised,
    required this.chatOn,
    required this.captionsOn,
    required this.onMic,
    required this.onCamera,
    required this.onHand,
    required this.onChat,
    required this.onCaptions,
    required this.onLeave,
  });

  final bool micOn;
  final bool cameraOn;
  final bool handRaised;
  final bool chatOn;
  final bool captionsOn;
  final VoidCallback? onMic;
  final VoidCallback? onCamera;
  final VoidCallback onHand;
  final VoidCallback onChat;
  final VoidCallback onCaptions;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassPanel(
        radius: HkRadius.pill,
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ControlButton(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              active: micOn,
              tooltip: micOn ? 'Mikrofonni o‘chirish' : 'Mikrofonni yoqish',
              onTap: onMic,
            ),
            _ControlButton(
              icon: cameraOn
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              active: cameraOn,
              tooltip: cameraOn ? 'Kamerani o‘chirish' : 'Kamerani yoqish',
              onTap: onCamera,
            ),
            _ControlButton(
              icon: Icons.screen_share_outlined,
              tooltip: 'Ekranni ulashish',
              onTap: () {},
            ),
            _ControlButton(
              icon: Icons.pan_tool_alt_outlined,
              active: handRaised,
              tooltip: handRaised ? "Qo'lni tushirish" : "Qo'l ko'tarish",
              onTap: onHand,
            ),
            _ControlButton(
              icon: Icons.chat_bubble_outline_rounded,
              active: chatOn,
              tooltip: 'Suhbat',
              onTap: onChat,
            ),
            _ControlButton(
              icon: Icons.closed_caption_outlined,
              active: captionsOn,
              tooltip: 'Subtitrlar',
              onTap: onCaptions,
            ),
            Container(
              width: 1,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: HkGlass.border,
            ),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: onLeave,
                style: FilledButton.styleFrom(
                  backgroundColor: HkColors.danger,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(HkRadius.pill),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                icon: const Icon(Icons.call_end_rounded, size: 18),
                label: const Text(
                  'Chiqish',
                  style: TextStyle(
                    fontFamily: HkType.family,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatefulWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });

  final IconData icon;

  /// Null disables the button — the room is not joined yet, so publishing
  /// would have nowhere to go.
  final VoidCallback? onTap;
  final String tooltip;
  final bool active;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return Tooltip(
      message: widget.tooltip,
      child: Opacity(
        // Dimmed rather than hidden: the control bar keeps its shape while the
        // room is still connecting, so nothing jumps under the finger.
        opacity: disabled ? 0.4 : 1,
        child: MouseRegion(
          cursor: disabled
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: widget.active ? kLimeGradient : null,
                color: widget.active
                    ? null
                    : (_hovered ? HkGlass.hoverFill : const Color(0x0FFFFFFF)),
                borderRadius: BorderRadius.circular(HkRadius.control),
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: widget.active ? HkColors.ink : HkColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
