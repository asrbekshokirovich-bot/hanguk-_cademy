import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart'
    show VideoTrack, VideoTrackRenderer, VideoViewFit;

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
import '../../../core/env.dart';

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
  /// Read off the media session rather than kept beside it.
  ///
  /// These were local booleans flipped on tap, which made the control bar a
  /// statement of intent rather than of fact. A refused microphone left the
  /// button lit and sent `mic_on: true` to `ol_room_presence`, so everyone
  /// else in the room saw a live microphone next to a name they could not
  /// hear — and the person talking had nothing on screen telling them
  /// otherwise.
  bool get _micOn => _media.micOn;
  bool get _cameraOn => _media.cameraOn;

  bool _handRaised = false;
  bool _showChat = true;
  bool _ending = false;

  /// Which room this state has announced itself into, so the heartbeat knows
  /// what to refresh and `dispose` knows what to leave. Held separately from
  /// `widget.lessonId`, which is null on the dock's bare `/live` — the room
  /// there is whichever lesson turned out to be on air.
  String? _joinedLessonId;
  Timer? _heartbeat;

  /// Attendance, which is measured rather than marked: the room knows who is
  /// in it, so nobody has to keep a register. [_attendedBefore] is what the
  /// row already held when this sitting began — somebody who drops out and
  /// comes back must not lose the first half of their lesson — and
  /// [_sittingFrom] is when this one started.
  int _attendedBefore = 0;
  DateTime? _sittingFrom;

  /// Only students are counted. A teacher is present by definition, and
  /// averaging their perfect attendance in with the class would lift every
  /// figure on the admin dashboard by a little, for no reason.
  bool get _countsAttendance =>
      ref.read(profileProvider).value?.role == 'student';

  int get _attendedSeconds {
    final from = _sittingFrom;
    if (from == null) return _attendedBefore;
    return _attendedBefore + hkNow().difference(from).inSeconds;
  }

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
    // A no-op in demo mode, which is what the widget tests run in.
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
      final repo = ref.read(lessonsRepositoryProvider);
      // Not awaited: dispose cannot be async, and the heartbeat cutoff covers
      // the presence row within the minute even if the request never lands.
      // Attendance is sent on the same terms — it was banked 30 seconds ago
      // at worst, so losing this one costs half a minute of one lesson.
      if (_sittingFrom != null) repo.recordAttendance(left, _attendedSeconds);
      repo.leaveRoom(left);
    }
    super.dispose();
  }

  /// Joins the room once the live lesson is known, then keeps the heartbeat
  /// going. Called from `build`, which is where the lesson first becomes
  /// available — guarded so it happens once per room.
  void _ensureJoined(Lesson lesson) {
    if (_joinedLessonId == lesson.id) return;

    final repo = ref.read(lessonsRepositoryProvider);

    // Demo mode has no room to join: the participants and the chat are
    // fixtures, and there is no backend to tell that anyone arrived. Leaving
    // early also keeps the heartbeat out of the widget tests, where a
    // repeating timer outlives the test that started it.
    //
    // The media session is still told, with a null grant. Skipping it left
    // the session at `idle`, which the notice renders as "Video
    // tayyorlanmoqda…" — a room that is preparing nothing, for ever.
    if (repo.isDemo) {
      unawaited(_media.connect(null));
      return;
    }

    final previous = _joinedLessonId;
    _joinedLessonId = lesson.id;
    _heartbeat?.cancel();

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

    if (_countsAttendance) {
      unawaited(() async {
        final banked = await repo.beginAttendance(lesson.id);
        if (!mounted || _joinedLessonId != lesson.id) return;
        _attendedBefore = banked;
        _sittingFrom = hkNow();
      }());
    }

    // Half the 75-second cutoff, so one dropped request is not enough to make
    // someone vanish from the list they are sitting in.
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      repo.enterRoom(lesson.id);
      // Banked on the beat as well as on the way out, because the way out is
      // the half that does not happen — laptops close and tabs are killed.
      if (_sittingFrom != null) {
        repo.recordAttendance(lesson.id, _attendedSeconds);
      }
    });
  }

  /// Mirrors the room's actual state into `ol_room_presence`, so the other
  /// participants see it.
  ///
  /// What is sent is what is true — [_micOn] now reads the published track,
  /// not the button — because this row is what draws the little microphone
  /// beside your name on everybody else's screen.
  void _pushPresence() {
    final id = _joinedLessonId;
    if (id == null) return;
    ref
        .read(lessonsRepositoryProvider)
        .enterRoom(id, micOn: _micOn, handRaised: _handRaised);
  }

  /// Turns the microphone on or off and tells the room what came of it.
  ///
  /// Ordered this way deliberately: ask the device first, publish the result
  /// second. The other way round announces a microphone that may never have
  /// been handed over.
  Future<void> _toggleMic() async {
    await _media.setMicrophone(!_micOn);
    if (!mounted) return;
    _pushPresence();
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
      final repo = ref.read(lessonsRepositoryProvider);
      if (_sittingFrom != null) {
        await repo.recordAttendance(id, _attendedSeconds);
        _sittingFrom = null;
      }
      await repo.leaveRoom(id);
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

    // Whoever the presence table has flagged as host — the teacher, by the
    // account id LiveKit also knows them by. The stage needs it to say
    // whether that person is speaking and whether their microphone is live,
    // neither of which `lesson.teacher` can answer: its id belongs to
    // `ol_teachers`, not to `auth.users`.
    final hostId = lesson == null
        ? null
        : (ref.watch(roomParticipantsProvider(lesson.id)).value ?? const [])
            .where((p) => p.isHost)
            .map((p) => p.id)
            .firstOrNull;

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
                _AudioBlockedNotice(media: _media),
                _DeviceErrorNotice(media: _media),
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
                            media: _media,
                            hostId: hostId,
                          ),
                        ),
                        const SizedBox(width: HkSpace.gridGap),
                        SizedBox(
                          width: 330,
                          child: _RightRail(
                            showChat: _showChat,
                            lessonId: lesson.id,
                            media: _media,
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
                      media: _media,
                      hostId: hostId,
                    ),
                  ),
                  const SizedBox(height: HkSpace.gridGap),
                  SizedBox(
                    height: 420,
                    child: _RightRail(
                      showChat: _showChat,
                      lessonId: lesson.id,
                      media: _media,
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
                  // Null while there is no media connection. A live-looking
                  // button that cannot reach a microphone is the thing this
                  // screen must never show again.
                  onMic: _media.isLive ? _toggleMic : null,
                  onCamera:
                      _media.isLive ? () => _media.setCamera(!_cameraOn) : null,
                  screenSharing: _media.screenSharing,
                  onScreenShare: _media.isLive
                      ? () => _media.setScreenShare(!_media.screenSharing)
                      : null,
                  onHand: () {
                    setState(() => _handRaised = !_handRaised);
                    _pushPresence();
                  },
                  onChat: () => setState(() => _showChat = !_showChat),
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

/// "You cannot hear anyone" — and the one button that fixes it.
///
/// A browser will not play a page's sound until the page has been interacted
/// with, and it does not say so. The lesson looks connected, the participant
/// list fills up, microphones light up, and it is silent: everyone waits for
/// somebody else to start, and every one of them has started.
///
/// It has to be a tap. The permission is granted to a gesture, not to a page,
/// so there is no way for the app to clear this quietly on the person's
/// behalf — which is why this is the loudest thing on the screen while it is
/// up, and gone the moment it is dealt with.
class _AudioBlockedNotice extends StatelessWidget {
  const _AudioBlockedNotice({required this.media});

  final LiveMediaSession media;

  @override
  Widget build(BuildContext context) {
    if (!media.audioBlocked) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        radius: HkRadius.cardSmall,
        tint: const Color(0x1AE08600),
        borderColor: const Color(0x55E08600),
        child: Row(
          children: [
            const Icon(
              Icons.volume_off_rounded,
              size: 18,
              color: HkColors.warningBright,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Brauzer ovozni to‘sib qo‘ydi — hozir hech kimni eshitmaysiz.',
                style: HkType.body.copyWith(fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 12),
            LimeButton(
              label: 'Ovozni yoqish',
              icon: Icons.volume_up_rounded,
              onPressed: media.startAudioPlayback,
            ),
          ],
        ),
      ),
    );
  }
}

/// A microphone or camera the device would not hand over.
///
/// Distinct from the connection notice above it: the room is fine and
/// everyone else is audible, it is this one device that was refused. Almost
/// always a permission the person can go and grant — which they will never
/// think to do if the only symptom is a button that does nothing.
class _DeviceErrorNotice extends StatelessWidget {
  const _DeviceErrorNotice({required this.media});

  final LiveMediaSession media;

  @override
  Widget build(BuildContext context) {
    final message = media.deviceError;
    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        radius: HkRadius.cardSmall,
        tint: const Color(0x1ADC2626),
        borderColor: const Color(0x33DC2626),
        child: Row(
          children: [
            const Icon(
              Icons.mic_off_rounded,
              size: 18,
              color: HkColors.dangerBright,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: HkType.body.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stage extends StatefulWidget {
  const _Stage({
    required this.lesson,
    required this.media,
    required this.hostId,
  });

  final Lesson lesson;
  final LiveMediaSession media;

  /// The teacher's account id, as LiveKit knows them.
  ///
  /// Taken from the presence row flagged `is_host` rather than from
  /// `lesson.teacher.id`, which is an `ol_teachers` row id and matches
  /// nothing in the media room — `ol_livekit_join()` signs the *account* id
  /// into the token. Null until presence has arrived, or when the teacher is
  /// not in the room.
  final String? hostId;

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

    final host = widget.hostId;
    // Null when the room has never heard of them — not joined yet, or no
    // media connection at all. The nameplate then shows no icon rather than
    // inventing one.
    final bool? hostMic = host == null ? null : widget.media.micOf(host);

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
                      // Whether this person is actually talking, not a loop.
                      // The rings used to pulse for ever, so the stage said
                      // "somebody is speaking" through an entire silence —
                      // the one question a quiet room needs answered
                      // truthfully.
                      speaking: host != null &&
                          widget.media.speakingIdentities.contains(host),
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
                  // Only when something is actually recording. The badge
                  // used to appear on any lesson flagged `auto_record`, with
                  // a running clock, while nothing recorded anything — see
                  // HkEnv.recordingEnabled.
                  if (HkEnv.recordingEnabled && widget.lesson.autoRecord)
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
                  // The icon was always the lit one, so the nameplate said
                  // the teacher was transmitting whatever they were doing.
                  // Null while the room has never heard of them, rather than
                  // guessing either way.
                  icon: hostMic == null
                      ? null
                      : (hostMic ? Icons.mic_rounded : Icons.mic_off_rounded),
                  background: const Color(0x66000000),
                  foreground: HkColors.textPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
              ),
            // No captions.
            //
            // There was a band here, on by default, holding one hard-coded
            // Korean sentence and its Uzbek translation — the same words in
            // every lesson, for everybody, with a "Subtitrlar" switch beside
            // the microphone implying that something was listening. In a
            // language school that is not a placeholder, it is a lesson aid
            // students would have leant on and been misled by.
            //
            // It comes back when there is speech recognition to fill it.
            // Self PiP. Your own camera when it is on — this was a box with
            // "Siz" written in it and nothing else, so the only way to learn
            // whether your camera worked was to ask somebody.
            if (!compact)
              Positioned(
                right: 16,
                bottom: 16,
                child: _SelfPreview(media: widget.media),
              ),
          ],
        ),
      ),
    );
  }
}

/// Your own camera, in the corner of the stage.
///
/// Says which of the three states it is in rather than showing the same box
/// for all of them: the camera is on and this is what it sees, the camera is
/// off, or there is no media connection to turn one on with.
class _SelfPreview extends StatelessWidget {
  const _SelfPreview({required this.media});

  final LiveMediaSession media;

  @override
  Widget build(BuildContext context) {
    final track = media.localCameraTrack;

    return Container(
      width: 158,
      height: 104,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0x1AD4E94C),
        borderRadius: BorderRadius.circular(HkRadius.chip),
        border: Border.all(color: const Color(0x33D4E94C)),
      ),
      alignment: Alignment.center,
      child: track != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                // Mirrored, because a preview of yourself that is not
                // mirrored reads as somebody else's camera.
                Transform.flip(
                  flipX: true,
                  child: VideoTrackRenderer(track, fit: VideoViewFit.cover),
                ),
                const Positioned(
                  left: 8,
                  bottom: 6,
                  child: Text(
                    'Siz',
                    style: TextStyle(
                      fontFamily: HkType.family,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  media.isLive
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_off_outlined,
                  size: 18,
                  color: HkColors.lime.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 6),
                Text(
                  media.isLive ? 'Kamerangiz o‘chiq' : 'Kamera ulanmagan',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: HkType.family,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: HkColors.lime,
                  ),
                ),
              ],
            ),
    );
  }
}

/// The teacher's avatar, with the design's lime ring while they are talking.
///
/// The ring used to repeat for ever, unconnected to any audio, so the stage
/// announced that somebody was speaking through an entire silence. On a
/// screen whose whole job is "can you hear this person", that was the one
/// thing it could not be allowed to make up.
class _SpeakingAvatar extends StatefulWidget {
  const _SpeakingAvatar({
    required this.initials,
    required this.size,
    required this.speaking,
    this.gradient,
  });

  final String initials;
  final double size;
  final bool speaking;
  final Gradient? gradient;

  @override
  State<_SpeakingAvatar> createState() => _SpeakingAvatarState();
}

class _SpeakingAvatarState extends State<_SpeakingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.speaking) _c.repeat();
  }

  @override
  void didUpdateWidget(_SpeakingAvatar old) {
    super.didUpdateWidget(old);
    if (widget.speaking == old.speaking) return;
    // Stopped where it stands rather than reset: a ring that snaps back to
    // its starting radius every time somebody pauses for breath flickers.
    widget.speaking ? _c.repeat() : _c.stop();
  }

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
              if (widget.speaking)
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
  const _RightRail({
    required this.showChat,
    required this.lessonId,
    required this.media,
  });

  final bool showChat;
  final String lessonId;

  /// Consulted for the microphone beside each name. See [_ParticipantRow].
  final LiveMediaSession media;

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
                        _ParticipantRow(
                      participant: participants[i],
                      media: media,
                    ),
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
  const _ParticipantRow({required this.participant, required this.media});

  final Participant participant;
  final LiveMediaSession media;

  @override
  Widget build(BuildContext context) {
    final p = participant;

    // The server's answer where there is one, the presence row's only where
    // there is not.
    //
    // `ol_room_presence.mic_on` is each client's account of itself, written
    // when somebody pressed a button. A browser that crashed mid-lesson
    // leaves its last claim behind for the length of the heartbeat cutoff,
    // and a lit microphone next to someone who is not in the room any more is
    // how a teacher ends up waiting for an answer from an empty chair.
    // LiveKit knows which audio tracks are actually published, and they stop
    // existing with the connection that published them.
    final micOn = media.micOf(p.id) ?? p.micOn;
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
            micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            size: 16,
            color: micOn ? HkColors.lime : HkColors.dangerBright,
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
    required this.screenSharing,
    required this.onScreenShare,
    required this.handRaised,
    required this.chatOn,
    required this.onMic,
    required this.onCamera,
    required this.onHand,
    required this.onChat,
    required this.onLeave,
    required this.onEnd,
    required this.ending,
  });

  final bool micOn;
  final bool cameraOn;
  final bool handRaised;
  final bool chatOn;

  final bool screenSharing;

  /// Null when there is no media connection to speak into. The buttons then
  /// render as unavailable and say why, rather than lighting up over nothing.
  final VoidCallback? onMic;
  final VoidCallback? onCamera;

  /// Was wired to an empty callback: pressable, silent, and inert.
  final VoidCallback? onScreenShare;
  final VoidCallback onHand;
  final VoidCallback onChat;
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
              tooltip: onMic == null
                  ? 'Mikrofon mavjud emas — audio ulanmagan'
                  : (micOn ? 'Mikrofonni o‘chirish' : 'Mikrofonni yoqish'),
              onTap: onMic,
            ),
            _ControlButton(
              icon: cameraOn
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              active: cameraOn,
              tooltip: onCamera == null
                  ? 'Kamera mavjud emas — video ulanmagan'
                  : (cameraOn ? 'Kamerani o‘chirish' : 'Kamerani yoqish'),
              onTap: onCamera,
            ),
            _ControlButton(
              icon: screenSharing
                  ? Icons.stop_screen_share_rounded
                  : Icons.screen_share_outlined,
              active: screenSharing,
              tooltip: onScreenShare == null
                  ? 'Ekranni ulashish mavjud emas — video ulanmagan'
                  : (screenSharing
                      ? 'Ulashishni to‘xtatish'
                      : 'Ekranni ulashish'),
              onTap: onScreenShare,
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

  /// Null renders the button as unavailable: dimmed, not clickable, and with
  /// a tooltip saying why. Better than a live-looking control that silently
  /// does nothing.
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
    final enabled = widget.onTap != null;
    final hovered = enabled && _hovered;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
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
                  : (hovered ? HkGlass.hoverFill : const Color(0x0FFFFFFF)),
              borderRadius: BorderRadius.circular(HkRadius.control),
            ),
            child: Icon(
              widget.icon,
              size: 20,
              color: widget.active
                  ? HkColors.ink
                  : (enabled ? HkColors.textPrimary : HkColors.textTertiary),
            ),
          ),
        ),
      ),
    );
  }
}
