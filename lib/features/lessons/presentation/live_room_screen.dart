import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart'
    show VideoTrack, VideoTrackRenderer;

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../staff/data/staff_providers.dart';
import '../data/lessons_repository.dart';
import '../data/live_media.dart';
import '../data/providers.dart';
import '../domain/models.dart';
import '../../../core/clock.dart';

/// "Jonli dars" — the live lesson room.
///
/// The room chrome is complete and driven by real lesson data: who is
/// teaching, how long it has been running, whether it is being recorded.
///
/// The participant list and the chat are real: presence is a heartbeat in
/// `ol_room_presence`, messages stream out of `ol_chat_messages`, and both
/// update live for everyone in the room.
///
/// Camera and microphone run over LiveKit, joined with a token the database
/// signs — see `LiveMediaSession` and `20260918140000_livekit_tokens.sql`.
/// Media is the one part of the room allowed to fail on its own: a project
/// with no LiveKit credentials, or a network that blocks it, still gets a
/// working lesson with chat and a participant list, and the notice at the top
/// says which of the two is happening.
class LiveRoomScreen extends ConsumerStatefulWidget {
  const LiveRoomScreen({super.key, this.lessonId});

  /// Which lesson's room this is. Null on the dock's `/live` — "whatever is
  /// on air" — which is the right question for a student, who attends one
  /// class at a time. A teacher opens their own room by id: on a day when two
  /// lessons are running, "whatever is on air" is somebody else's.
  final String? lessonId;

  @override
  ConsumerState<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends ConsumerState<LiveRoomScreen> {
  bool _micOn = false;
  bool _cameraOn = false;
  bool _handRaised = false;
  bool _showChat = true;
  bool _showCaptions = true;
  bool _ending = false;

  /// Which room this state has announced itself into, so the heartbeat knows
  /// what to refresh and `dispose` knows what to leave. Held separately from
  /// `widget.lessonId`, which is null on the dock's bare `/live` — the room
  /// there is whichever lesson turned out to be on air.
  String? _joinedLessonId;
  Timer? _heartbeat;

  /// The camera/microphone connection. Created once and kept across rebuilds:
  /// a media session torn down by a rebuild would reconnect every time the
  /// chat received a message.
  final LiveMediaSession _media = LiveMediaSession();

  @override
  void initState() {
    super.initState();
    _media.addListener(_onMediaChanged);
    // Ends anything that ran past its slot. Cheap, and it runs here because
    // opening the room is the moment a stale "live" lesson actually gets in
    // someone's way: `/live` would otherwise show last Tuesday's class.
    Future.microtask(
      () => ref.read(lessonsRepositoryProvider).endStaleLessons(),
    );
  }

  void _onMediaChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _media.removeListener(_onMediaChanged);
    _media.dispose();
    _heartbeat?.cancel();
    final left = _joinedLessonId;
    if (left != null) {
      // Not awaited: dispose cannot be async, and the heartbeat cutoff covers
      // this row within the minute even if the request never lands.
      ref.read(lessonsRepositoryProvider).leaveRoom(left);
    }
    super.dispose();
  }

  /// Joins the room once the live lesson is known, then keeps the heartbeat
  /// going. Called from `build`, which is where the lesson first becomes
  /// available — guarded so it happens once per room.
  void _ensureJoined(Lesson lesson) {
    if (_joinedLessonId == lesson.id) return;

    final previous = _joinedLessonId;
    _joinedLessonId = lesson.id;
    _heartbeat?.cancel();

    final repo = ref.read(lessonsRepositoryProvider);
    if (previous != null) repo.leaveRoom(previous);
    repo.enterRoom(lesson.id, micOn: _micOn, handRaised: _handRaised);

    // Media is asked for separately and is allowed to fail. Presence and chat
    // are what make the room usable; video is what makes it good.
    unawaited(() async {
      try {
        final grant = await repo.liveMediaGrant(lesson.id);
        if (!mounted || _joinedLessonId != lesson.id) return;
        await _media.connect(grant);
      } catch (_) {
        if (mounted) await _media.connect(null);
      }
    }());

    // Half the 75-second cutoff, so one dropped request is not enough to make
    // someone vanish from the list they are sitting in.
    _heartbeat = Timer.periodic(
      const Duration(seconds: 30),
      (_) => repo.enterRoom(lesson.id),
    );
  }

  /// Mirrors a control-bar toggle into the room, so the other participants
  /// see it. Local state changes either way — a failed write should not leave
  /// the button disagreeing with the finger that pressed it.
  void _pushPresence() {
    final id = _joinedLessonId;
    if (id == null) return;
    ref
        .read(lessonsRepositoryProvider)
        .enterRoom(id, micOn: _micOn, handRaised: _handRaised);
  }

  /// Leaves deliberately, as opposed to closing the window. Distinct from
  /// [_end]: this takes *you* out of the room and leaves the lesson running.
  Future<void> _leave() async {
    final id = _joinedLessonId;
    _heartbeat?.cancel();
    _heartbeat = null;
    _joinedLessonId = null;
    await _media.leave();
    if (id != null) {
      await ref.read(lessonsRepositoryProvider).leaveRoom(id);
    }
    if (!mounted) return;
    context.go('/');
  }

  /// Takes the lesson off air, after asking. Ending is visible to everyone in
  /// the room and there is no undo button next to it, so the confirmation is
  /// not ceremony — "Chiqish" sits one button away and does something very
  /// different.
  Future<void> _end(Lesson lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF00C1430),
        title: const Text('Darsni tugatish', style: HkType.cardTitle),
        content: Text(
          '“${lesson.title}” yakunlanadi. Dars efirdan olinadi va barcha '
          'ishtirokchilar uchun tugaydi.',
          style: HkType.body.copyWith(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Bekor qilish'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Tugatish',
              style: TextStyle(color: HkColors.dangerBright),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _ending = true);
    try {
      await _media.leave();
      await setLessonStatus(ref, lesson.id, LessonStatus.ended);
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _ending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Darsni tugatib bo‘lmadi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = HkLayout.of(context);
    final id = widget.lessonId;
    final found = id == null
        ? ref.watch(liveLessonProvider).value
        : ref.watch(lessonByIdProvider(id)).value;

    // A named room that is no longer on air is the same screen as no room at
    // all. Leaving the chrome up around an ended lesson is how a teacher ends
    // up talking into a room everyone else has left.
    final lesson =
        found?.status == LessonStatus.live ? found : null;

    // Students leave; whoever is running the lesson ends it. The router does
    // not gate `/live` by role — every role belongs in a lesson — so this is
    // the one place the distinction is drawn, and `ol_lessons_write` draws it
    // again on the way to the database.
    final canEnd = lesson != null && ownsLesson(ref, lesson);

    // Announce ourselves as soon as we know which room this is. Deferred out
    // of the build phase: joining writes to a provider, and a provider write
    // during build is the classic Riverpod assertion.
    if (lesson != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureJoined(lesson);
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
                _MediaNotice(media: _media),
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
                            media: _media,
                          ),
                        ),
                        const SizedBox(width: HkSpace.gridGap),
                        SizedBox(
                          width: 330,
                          child: _RightRail(
                            showChat: _showChat,
                            lessonId: lesson.id,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  SizedBox(
                    height: 360,
                    child: _Stage(
                      lesson: lesson,
                      showCaptions: _showCaptions,
                      media: _media,
                    ),
                  ),
                  const SizedBox(height: HkSpace.gridGap),
                  SizedBox(
                    height: 420,
                    child: _RightRail(
                      showChat: _showChat,
                      lessonId: lesson.id,
                    ),
                  ),
                ],
                const SizedBox(height: HkSpace.gridGap),
                _ControlBar(
                  onEnd: canEnd ? () => _end(lesson) : null,
                  ending: _ending,
                  micOn: _micOn,
                  cameraOn: _cameraOn,
                  handRaised: _handRaised,
                  chatOn: _showChat,
                  captionsOn: _showCaptions,
                  onMic: () {
                    final next = !_micOn;
                    setState(() => _micOn = next);
                    _media.setMicrophone(next);
                    _pushPresence();
                  },
                  onCamera: () {
                    final next = !_cameraOn;
                    setState(() => _cameraOn = next);
                    _media.setCamera(next);
                  },
                  onHand: () {
                    setState(() => _handRaised = !_handRaised);
                    _pushPresence();
                  },
                  onChat: () => setState(() => _showChat = !_showChat),
                  onCaptions: () =>
                      setState(() => _showCaptions = !_showCaptions),
                  onLeave: _leave,
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

/// States plainly that audio/video is not live yet. Without it, a student
/// pressing an inert mic button would reasonably conclude the app is broken.
/// The one line at the top of the room that says what the media is doing.
///
/// It exists because the three failure modes look identical on screen and
/// need completely different responses: nothing configured (an admin task),
/// a connection that failed (a network or a token), and a room where simply
/// nobody has switched a camera on (nothing is wrong at all). Shown only when
/// there is something to say — a connected room gets its screen back.
class _MediaNotice extends StatelessWidget {
  const _MediaNotice({required this.media});

  final LiveMediaSession media;

  @override
  Widget build(BuildContext context) {
    final (String? text, Color tint, Color border, Color icon) =
        switch (media.status) {
      LiveMediaStatus.connected => (null, Colors.transparent,
          Colors.transparent, Colors.transparent),
      LiveMediaStatus.connecting => (
          'Video ulanmoqda…',
          const Color(0x1A3B82F6),
          const Color(0x333B82F6),
          HkColors.textSecondary,
        ),
      LiveMediaStatus.unavailable => (
          "Video va audio bu loyihada sozlanmagan. Suhbat va ishtirokchilar "
              "ro'yxati ishlaydi.",
          const Color(0x1AE08600),
          const Color(0x33E08600),
          HkColors.warningBright,
        ),
      LiveMediaStatus.failed => (
          'Videoga ulanib bo‘lmadi: ${media.error ?? "noma’lum xato"}',
          const Color(0x1ADC2626),
          const Color(0x33DC2626),
          HkColors.dangerBright,
        ),
      LiveMediaStatus.idle => (
          'Video tayyorlanmoqda…',
          const Color(0x1A3B82F6),
          const Color(0x333B82F6),
          HkColors.textSecondary,
        ),
    };

    if (text == null) return const SizedBox.shrink();

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      radius: HkRadius.cardSmall,
      tint: tint,
      borderColor: border,
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: HkType.body.copyWith(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _Stage extends StatefulWidget {
  const _Stage({
    required this.lesson,
    required this.showCaptions,
    required this.media,
  });

  final Lesson lesson;
  final bool showCaptions;
  final LiveMediaSession media;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
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

  @override
  Widget build(BuildContext context) {
    final teacher = widget.lesson.teacher;
    final compact = HkLayout.of(context).isCompact;
    final VideoTrack? stageTrack = widget.media.stageTrack;

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
            // Whoever is on camera, or the avatar when nobody is.
            //
            // The avatar is not a placeholder to be embarrassed about: most
            // of a language lesson is audio, and a stage that goes black the
            // moment the teacher turns their camera off would look broken.
            if (stageTrack != null)
              Positioned.fill(
                // Default fit is contain, which is what a shared screen or a
                // slide needs — cover would crop the edges off a whiteboard.
                child: VideoTrackRenderer(stageTrack),
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

class _RightRail extends ConsumerWidget {
  const _RightRail({required this.showChat, required this.lessonId});

  final bool showChat;
  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value` and not `.when`: presence arrives a moment after the room does,
    // and a spinner where the participant list goes would flash on every
    // single open. An empty list for that moment reads as "nobody yet", which
    // is both true and what it turns into anyway.
    final participants =
        ref.watch(roomParticipantsProvider(lessonId)).value ?? const [];

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
              // Counted, not asserted. The old pill said "Davomat 100%"
              // unconditionally, which was a fixture talking: it read as a
              // measurement and was in fact a constant.
              HkPill(
                label: participants.isEmpty
                    ? 'Bo‘sh'
                    : '${participants.where((p) => p.handRaised).length} qo‘l',
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
            child: participants.isEmpty
                ? Center(
                    child: Text(
                      'Hali hech kim qo‘shilmadi',
                      style: HkType.muted.copyWith(fontSize: 12),
                    ),
                  )
                : ListView.separated(
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
            Expanded(flex: 2, child: _ChatList(lessonId: lessonId)),
            const SizedBox(height: 10),
            _ChatComposer(lessonId: lessonId),
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

class _ChatList extends ConsumerStatefulWidget {
  const _ChatList({required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<_ChatList> {
  final _controller = ScrollController();
  int _seen = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Keeps the newest message in view, but only when the reader was already
  /// at the bottom. Yanking the list down while someone is scrolling back
  /// through what was said is how a chat becomes unreadable during a busy
  /// moment — which is exactly when people scroll back.
  void _followTail(int count) {
    if (count == _seen) return;
    final grew = count > _seen;
    _seen = count;
    if (!grew || !_controller.hasClients) return;

    final position = _controller.position;
    final atBottom = position.pixels >= position.maxScrollExtent - 80;
    if (!atBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(roomChatProvider(widget.lessonId));

    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // The error is shown, not swallowed. A chat that silently renders empty
      // when the policy rejects the read looks identical to a quiet lesson,
      // and the two need very different responses.
      error: (e, _) => Center(
        child: Text(
          'Suhbatni yuklab bo‘lmadi:\n$e',
          textAlign: TextAlign.center,
          style: HkType.muted.copyWith(fontSize: 11.5),
        ),
      ),
      data: (messages) {
        _followTail(messages.length);

        if (messages.isEmpty) {
          return Center(
            child: Text(
              'Xabarlar yo‘q',
              style: HkType.muted.copyWith(fontSize: 12),
            ),
          );
        }

        return ListView.separated(
          controller: _controller,
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
                        m.isSelf ? 'Siz' : m.author,
                        style: HkType.chip.copyWith(
                          color: m.isSelf
                              ? HkColors.lime
                              : HkColors.textPrimary,
                        ),
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
      },
    );
  }
}

class _ChatComposer extends ConsumerStatefulWidget {
  const _ChatComposer({required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<_ChatComposer> {
  final _field = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _field.text.trim();
    if (text.isEmpty || _sending) return;

    // Cleared before the round trip, and restored if the send fails. A field
    // that stays full until the server answers makes a slow connection look
    // like a dead button, and the double-tap that follows sends it twice.
    _field.clear();
    setState(() => _sending = true);
    try {
      await ref
          .read(lessonsRepositoryProvider)
          .sendChatMessage(widget.lessonId, text);
    } catch (e) {
      if (!mounted) return;
      _field.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xabar yuborilmadi: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
              controller: _field,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              maxLength: 2000,
              style: HkType.body.copyWith(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                counterText: '',
                hintText: 'Xabar yozing…',
                hintStyle: HkType.muted.copyWith(fontSize: 12.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sending ? null : _send,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: kLimeGradient,
              shape: BoxShape.circle,
              // Dimmed while in flight rather than swapped for a spinner: the
              // send is usually faster than the eye, and a control that
              // changes shape for 80ms just flickers.
              backgroundBlendMode: _sending ? BlendMode.luminosity : null,
            ),
            child: const Icon(
              Icons.send_rounded,
              size: 17,
              color: HkColors.ink,
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
    required this.chatOn,
    required this.captionsOn,
    required this.onMic,
    required this.onCamera,
    required this.onHand,
    required this.onChat,
    required this.onCaptions,
    required this.onLeave,
    required this.onEnd,
    required this.ending,
  });

  final bool micOn;
  final bool cameraOn;
  final bool handRaised;
  final bool chatOn;
  final bool captionsOn;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onHand;
  final VoidCallback onChat;
  final VoidCallback onCaptions;
  final VoidCallback onLeave;

  /// Null for a student: they can leave the room, but only staff take the
  /// lesson off air for everyone.
  final VoidCallback? onEnd;
  final bool ending;

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
            // Leaving is the red button only when it is the only way out of
            // the room. For staff the red belongs on "Darsni tugatish" — that
            // is the one that ends the lesson for sixty other people — and
            // leaving steps back to a quiet outline so the two are not two
            // identical red buttons side by side.
            SizedBox(
              height: 50,
              child: onEnd == null
                  ? FilledButton.icon(
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
                    )
                  : OutlinedButton.icon(
                      onPressed: onLeave,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HkColors.textSecondary,
                        side: const BorderSide(color: HkGlass.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(HkRadius.pill),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'Chiqish',
                        style: TextStyle(
                          fontFamily: HkType.family,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
            if (onEnd != null)
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: ending ? null : onEnd,
                  style: FilledButton.styleFrom(
                    backgroundColor: HkColors.danger,
                    disabledBackgroundColor: HkColors.danger.withValues(
                      alpha: 0.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HkRadius.pill),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text(
                    ending ? 'Tugatilmoqda…' : 'Darsni tugatish',
                    style: const TextStyle(
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
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
    );
  }
}
