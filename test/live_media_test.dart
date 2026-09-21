import 'package:flutter_test/flutter_test.dart';

import 'package:hanguk_online/features/lessons/data/live_media.dart';

/// The control bar must never claim a microphone it does not have.
///
/// This is the state the live room used to be able to reach: the button lit,
/// `ol_room_presence.mic_on` sent as true, a green microphone beside your
/// name on everybody else's screen — and no audio track published at all.
/// The person talks for ten minutes and nobody hears a word, and nothing on
/// the screen suggests anything is wrong.
///
/// The session is the half of that which can be tested without a LiveKit
/// server: what it reports when there is no room behind it.
void main() {
  test('a session nobody has connected is not live', () {
    final media = LiveMediaSession();
    addTearDown(media.dispose);

    expect(media.isLive, isFalse);
    expect(media.micOn, isFalse, reason: 'no track, no microphone');
    expect(media.cameraOn, isFalse);
    expect(media.audioBlocked, isFalse);
    expect(media.status, LiveMediaStatus.idle);
  });

  test('a project with no LiveKit says so, and stays unavailable', () async {
    final media = LiveMediaSession();
    addTearDown(media.dispose);

    await media.connect(null);

    expect(media.status, LiveMediaStatus.unavailable);
    expect(
      media.isLive,
      isFalse,
      reason: 'the microphone and camera buttons hang off this',
    );
  });

  test('telling it twice that there is no media is silent the second time',
      () async {
    // Not a detail. The room calls connect() from a post-frame callback, so a
    // notification on a state that has not changed rebuilds the screen, which
    // schedules the callback, which calls this again — a loop that spins for
    // as long as the room is open.
    final media = LiveMediaSession();
    addTearDown(media.dispose);

    var notifications = 0;
    media.addListener(() => notifications++);

    await media.connect(null);
    expect(notifications, 1);

    await media.connect(null);
    await media.connect(null);
    expect(notifications, 1, reason: 'nothing changed, so nothing to say');
  });

  test('with no room, it claims nothing about anybody', () async {
    final media = LiveMediaSession();
    addTearDown(media.dispose);
    await media.connect(null);

    expect(media.screenSharing, isFalse);
    expect(media.localCameraTrack, isNull, reason: 'the self preview says so');
    expect(media.speakingIdentities, isEmpty, reason: 'the ring stays still');
    expect(
      media.micOf('some-user-id'),
      isNull,
      reason: 'null, not false — the participant list then falls back to '
          'the presence row rather than drawing everyone as muted',
    );
  });

  test('a screen-share request with no room behind it changes nothing',
      () async {
    final media = LiveMediaSession();
    addTearDown(media.dispose);
    await media.connect(null);

    await media.setScreenShare(true);

    expect(media.screenSharing, isFalse);
    expect(media.deviceError, isNull);
  });

  test('a microphone request with no room behind it changes nothing',
      () async {
    final media = LiveMediaSession();
    addTearDown(media.dispose);
    await media.connect(null);

    await media.setMicrophone(true);

    expect(
      media.micOn,
      isFalse,
      reason: 'asking is not the same as being heard',
    );
    expect(media.deviceError, isNull);
  });

  test('a mic press after the room has dropped says so', () async {
    final media = LiveMediaSession();
    addTearDown(media.dispose);

    // What a disconnect leaves behind: the session believed it was connected
    // and the room is gone. The button used to look live and do nothing.
    media.status = LiveMediaStatus.connected;
    await media.setMicrophone(true);

    expect(media.micOn, isFalse);
    expect(media.deviceError, contains('uzilgan'));
  });

  group('what the microphone beside a name is allowed to claim', () {
    // Every combination, because the defect was one of eight cases being
    // folded into another: "LiveKit has never heard of this person" was
    // treated as "their microphone is off", and the teacher was shown a
    // participant who could not be heard at all as merely quiet.
    HkMicState state({
      required bool mediaLive,
      required bool? fromLiveKit,
      required bool fromPresence,
      bool isSelf = false,
    }) =>
        hkMicState(
          mediaLive: mediaLive,
          fromLiveKit: fromLiveKit,
          fromPresence: fromPresence,
          isSelf: isSelf,
        );

    test('LiveKit wins over the presence table, both ways', () {
      // Publishing, whatever the row says.
      expect(
        state(mediaLive: true, fromLiveKit: true, fromPresence: false),
        HkMicState.live,
      );
      // Not publishing, whatever the row says. This is the stale `mic_on`
      // that survived a dropped connection.
      expect(
        state(mediaLive: true, fromLiveKit: false, fromPresence: true),
        HkMicState.muted,
      );
    });

    test('unknown to LiveKit, while we are in the room, is its own state', () {
      expect(
        state(mediaLive: true, fromLiveKit: null, fromPresence: true),
        HkMicState.absent,
      );
      expect(
        state(mediaLive: true, fromLiveKit: null, fromPresence: false),
        HkMicState.absent,
      );
    });

    test('our own row is never absent', () {
      expect(
        state(
          mediaLive: true,
          fromLiveKit: null,
          fromPresence: true,
          isSelf: true,
        ),
        HkMicState.live,
        reason: 'if the session is up we are in it; the row is all we have',
      );
    });

    test('with no media of our own we do not accuse anybody', () {
      // A room with no LiveKit configured, or one still connecting: we know
      // nothing about anybody's audio, so the presence row stands.
      expect(
        state(mediaLive: false, fromLiveKit: null, fromPresence: true),
        HkMicState.live,
      );
      expect(
        state(mediaLive: false, fromLiveKit: null, fromPresence: false),
        HkMicState.muted,
      );
    });
  });

  test('a failure can be cleared so the room may be tried again', () {
    final media = LiveMediaSession();
    addTearDown(media.dispose);

    media.fail('Token olinmadi');
    expect(media.status, LiveMediaStatus.failed);
    expect(media.error, 'Token olinmadi');

    media.reset();
    expect(media.status, LiveMediaStatus.idle);
    expect(media.error, isNull);
  });
}
