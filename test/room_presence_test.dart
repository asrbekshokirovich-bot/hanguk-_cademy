import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';

/// Leaving a room is not an event.
///
/// Presence expires by a 75-second heartbeat cutoff, and the cutoff is
/// applied where the rows arrive — so it is only ever re-applied when a row
/// changes. In a room that has gone quiet nothing changes, which is exactly
/// the moment it matters: the last person to shut their laptop stayed in the
/// list for good, because there was nobody left to type and trigger a
/// re-read, and a student walking in afterwards was shown a roomful of people
/// who had already left.
///
/// `roomParticipantsProvider` asks for a fifteen-second recheck now. What the
/// recheck does — re-send the rows already in hand, so the filter runs again
/// against a later clock, rather than tear down the realtime channel and
/// rebuild it — is [reEmittedEvery], and that is what these tests drive. The
/// filter itself sits behind a Supabase client and cannot be reached here.
///
/// Real timers at a few milliseconds rather than a pinned clock: this is
/// stream plumbing, and `testWidgets`' fake clock does not survive a stream
/// subscription living across it. The assertions are written to care about
/// what happened, not exactly how many times, so a slow machine cannot turn
/// them red.
///
/// That demo mode starts no timer at all is guarded where it would bite:
/// `lesson_lifecycle_test.dart` renders the live room, and a periodic timer
/// left running would fail those tests outright.
const _interval = Duration(milliseconds: 40);

/// Comfortably more than one interval, on a machine with other work to do.
Future<void> _pastATick() =>
    Future<void>.delayed(const Duration(milliseconds: 160));

/// Long enough for an event to be delivered, far short of a tick.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('re-sends the last event after the interval', () async {
    final source = StreamController<int>();
    final seen = <int>[];
    final subscription =
        reEmittedEvery(source.stream, _interval).listen(seen.add);
    addTearDown(subscription.cancel);

    source.add(1);
    await _settle();
    expect(seen, [1]);

    await _pastATick();
    expect(
      seen.length,
      greaterThan(1),
      reason: 'the rows go out again for the filter to re-read the clock',
    );
    expect(
      seen.every((e) => e == 1),
      isTrue,
      reason: 'the same rows, not invented ones',
    );
  });

  test('passes a real change straight through', () async {
    final source = StreamController<int>();
    final seen = <int>[];
    final subscription =
        reEmittedEvery(source.stream, _interval).listen(seen.add);
    addTearDown(subscription.cancel);

    source.add(1);
    await _settle();
    final before = seen.length;

    // Somebody joining is not held back waiting for the next tick.
    source.add(2);
    await _settle();
    expect(seen.length, before + 1);
    expect(seen.last, 2);
  });

  test('sends nothing before the source has spoken', () async {
    final source = StreamController<int>();
    final seen = <int>[];
    final subscription =
        reEmittedEvery(source.stream, _interval).listen(seen.add);
    addTearDown(subscription.cancel);

    // There is no latest event to re-send yet, and inventing one would put an
    // empty list on screen — which reads as an empty room rather than as a
    // room that has not loaded.
    await _pastATick();
    expect(seen, isEmpty);
  });

  test('stops ticking when the listener goes away', () async {
    final source = StreamController<int>();
    final seen = <int>[];
    final subscription =
        reEmittedEvery(source.stream, _interval).listen(seen.add);

    source.add(1);
    await _settle();
    await subscription.cancel();
    final atCancel = seen.length;

    // Leaving the room must not leave a timer running behind it.
    await _pastATick();
    expect(seen.length, atCancel);
  });
}
