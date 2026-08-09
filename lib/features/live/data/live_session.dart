import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../lessons/data/lessons_repository.dart';

/// Where a device is in the process of joining the room.
enum LiveStage { idle, connecting, connected, failed }

@immutable
class LiveState {
  const LiveState({
    this.stage = LiveStage.idle,
    this.room,
    this.error,
    this.micOn = false,
    this.cameraOn = false,
  });

  final LiveStage stage;
  final Room? room;
  final String? error;
  final bool micOn;
  final bool cameraOn;

  bool get isConnected => stage == LiveStage.connected;

  LiveState copyWith({
    LiveStage? stage,
    Room? room,
    String? error,
    bool? micOn,
    bool? cameraOn,
  }) {
    return LiveState(
      stage: stage ?? this.stage,
      room: room ?? this.room,
      // Cleared on every transition rather than carried: a stale message under
      // a working connection is worse than none.
      error: stage == null ? error : null,
      micOn: micOn ?? this.micOn,
      cameraOn: cameraOn ?? this.cameraOn,
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

  @override
  LiveState build() {
    ref.onDispose(_teardown);
    return const LiveState();
  }

  Future<void> connect(String lessonId) async {
    if (state.stage == LiveStage.connecting || state.isConnected) return;

    state = state.copyWith(stage: LiveStage.connecting);

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
        ..on<ParticipantDisconnectedEvent>((_) => _bump())
        ..on<TrackSubscribedEvent>((_) => _bump())
        ..on<TrackUnsubscribedEvent>((_) => _bump())
        ..on<ActiveSpeakersChangedEvent>((_) => _bump());

      await room.connect(credentials.url, credentials.token);
      _room = room;

      state = LiveState(stage: LiveStage.connected, room: room);
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
    state = LiveState(
      stage: LiveStage.connected,
      room: _room,
      micOn: state.micOn,
      cameraOn: state.cameraOn,
    );
  }

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

  Future<void> disconnect() async {
    await _teardown();
    state = const LiveState();
  }

  Future<void> _teardown() async {
    await _events?.dispose();
    _events = null;
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
  }
}

final liveSessionProvider =
    NotifierProvider<LiveSessionController, LiveState>(LiveSessionController.new);
