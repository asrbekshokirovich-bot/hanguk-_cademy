import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/clock.dart';
import '../../lessons/data/lessons_repository.dart';

/// Where a device is in the process of joining the room.
enum LiveStage { idle, connecting, connected, failed }

/// One line of the in-lesson chat, on screen.
///
/// Delivery is over LiveKit's data channel because it is instant; durability
/// is a row in `ol_lesson_messages`, written alongside. The history is read
/// back on join, so arriving late does not mean arriving to an empty panel.
@immutable
class LiveMessage {
  const LiveMessage({
    required this.author,
    required this.text,
    required this.sentAt,
    this.mine = false,
  });

  final String author;
  final String text;
  final DateTime sentAt;
  final bool mine;
}

@immutable
class LiveState {
  const LiveState({
    this.stage = LiveStage.idle,
    this.room,
    this.error,
    this.micOn = false,
    this.cameraOn = false,
    this.screenOn = false,
    this.handRaised = false,
    this.messages = const [],
    this.handsUp = const {},
  });

  final LiveStage stage;
  final Room? room;
  final String? error;
  final bool micOn;
  final bool cameraOn;
  final bool screenOn;
  final bool handRaised;
  final List<LiveMessage> messages;

  /// Identities of everyone currently with a hand up, this device included.
  final Set<String> handsUp;

  bool get isConnected => stage == LiveStage.connected;

  LiveState copyWith({
    LiveStage? stage,
    Room? room,
    String? error,
    bool? micOn,
    bool? cameraOn,
    bool? screenOn,
    bool? handRaised,
    List<LiveMessage>? messages,
    Set<String>? handsUp,
  }) {
    return LiveState(
      stage: stage ?? this.stage,
      room: room ?? this.room,
      // Cleared on every transition rather than carried: a stale message under
      // a working connection is worse than none.
      error: stage == null ? error : null,
      micOn: micOn ?? this.micOn,
      cameraOn: cameraOn ?? this.cameraOn,
      screenOn: screenOn ?? this.screenOn,
      handRaised: handRaised ?? this.handRaised,
      messages: messages ?? this.messages,
      handsUp: handsUp ?? this.handsUp,
    );
  }
}

/// Joins the LiveKit room for one lesson and holds the connection.
///
/// The token comes from the `livekit-token` Edge Function, never from the
/// app: minting one needs the LiveKit API secret, and a secret shipped inside
/// an .aab is a public secret. The function also refuses to issue a token for
/// a lesson that is not live, so a student cannot dial into a room before the
/// teacher opens it.
class LiveSessionController extends Notifier<LiveState> {
  Room? _room;
  EventsListener<RoomEvent>? _events;

  /// Which lesson the open room belongs to. Chat rows are keyed on it.
  String? _lessonId;

  @override
  LiveState build() {
    ref.onDispose(_teardown);
    return const LiveState();
  }

  Future<void> connect(String lessonId) async {
    if (state.stage == LiveStage.connecting || state.isConnected) return;

    state = state.copyWith(stage: LiveStage.connecting);
    _lessonId = lessonId;

    try {
      final credentials =
          await ref.read(lessonsRepositoryProvider).liveKitToken(lessonId);
      if (credentials == null) {
        state = const LiveState(
          stage: LiveStage.failed,
          error: 'Video xizmati sozlanmagan',
        );
        return;
      }

      final room = Room(
        roomOptions: const RoomOptions(
          // Adaptive streaming drops the resolution of tiles that are small or
          // off-screen. On a phone over 3G — which is what the academy's
          // students are on — this is the difference between a call and a
          // slideshow.
          adaptiveStream: true,
          dynacast: true,
        ),
      );

      _events = room.createListener();
      _events!
        ..on<RoomDisconnectedEvent>((_) {
          state = state.copyWith(stage: LiveStage.idle);
        })
        ..on<ParticipantConnectedEvent>((_) => _bump())
        ..on<ParticipantDisconnectedEvent>((e) {
          // A hand goes down when its owner leaves; otherwise the rail keeps
          // showing a raised hand for somebody who is no longer here.
          final hands = {...state.handsUp}..remove(e.participant.identity);
          state = state.copyWith(handsUp: hands);
          _bump();
        })
        ..on<TrackSubscribedEvent>((_) => _bump())
        ..on<TrackUnsubscribedEvent>((_) => _bump())
        ..on<TrackMutedEvent>((_) => _bump())
        ..on<TrackUnmutedEvent>((_) => _bump())
        ..on<ActiveSpeakersChangedEvent>((_) => _bump())
        ..on<DataReceivedEvent>(_onData);

      await room.connect(credentials.url, credentials.token);
      _room = room;

      state = LiveState(stage: LiveStage.connected, room: room);

      // The lesson's chat so far. Somebody joining ten minutes late should
      // see what has been asked, not an empty panel. A failure here is not
      // worth failing the whole join over — the room still works, the
      // history is simply missing.
      try {
        final history =
            await ref.read(lessonsRepositoryProvider).lessonMessages(lessonId);
        final me = room.localParticipant?.identity;
        if (state.isConnected) {
          state = state.copyWith(
            messages: [
              for (final m in history)
                LiveMessage(
                  author: m.authorName,
                  text: m.body,
                  sentAt: m.sentAt,
                  mine: m.authorId == me,
                ),
              ...state.messages,
            ],
          );
        }
      } catch (_) {}
    } catch (e) {
      await _teardown();
      state = LiveState(stage: LiveStage.failed, error: '$e');
    }
  }

  /// The room mutates in place, so nothing in the state object changes when a
  /// participant joins or a track arrives. Riverpod compares by identity, so
  /// listeners need a new object to rebuild on.
  void _bump() {
    if (!state.isConnected) return;
    state = state.copyWith(room: _room, stage: LiveStage.connected);
  }

  // ------------------------------------------------------------- data ---

  void _onData(DataReceivedEvent event) {
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
    } catch (_) {
      return; // Not ours. Ignore rather than crash the room.
    }

    final from = event.participant?.identity ?? '';
    switch (payload['t']) {
      case 'chat':
        state = state.copyWith(
          messages: [
            ...state.messages,
            LiveMessage(
              author: (payload['n'] as String?) ?? 'Ishtirokchi',
              text: (payload['m'] as String?) ?? '',
              sentAt: hkNow(),
            ),
          ],
        );
      case 'hand':
        final up = payload['u'] == true;
        final hands = {...state.handsUp};
        if (up) {
          hands.add(from);
        } else {
          hands.remove(from);
        }
        state = state.copyWith(handsUp: hands);
    }
  }

  Future<void> _publish(Map<String, dynamic> payload) async {
    final local = _room?.localParticipant;
    if (local == null) return;
    await local.publishData(
      utf8.encode(jsonEncode(payload)),
      reliable: true,
    );
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !state.isConnected) return;

    final me = _room?.localParticipant;
    final name = (me?.name.isNotEmpty ?? false) ? me!.name : 'Men';

    // Shown immediately. LiveKit does not echo your own data back, so without
    // this the sender would watch their message disappear.
    state = state.copyWith(
      messages: [
        ...state.messages,
        LiveMessage(author: name, text: trimmed, sentAt: hkNow(), mine: true),
      ],
    );
    await _publish({'t': 'chat', 'n': name, 'm': trimmed});

    // Stored after it is on screen and on the wire: a slow insert should not
    // hold up the message, and a failed one should not swallow it.
    final lessonId = _lessonId;
    if (lessonId != null) {
      try {
        await ref.read(lessonsRepositoryProvider).sendLessonMessage(
              lessonId: lessonId,
              authorName: name,
              body: trimmed,
            );
      } catch (e) {
        state = state.copyWith(error: 'Xabar saqlanmadi: \$e');
      }
    }
  }

  Future<void> setHandRaised(bool up) async {
    if (!state.isConnected) return;
    final me = _room?.localParticipant?.identity;
    final hands = {...state.handsUp};
    if (me != null) {
      up ? hands.add(me) : hands.remove(me);
    }
    state = state.copyWith(handRaised: up, handsUp: hands);
    await _publish({'t': 'hand', 'u': up});
  }

  // ------------------------------------------------------------ tracks ---

  Future<void> setMicrophone(bool on) async {
    final room = _room;
    if (room == null) return;
    // Optimistic, and reverted below if the platform refuses — on Android the
    // permission dialog appears inside this call and the user may say no.
    state = state.copyWith(micOn: on);
    try {
      await room.localParticipant?.setMicrophoneEnabled(on);
    } catch (e) {
      state = state.copyWith(micOn: !on, error: '$e');
    }
  }

  Future<void> setCamera(bool on) async {
    final room = _room;
    if (room == null) return;
    state = state.copyWith(cameraOn: on);
    try {
      await room.localParticipant?.setCameraEnabled(on);
    } catch (e) {
      state = state.copyWith(cameraOn: !on, error: '$e');
    }
  }

  Future<void> setScreenShare(bool on) async {
    final room = _room;
    if (room == null) return;
    state = state.copyWith(screenOn: on);
    try {
      await room.localParticipant?.setScreenShareEnabled(on);
    } catch (e) {
      // Android needs the foreground-service consent dialog and the user can
      // dismiss it; iOS needs a broadcast extension the app does not ship.
      // Either way the button goes back rather than lying.
      state = state.copyWith(screenOn: !on, error: '$e');
    }
  }

  Future<void> disconnect() async {
    await _teardown();
    state = const LiveState();
  }

  Future<void> _teardown() async {
    _lessonId = null;
    await _events?.dispose();
    _events = null;
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
  }
}

final liveSessionProvider = NotifierProvider<LiveSessionController, LiveState>(
  LiveSessionController.new,
);
