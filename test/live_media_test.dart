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
