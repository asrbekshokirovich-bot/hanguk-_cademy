import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 moved StateProvider out of the main barrel. Both remaining uses
// here are genuinely a single mutable value driven by a tap (the active
// filter chip, the visible week), which is what StateProvider is for.
import 'package:flutter_riverpod/legacy.dart';

import '../../auth/data/auth_repository.dart';
import '../domain/models.dart';
import 'lessons_repository.dart';
import '../../../core/clock.dart';

final profileProvider = FutureProvider<UserProfile>((ref) {
  // Watched, not ignored: the router reads this provider on its very first
  // redirect, which happens before anyone has signed in. That read fails and
  // the failure is what gets cached. Nothing else re-runs it, so without this
  // dependency the profile stays empty for the whole session — the user shows
  // as a nameless student however they signed in, and, worse, the
  // must_change_password gate never fires because the router sees a null
  // profile and skips the check.
  ref.watch(authStateProvider);
  // Re-read on the roster tick too. The role lives here and a superadmin can
  // change it from another machine: without this a demoted admin keeps the
  // admin dock and passes the router's checks until they restart the app, and
  // somebody promoted to teacher is shown none of the staff screens they were
  // just given. A minute-old role is acceptable; a session-old one is not.
  ref.watch(hkRosterTick);
  return ref.watch(lessonsRepositoryProvider).currentProfile();
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) {
  // On the tick, like the timetable card directly underneath it. Otherwise
  // "Bugungi darslar" reads 0 all day after an admin schedules today's
  // lesson, while the card below it lists that very lesson.
  ref.watch(_statusTick);
  return ref.watch(lessonsRepositoryProvider).dashboardStats();
});

final todaysLessonsProvider = FutureProvider<List<Lesson>>((ref) {
  // A lesson's status changes with the wall clock and nothing pushes that
  // change, so the day has to be re-read on the tick like the live lesson is.
  ref.watch(_statusTick);
  return ref.watch(lessonsRepositoryProvider).todaysLessons();
});

/// How often the app re-asks the database what is on air and what has ended.
///
/// Both answers move on their own — `ol_sync_lesson_statuses()` runs under
/// pg_cron every minute — and neither arrives as an event. Twenty seconds is
/// well inside how fast a student needs to learn their lesson started, and
/// well under the minute the cron job takes to change anything.
const _statusPollInterval = Duration(seconds: 20);

/// The lesson currently on air, re-read on [_statusPollInterval].
///
/// Polled rather than subscribed to. A realtime channel for a single boolean
/// ("is anything live?") is a websocket per client for the whole session,
/// while a poll costs one indexed row read.
///
/// It is a stream rather than a `FutureProvider` because a future resolves
/// once. That is the whole bug this replaces: the comment above said "poll"
/// and the code asked exactly once, at launch. A student who opened the app
/// before their lesson began sat on "Hozir jonli dars yo'q" for the length of
/// the lesson, however long it had actually been running.
///
/// `endStaleLessons()` runs first on every pass because the two are the same
/// question from opposite ends. The database flips the statuses itself, but a
/// project whose cron job is paused or behind would leave yesterday's lesson
/// on air — and the poll would then faithfully report it as live.
final liveLessonProvider = StreamProvider<Lesson?>((ref) async* {
  final repo = ref.watch(lessonsRepositoryProvider);

  while (true) {
    try {
      await repo.endStaleLessons();
      yield await repo.liveLesson();
    } catch (error, stack) {
      // Reported and then carried on from, rather than thrown. A throw here
      // ends the generator, and the poll with it: one dropped request on a
      // train would stop the app noticing lessons for the rest of the
      // session. Emitting through a sub-stream keeps this one open, so the
      // banner offers its Retry and the next pass clears it by itself when
      // the connection comes back.
      yield* Stream<Lesson?>.error(error, stack);
    }

    // Demo mode has nothing to poll — the fixtures are a constant — and a
    // widget test left holding this timer would never finish pumping.
    if (repo.isDemo) return;
    await Future<void>.delayed(_statusPollInterval);
  }
});

/// A bare counter on the poll cadence, for the screens whose reads are still
/// one-shot futures. It exists so they do not each end up owning a timer.
///
/// The schedule needs it for the same reason the dashboard does: a lesson
/// that had started, or had finished an hour ago, went on reading
/// "Rejalashtirilgan" until something else happened to rebuild the screen.
final _statusTickProvider = StreamProvider<int>((ref) async* {
  final demo = ref.watch(lessonsRepositoryProvider).isDemo;

  var tick = 0;
  yield tick;
  // Demo mode yields the one value and stops: the fixtures never move, and a
  // widget test left holding this timer would never finish pumping.
  while (!demo) {
    await Future<void>.delayed(_statusPollInterval);
    yield ++tick;
  }
});

/// The tick as a plain number, which is what its readers actually want.
///
/// Watching the stream itself would fire once more than it should: a
/// `StreamProvider` starts at `AsyncLoading` and reaches its first value a
/// microtask later, and that transition alone counts as a change. Every
/// screen would then re-read the whole day a moment after opening — a second
/// round trip that can only return what the first one did. Collapsing the
/// stream to `int` here means the first value looks the same as the state
/// before it, so the first rebuild is the twenty-second one.
final _statusTick = Provider<int>((ref) {
  return ref.watch(_statusTickProvider).value ?? 0;
});

/// How often the lists a person maintains by hand are re-read.
///
/// Rosters, groups and the grading queue do not move on their own — somebody
/// in the office does something and they change — so the twenty-second beat
/// would be asking a question whose answer almost never differs. Never asking
/// is what left a teacher reading "no group has been assigned to you" while
/// an administrator looked at the opposite on the next screen. A minute is
/// short enough that nobody calls it broken.
const _rosterPollInterval = Duration(minutes: 1);

final _rosterTickProvider = StreamProvider<int>((ref) async* {
  final demo = ref.watch(lessonsRepositoryProvider).isDemo;

  var tick = 0;
  yield tick;
  // Demo yields once and stops, for the same reason the status tick does: a
  // widget test left holding this timer would never finish pumping.
  while (!demo) {
    await Future<void>.delayed(_rosterPollInterval);
    yield ++tick;
  }
});

/// The roster tick as a plain number. Public because the screens that need it
/// most are in the staff feature, and collapsed to an `int` for the reason
/// written above [_statusTick]: watching the stream would cost every list a
/// second read a microtask after it opened.
final hkRosterTick = Provider<int>((ref) {
  return ref.watch(_rosterTickProvider).value ?? 0;
});

/// Whether the room is on tape, asked on the same beat as the lesson status.
///
/// The badge used to be drawn from `auto_record`, which is a wish rather than
/// a fact: it said "Yozib olinmoqda" over a room nothing was recording for as
/// long as that column was true.
final lessonRecordingProvider =
    FutureProvider.family<bool, String>((ref, lessonId) {
  ref.watch(_statusTick);
  return ref.watch(lessonsRepositoryProvider).isRecording(lessonId);
}, isAutoDispose: true);

final lessonByIdProvider =
    FutureProvider.family<Lesson?, String>((ref, id) {
  // The live room decides whether it is still a room from this value, so it
  // has to move with the lesson's status. Without the tick a teacher stayed
  // in a full live room after an admin ended it — and the first thing they
  // pressed came back as a raw row-level-security error, because the policy
  // behind the chat checks the status the screen had stopped reading.
  ref.watch(_statusTick);
  return ref.watch(lessonsRepositoryProvider).lessonById(id);
}, isAutoDispose: true);

/// Which filter chip is active in the recordings library. `null` = "Barchasi".
final recordingsFilterProvider = StateProvider<String?>((ref) => null);

/// The library, re-read on the roster beat.
///
/// A recording arrives a minute or two after the lesson ends, written by the
/// server rather than by anybody looking at this screen — so a list fetched
/// once at launch shows "Bu bo‘limda hali yozuv yo‘q" over a recording that
/// exists, until the app is restarted. That is exactly the shape of defect
/// the rosters had.
final recordingsProvider = FutureProvider<List<Recording>>((ref) {
  ref.watch(hkRosterTick);
  final category = ref.watch(recordingsFilterProvider);
  return ref.watch(lessonsRepositoryProvider).recordings(category: category);
}, isAutoDispose: true);

/// The three most recent recordings, for the dashboard's "So'nggi yozuvlar".
final recentRecordingsProvider = FutureProvider<List<Recording>>((ref) async {
  ref.watch(hkRosterTick);
  final all = await ref.watch(lessonsRepositoryProvider).recordings();
  return all.take(3).toList();
}, isAutoDispose: true);

/// What the recorder is doing, for the staff screen that would otherwise
/// just be empty.
final recordingJobsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(hkRosterTick);
  return ref.watch(lessonsRepositoryProvider).recordingJobs();
}, isAutoDispose: true);

final recordingByIdProvider =
    FutureProvider.family<Recording?, String>(isAutoDispose: true, (ref, id) {
  return ref.watch(lessonsRepositoryProvider).recordingById(id);
});

/// Auto-disposing: the homework row beside it re-reads on the tick, so a
/// handout uploaded afterwards would otherwise stay invisible while the
/// assignment around it updated — which reads as a failed upload.
final materialsProvider =
    FutureProvider.family<List<LessonMaterial>, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).materials(lessonId);
}, isAutoDispose: true);

final quizProvider =
    FutureProvider.family<LessonQuiz?, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).quiz(lessonId);
});

final assignmentProvider =
    FutureProvider.family<Assignment?, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).assignment(lessonId);
});

/// Start of the week currently shown in the schedule, as a Monday.
final scheduleWeekStartProvider = StateProvider<DateTime>((ref) {
  final now = hkNow();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - 1));
});

final weekLessonsProvider = FutureProvider<List<Lesson>>((ref) {
  // As with the day: the week grid paints a status per lesson, and the
  // statuses move without anyone touching the screen.
  ref.watch(_statusTick);
  final start = ref.watch(scheduleWeekStartProvider);
  return ref
      .watch(lessonsRepositoryProvider)
      .lessonsBetween(start, start.add(const Duration(days: 7)));
});

/// The homework this student owes, across every lesson they are enrolled in.
///
/// Watched on the dashboard, which is the only screen a student opens every
/// day. Homework used to live on the recording-detail page alone, and that
/// page is reachable only through a recording — of which there are none, so
/// the work a teacher set was invisible to the person meant to do it.
final myAssignmentsProvider = FutureProvider<List<Assignment>>((ref) {
  // On the same tick as the lesson status, because homework arrives the same
  // way: somebody else writes it while this screen is open. Without it a
  // student sitting on the dashboard is told they have no homework for as
  // long as they sit there, and the teacher who just set it is told by the
  // app that it was saved.
  ref.watch(_statusTick);
  return ref.watch(lessonsRepositoryProvider).myAssignments();
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  // Same reason, and more obviously so: a notification nobody is told about
  // until they restart the app is a notification that did not happen.
  ref.watch(_statusTick);
  return ref.watch(lessonsRepositoryProvider).notifications();
});

/// Drives the bell's red dot. Derived from the list rather than a separate
/// count query — the panel needs the rows anyway, and two sources would drift
/// (dot still red after the panel says everything is read).
final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value;
  if (list == null) return 0;
  return list.where((n) => n.isUnread).length;
});

/// The live room's chat, as it arrives.
/// Auto-disposing, like the presence stream below: leaving the room has to
/// close the realtime channel. Kept alive, every room a person had ever
/// opened stayed subscribed for the rest of the run.
final roomChatProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).chatStream(lessonId);
}, isAutoDispose: true);

/// Who is in the live room, as they come and go.
///
/// Re-evaluated on a timer as well as on every change, because membership
/// expires by a 75-second heartbeat cutoff and an expiry is not an event
/// anything pushes. This comment claimed the timer for a while before there
/// was one, and the room behaved accordingly: the last person to close their
/// laptop stayed in the list for good — nobody was left to type and trigger
/// a re-read — and a student arriving afterwards was shown a room full of
/// people who had already gone.
///
/// Fifteen seconds against a 75-second cutoff: someone who has left shows as
/// gone within about a quarter of the window they are given, and the recheck
/// costs nothing over the wire. It re-runs the filter over rows already in
/// hand rather than re-subscribing — see `reEmittedEvery`.
///
/// Demo mode gets no timer at all: `participantsStream` returns a fixture
/// before the interval is ever looked at, so widget tests are not left
/// pumping a loop that never ends.
///
/// Auto-disposing, which is also what cancels that fifteen-second timer when
/// the room closes. Kept alive, it ran for every room ever visited.
final roomParticipantsProvider =
    StreamProvider.family<List<Participant>, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).participantsStream(
        lessonId,
        recheckEvery: const Duration(seconds: 15),
      );
}, isAutoDispose: true);

/// What the user has typed into the search sheet.
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<SearchResults>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return SearchResults.empty;
  return ref.watch(lessonsRepositoryProvider).search(query);
});
