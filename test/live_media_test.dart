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
}
