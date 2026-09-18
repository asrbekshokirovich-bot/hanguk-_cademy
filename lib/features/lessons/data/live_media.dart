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

  LiveMediaStatus status = LiveMediaStatus.idle;

  /// Why the connection failed, in the form LiveKit reported it. Shown on
  /// screen: "video is not working" is not something a teacher can act on,
  /// and the difference between a bad token and a blocked port is the whole
  /// of the diagnosis.
  String? error;

  bool _disposed = false;

  bool get micOn => _room?.localParticipant?.isMicrophoneEnabled() ?? false;
  bool get cameraOn => _room?.localParticipant?.isCameraEnabled() ?? false;

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
      status = LiveMediaStatus.connected;
    } catch (e) {
      await room.dispose();
      status = LiveMediaStatus.failed;
      error = '$e';
    }
    _changed();
  }

  Future<void> setMicrophone(bool on) async {
    final me = _room?.localParticipant;
    if (me == null) return;
    try {
      await me.setMicrophoneEnabled(on);
    } catch (e) {
      // Almost always a denied permission. Surfaced rather than swallowed:
      // a mute button that does nothing and says nothing is the single most
      // reported bug in every video product there has ever been.
      error = '$e';
    }
    _changed();
  }

  Future<void> setCamera(bool on) async {
    final me = _room?.localParticipant;
    if (me == null) return;
    try {
      await me.setCameraEnabled(on);
    } catch (e) {
      error = '$e';
    }
    _changed();
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
    if (room != null) {
      room.removeListener(_changed);
      unawaited(room.disconnect().catchError((_) {}).then((_) => room.dispose()));
    }
    super.dispose();
  }
}
