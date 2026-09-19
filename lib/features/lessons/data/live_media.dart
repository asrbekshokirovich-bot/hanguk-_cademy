import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../domain/models.dart' show LiveMediaGrant;

/// Where a room's media connection has got to.
///
/// [unavailable] is not a failure. It is the honest state of a project that
/// has no LiveKit credentials configured — the chat and the participant list
/// still work, and the room says so rather than showing a broken video pane.
enum LiveMediaStatus { idle, connecting, connected, unavailable, failed }

/// The camera-and-microphone half of the live room.
///
/// Kept apart from the widget because a media connection outlives a rebuild
/// and must not be torn down by one. The widget listens; this owns the Room.
class LiveMediaSession extends ChangeNotifier {
  Room? _room;
  Room? get room => _room;

  EventsListener<RoomEvent>? _events;

  LiveMediaStatus status = LiveMediaStatus.idle;

  /// Why the connection failed, in the form LiveKit reported it. Shown on
  /// screen: "video is not working" is not something a teacher can act on,
  /// and the difference between a bad token and a blocked port is the whole
  /// of the diagnosis.
  String? error;

  /// Why the last microphone or camera request was refused, if it was.
  ///
  /// Separate from [error] because it is a different failure with a different
  /// remedy: the room is connected and everyone else can be heard, it is this
  /// one device that was not handed over. Usually a denied browser permission
  /// — which the person can go and change, but only if they are told.
  String? deviceError;

  /// True when the room is connected and its sound is being held back.
  ///
  /// Browsers refuse to play audio until the page has been interacted with,
  /// and they refuse silently. Untreated, the lesson looks perfect and is
  /// completely mute: everybody waits for somebody else to speak, and every
  /// one of them is speaking.
  bool audioBlocked = false;

  bool _disposed = false;

  /// Whether the microphone and camera buttons can do anything at all. False
  /// while the room is still connecting, and false for good on a project with
  /// no LiveKit behind it.
  bool get isLive => _room != null && status == LiveMediaStatus.connected;

  bool get micOn => _room?.localParticipant?.isMicrophoneEnabled() ?? false;
  bool get cameraOn => _room?.localParticipant?.isCameraEnabled() ?? false;
  bool get screenSharing =>
      _room?.localParticipant?.isScreenShareEnabled() ?? false;

  /// Your own camera, for the corner preview.
  ///
  /// Without it there is no way to find out whether the camera works other
  /// than asking somebody else — the preview was a box with "Siz" written in
  /// it, unchanged whether the camera was on, off or refused.
  VideoTrack? get localCameraTrack {
    final me = _room?.localParticipant;
    if (me == null) return null;
    for (final pub in me.videoTrackPublications) {
      if (pub.source != TrackSource.camera || pub.muted) continue;
      final track = pub.track;
      if (track is VideoTrack) return track;
    }
    return null;
  }

  /// Who is speaking right now, by the identity LiveKit knows them as.
  ///
  /// That identity is the Supabase `user_id`: `ol_livekit_join()` signs it
  /// into the token's `sub`, which is what makes it possible to line these
  /// up with the rows in `ol_room_presence`.
  Set<String> get speakingIdentities {
    final room = _room;
    if (room == null) return const {};
    return {
      for (final p in room.activeSpeakers)
        if (p.isSpeaking) p.identity,
    };
  }

  /// Whether [identity] is transmitting audio, as the server sees it — or
  /// null when this room has never heard of them.
  ///
  /// The presence table only carries what each client said about itself, so a
  /// browser that crashed leaves a lit microphone behind for the length of
  /// the heartbeat cutoff. This is the published track, and it goes away with
  /// the connection that published it.
  bool? micOf(String identity) {
    final room = _room;
    if (room == null) return null;

    final me = room.localParticipant;
    if (me != null && me.identity == identity) return me.isMicrophoneEnabled();

    for (final remote in room.remoteParticipants.values) {
      if (remote.identity != identity) continue;
      for (final pub in remote.audioTrackPublications) {
        if (pub.source == TrackSource.microphone) return !pub.muted;
      }
      return false;
    }
    return null;
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Joins the room described by [grant]. A null grant means the project has
  /// no media configured, which lands in [LiveMediaStatus.unavailable].
  ///
  /// Nobody's camera or microphone is turned on here. Joining a class should
  /// not broadcast your kitchen; the buttons on the control bar do that, and
  /// only when pressed.
  Future<void> connect(LiveMediaGrant? grant) async {
    if (grant == null) {
      // Idempotent on purpose. The room calls this from a post-frame
      // callback, so notifying on a state that has not changed would rebuild
      // the screen, which would schedule the callback, which would call this
      // again — for as long as the room stayed open.
      if (status == LiveMediaStatus.unavailable) return;
      status = LiveMediaStatus.unavailable;
      _changed();
      return;
    }
    if (status == LiveMediaStatus.connecting ||
        status == LiveMediaStatus.connected) {
      return;
    }

    status = LiveMediaStatus.connecting;
    error = null;
    _changed();

    final room = Room(
      roomOptions: const RoomOptions(
        // Sends only the resolutions that are actually on screen. A grid of
        // twenty thumbnails does not need twenty HD streams, and on a school
        // connection asking for them is how the audio starts breaking up.
        adaptiveStream: true,
        dynacast: true,
      ),
    );

    try {
      await room.connect(grant.url, grant.token);
      if (_disposed) {
        await room.disconnect();
        await room.dispose();
        return;
      }
      _room = room;
      room.addListener(_changed);
      // The room reports a blocked speaker as an event, not as a state
      // change, so `addListener` alone never hears about it.
      _events = room.createListener()
        ..on<AudioPlaybackStatusChanged>((_) {
          audioBlocked = !room.canPlaybackAudio;
          _changed();
        })
        // Who is speaking, and whose microphone is live, are the two things
        // the room draws on other people's behalf. Both arrive as events
        // rather than as a state change, so `addListener` alone would leave
        // the screen showing a moment that has passed.
        ..on<ActiveSpeakersChangedEvent>((_) => _changed())
        ..on<TrackMutedEvent>((_) => _changed())
        ..on<TrackUnmutedEvent>((_) => _changed())
        ..on<TrackPublishedEvent>((_) => _changed())
        ..on<TrackUnpublishedEvent>((_) => _changed())
        ..on<LocalTrackPublishedEvent>((_) => _changed())
        ..on<LocalTrackUnpublishedEvent>((_) => _changed());
      status = LiveMediaStatus.connected;
      // Asked for immediately, because on every platform but a browser it
      // simply works and the notice must not appear where it is not needed.
      // Where it is needed, this is what makes the browser say no, which is
      // the only way to find out before a whole lesson has gone by in
      // silence.
      await room.startAudio();
      audioBlocked = !room.canPlaybackAudio;
    } catch (e) {
      await room.dispose();
      status = LiveMediaStatus.failed;
      error = '$e';
    }
    _changed();
  }

  /// Lets the browser play the room's sound, from a tap it will accept.
  ///
  /// There is no way to do this on the app's behalf: the permission is
  /// granted to a gesture, not to a page, which is why the notice that calls
  /// this has to be something the person presses.
  Future<void> startAudioPlayback() async {
    final room = _room;
    if (room == null) return;
    try {
      await room.startAudio();
    } catch (e) {
      error = '$e';
    }
    audioBlocked = !room.canPlaybackAudio;
    _changed();
  }

  /// Turns the microphone on or off, and reports what actually happened.
  ///
  /// The caller must read [micOn] afterwards rather than assume the request
  /// was granted. A room where the button says "on" and the track was never
  /// published is the worst state this screen can be in: the person talks for
  /// ten minutes, everyone else's participant list shows a lit microphone
  /// beside their name, and nobody hears a word.
  Future<void> setMicrophone(bool on) async {
    final me = _room?.localParticipant;
    if (me == null) return;
    try {
      await me.setMicrophoneEnabled(on);
      deviceError = null;
    } catch (e) {
      // Almost always a denied permission. Surfaced rather than swallowed:
      // a mute button that does nothing and says nothing is the single most
      // reported bug in every video product there has ever been.
      deviceError = _deviceMessage(e, 'Mikrofon');
    }
    _changed();
  }

  Future<void> setCamera(bool on) async {
    final me = _room?.localParticipant;
    if (me == null) return;
    try {
      await me.setCameraEnabled(on);
      deviceError = null;
    } catch (e) {
      deviceError = _deviceMessage(e, 'Kamera');
    }
    _changed();
  }

  /// Shares the screen, or stops sharing it.
  ///
  /// The button for this was wired to an empty callback: it could be pressed,
  /// it did nothing, and it said nothing. The platform picks the window or
  /// display itself, so there is no source list to build here — but it can
  /// refuse (a browser dialog dismissed, a mobile browser that has no such
  /// API at all), and a refusal has to reach the screen like any other.
  Future<void> setScreenShare(bool on) async {
    final me = _room?.localParticipant;
    if (me == null) return;
    try {
      await me.setScreenShareEnabled(on);
      deviceError = null;
    } catch (e) {
      deviceError = _deviceMessage(e, 'Ekran');
    }
    _changed();
  }

  /// Plain Uzbek for the two refusals that actually happen, and the raw text
  /// for everything else — a message nobody can act on is worse than one that
  /// at least names what went wrong.
  static String _deviceMessage(Object error, String device) {
    final text = '$error';
    if (text.contains('NotAllowedError') ||
        text.contains('Permission') ||
        text.contains('permission')) {
      return '$device — ruxsat berilmadi. Brauzer manzil qatoridagi qulf '
          'belgisidan ruxsat bering va qaytadan urinib ko‘ring.';
    }
    if (text.contains('NotFoundError') || text.contains('NotReadableError')) {
      return '$device topilmadi yoki boshqa dastur uni band qilgan.';
    }
    return '$device — yoqib bo‘lmadi: $text';
  }

  /// The video worth putting on the stage: whoever is speaking, falling back
  /// to the first remote camera, then to your own.
  ///
  /// Returns null when nobody has a camera on, which is the normal state of
  /// an audio lesson — the stage then keeps the avatar it has always shown.
  VideoTrack? get stageTrack {
    final room = _room;
    if (room == null) return null;

    VideoTrack? firstCamera(Participant p) {
      for (final pub in p.videoTrackPublications) {
        if (pub.muted) continue;
        final track = pub.track;
        if (track is VideoTrack) return track;
      }
      return null;
    }

    final speaking = room.activeSpeakers;
    for (final speaker in speaking) {
      final track = firstCamera(speaker);
      if (track != null) return track;
    }
    for (final remote in room.remoteParticipants.values) {
      final track = firstCamera(remote);
      if (track != null) return track;
    }
    final me = room.localParticipant;
    return me == null ? null : firstCamera(me);
  }

  Future<void> leave() async {
    final room = _room;
    _room = null;
    status = LiveMediaStatus.idle;
    audioBlocked = false;
    deviceError = null;
    unawaited(_events?.dispose());
    _events = null;
    _changed();
    if (room == null) return;
    room.removeListener(_changed);
    try {
      await room.disconnect();
    } catch (_) {
      // Leaving is best-effort. The server drops a participant that stops
      // answering anyway, and a throw here would only break the screen that
      // is already on its way out.
    }
    await room.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    final room = _room;
    _room = null;
    unawaited(_events?.dispose());
    _events = null;
    if (room != null) {
      room.removeListener(_changed);
      unawaited(room.disconnect().catchError((_) {}).then((_) => room.dispose()));
    }
    super.dispose();
  }
}
