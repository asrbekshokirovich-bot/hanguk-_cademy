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
import '../data/providers.dart';
import '../domain/models.dart';
import '../../../core/clock.dart';
import '../../live/data/live_session.dart';

/// "Jonli dars" — the live lesson room.
///
/// The room chrome is complete and driven by real lesson data: who is
/// teaching, how long it has been running, whether it is being recorded.
///
/// Everything on this screen is real: audio, video and screen share go
/// through a LiveKit room whose token is minted by the `livekit-token` Edge
/// Function, and the chat and raised hands ride the same room's data channel.
/// Nothing here is a fixture.
///
/// There are no captions. The strip that used to sit over the video printed
/// one hardcoded Korean sentence no matter who was speaking, and a subtitle
/// that is always the same subtitle is worse than none.
class LiveRoomScreen extends ConsumerStatefulWidget {
  const LiveRoomScreen({super.key});

  @override
  ConsumerState<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends ConsumerState<LiveRoomScreen> {
  bool _showChat = true;

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
                          child: _Stage(lesson: lesson),
                        ),
                        const SizedBox(width: HkSpace.gridGap),
                        SizedBox(
                          width: 330,
                          child: _RightRail(
                            showChat: _showChat,
                            enrolledCount: lesson.enrolledCount,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  SizedBox(
                    height: 360,
                    child: _Stage(lesson: lesson),
                  ),
                  const SizedBox(height: HkSpace.gridGap),
                  SizedBox(
                    height: 420,
                    child: _RightRail(
                      showChat: _showChat,
                      enrolledCount: lesson.enrolledCount,
                    ),
                  ),
                ],
                const SizedBox(height: HkSpace.gridGap),
                _ControlBar(
                  micOn: session.micOn,
                  cameraOn: session.cameraOn,
                  handRaised: session.handRaised,
                  chatOn: _showChat,
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
                  onHand: session.isConnected
                      ? () => ref
                            .read(liveSessionProvider.notifier)
                            .setHandRaised(!session.handRaised)
                      : null,
                  screenOn: session.screenOn,
                  onScreen: session.isConnected
                      ? () => ref
                            .read(liveSessionProvider.notifier)
                            .setScreenShare(!session.screenOn)
                      : null,
                  onChat: () => setState(() => _showChat = !_showChat),
                  onLeave: () {
                    // Hang up before navigating. Leaving the screen alone kept
                    // the microphone published, so a teacher who walked away
                    // was still in the room.
                    ref.read(liveSessionProvider.notifier).disconnect();
                    context.go('/');
                  },
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
  const _Stage({required this.lesson});

  final Lesson lesson;

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

class _RightRail extends ConsumerWidget {
  const _RightRail({required this.showChat, required this.enrolledCount});

  final bool showChat;

  /// How many students the lesson has on the register. The attendance pill
  /// compares the room against it; it used to read a hardcoded 100%.
  final int enrolledCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(liveSessionProvider);
    final room = session.room;

    final people = <_Attendee>[
      if (room?.localParticipant != null)
        _Attendee.of(room!.localParticipant!, session.handsUp, isMe: true),
      for (final p in room?.remoteParticipants.values ??
          const <lk.RemoteParticipant>[])
        _Attendee.of(p, session.handsUp),
    ];

    // Everyone in the room minus the teacher, over everyone expected. Above
    // 100% would mean guests, so it is clamped rather than printed.
    final present = people.length > 1 ? people.length - 1 : 0;
    final attendance = enrolledCount == 0
        ? null
        : ((present / enrolledCount) * 100).clamp(0, 100).round();

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
                  'Ishtirokchilar · ${people.length}',
                  style: HkType.sectionTitle.copyWith(fontSize: 14),
                ),
              ),
              if (attendance != null)
                HkPill(
                  label: 'Davomat $attendance%',
                  background: const Color(0x2634C77B),
                  foreground: HkColors.successBright,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: showChat ? 3 : 1,
            child: people.isEmpty
                ? Center(
                    child: Text(
                      'Hali hech kim qo‘shilmagan',
                      style: HkType.muted,
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: people.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        _ParticipantRow(attendee: people[i]),
                  ),
          ),
          if (showChat) ...[
            const Divider(color: HkGlass.border, height: 24),
            const Text('Suhbat', style: HkType.sectionTitle),
            const SizedBox(height: 10),
            Expanded(flex: 2, child: _ChatList(messages: session.messages)),
            const SizedBox(height: 10),
            _ChatComposer(enabled: session.isConnected),
          ],
        ],
      ),
    );
  }
}

/// One row of the participant rail, read off the LiveKit room rather than a
/// fixture.
class _Attendee {
  const _Attendee({
    required this.name,
    required this.initials,
    required this.micOn,
    required this.handRaised,
    required this.isMe,
  });

  factory _Attendee.of(
    lk.Participant participant,
    Set<String> handsUp, {
    bool isMe = false,
  }) {
    final name = participant.name.isNotEmpty
        ? participant.name
        : (isMe ? 'Men' : 'Ishtirokchi');
    return _Attendee(
      name: name,
      initials: _initialsOf(name),
      micOn: participant.isMicrophoneEnabled(),
      handRaised: handsUp.contains(participant.identity),
      isMe: isMe,
    );
  }

  final String name;
  final String initials;
  final bool micOn;
  final bool handRaised;
  final bool isMe;

  static String _initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.attendee});

  final _Attendee attendee;

  @override
  Widget build(BuildContext context) {
    final p = attendee;
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
              if (p.isMe) ...[
                const SizedBox(width: 6),
                Text('siz', style: HkType.muted.copyWith(fontSize: 11)),
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
  const _ChatList({required this.messages});

  final List<LiveMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Text('Xabarlar yo‘q', style: HkType.muted),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      // Newest at the bottom, and the view starts there — a chat that opens
      // at the top of an hour-old conversation is read backwards.
      reverse: true,
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final m = messages[messages.length - 1 - i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    m.mine ? 'Siz' : m.author,
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

class _ChatComposer extends ConsumerStatefulWidget {
  const _ChatComposer({required this.enabled});

  final bool enabled;

  @override
  ConsumerState<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<_ChatComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    ref.read(liveSessionProvider.notifier).sendMessage(text);
    _controller.clear();
  }

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
              controller: _controller,
              enabled: widget.enabled,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              style: HkType.body.copyWith(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.enabled ? 'Xabar yozing…' : 'Ulanmagan',
                hintStyle: HkType.muted.copyWith(fontSize: 12.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: widget.enabled ? _send : null,
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.4,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                gradient: kLimeGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                size: 17,
                color: HkColors.ink,
              ),
            ),
          ),
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
    required this.screenOn,
    required this.chatOn,
    required this.onMic,
    required this.onCamera,
    required this.onHand,
    required this.onScreen,
    required this.onChat,
    required this.onLeave,
  });

  final bool micOn;
  final bool cameraOn;
  final bool handRaised;
  final bool screenOn;
  final bool chatOn;
  final VoidCallback? onMic;
  final VoidCallback? onCamera;
  final VoidCallback? onHand;
  final VoidCallback? onScreen;
  final VoidCallback onChat;
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
              icon: screenOn
                  ? Icons.stop_screen_share_outlined
                  : Icons.screen_share_outlined,
              active: screenOn,
              tooltip: screenOn
                  ? 'Ekranni ulashishni to‘xtatish'
                  : 'Ekranni ulashish',
              onTap: onScreen,
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
