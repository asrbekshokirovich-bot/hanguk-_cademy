import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hanguk_online/features/lessons/data/demo_data.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';

/// A lesson starts and ends on the wall clock, and the app has to notice.
///
/// Regression tests. `liveLessonProvider` carried a comment describing a
/// thirty-second poll over a `FutureProvider` that resolved exactly once, at
/// launch — the comment stated the intention and the code did not carry it
/// out. A student who opened the app before their lesson began was told
/// "Hozir jonli dars yo'q" for the whole hour it then ran, and the schedule
/// went on calling a finished lesson "Rejalashtirilgan" until something else
/// happened to rebuild the screen.
///
/// Nothing pushes either change: the statuses are moved server side by
/// `ol_sync_lesson_statuses()` under pg_cron, which is a write to a table
/// nobody is subscribed to.
class _FakeRepository extends LessonsRepository {
  _FakeRepository({this.demo = false}) : super(null);

  /// Set rather than inherited. `isDemo` really means "no Supabase client",
  /// and this fake has none either way; what the polling turns on is whether
  /// there is a backend whose answer can change, so each test says so.
  final bool demo;

  int liveReads = 0;
  int staleSweeps = 0;
  int dayReads = 0;

  /// What the next read of the live lesson will find.
  Lesson? onAir;

  /// Set to fail the next read, the way a dropped connection would.
  bool offline = false;

  @override
  bool get isDemo => demo;

  @override
  Future<void> endStaleLessons() async => staleSweeps++;

  @override
  Future<Lesson?> liveLesson() async {
    liveReads++;
    if (offline) throw StateError('tarmoqqa ulanib bo‘lmadi');
    return onAir;
  }

  @override
  Future<List<Lesson>> todaysLessons() async {
    dayReads++;
    return DemoData.todaysLessons();
  }
}

/// Everything the polling providers need, and nothing else.
ProviderContainer _containerFor(_FakeRepository repository) {
  return ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      lessonsRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

void main() {
  // testWidgets, not test: it runs the body against a fake clock, so the
  // twenty-second wait costs nothing and `pump` decides when it elapses.
  testWidgets('the live lesson is re-read for as long as anyone is watching',
      (tester) async {
    final repository = _FakeRepository();
    final container = _containerFor(repository);
    container.listen(liveLessonProvider, (_, _) {});

    await tester.pump();
    expect(repository.liveReads, 1, reason: 'asked once on open');
    expect(container.read(liveLessonProvider).value, isNull);

    // The lesson starts while the app sits there untouched — which is what
    // it does: the student opens it a few minutes early and waits.
    repository.onAir = DemoData.todaysLessons().first;

    await tester.pump(const Duration(seconds: 20));
    expect(repository.liveReads, 2, reason: 'asked again on the next tick');
    expect(
      container.read(liveLessonProvider).value,
      isNotNull,
      reason: 'the screen learns the lesson started without being touched',
    );

    await tester.pump(const Duration(seconds: 20));
    expect(repository.liveReads, 3, reason: 'and keeps asking');

    await _drain(tester, container);
  });

  testWidgets('every pass tidies up the lessons that ran past their slot',
      (tester) async {
    final repository = _FakeRepository();
    final container = _containerFor(repository);
    container.listen(liveLessonProvider, (_, _) {});

    // Both halves of the same question. Asking what is on air without first
    // ending what should have finished is how "the lesson from three weeks
    // ago is still live" survives a poll that is working perfectly.
    await tester.pump();
    expect(repository.staleSweeps, 1);

    await tester.pump(const Duration(seconds: 20));
    expect(repository.staleSweeps, 2);

    await _drain(tester, container);
  });

  testWidgets('a dropped request does not end the poll', (tester) async {
    // The app is used on mobile connections in Uzbekistan, where a request
    // failing is ordinary. Throwing out of the generator would end the
    // stream, and one bad moment would stop the app noticing lessons for the
    // rest of the session — the very failure this polling exists to prevent.
    final repository = _FakeRepository()..offline = true;
    final container = _containerFor(repository);
    container.listen(liveLessonProvider, (_, _) {});

    await tester.pump();
    expect(container.read(liveLessonProvider).hasError, isTrue,
        reason: 'the banner has to be able to say the read failed');

    repository
      ..offline = false
      ..onAir = DemoData.todaysLessons().first;

    await tester.pump(const Duration(seconds: 20));
    expect(repository.liveReads, 2, reason: 'it asked again anyway');
    expect(
      container.read(liveLessonProvider).value,
      isNotNull,
      reason: 'and cleared its own error once the connection came back',
    );

    await _drain(tester, container);
  });

  testWidgets('the schedule is re-read on the same tick', (tester) async {
    final repository = _FakeRepository();
    final container = _containerFor(repository);
    container.listen(todaysLessonsProvider, (_, _) {});

    await tester.pump();
    expect(
      repository.dayReads,
      1,
      reason: 'the tick must not cost a second round trip on open',
    );

    await tester.pump(const Duration(seconds: 20));
    expect(
      repository.dayReads,
      2,
      reason: 'a lesson that has ended stops reading "Rejalashtirilgan"',
    );

    await _drain(tester, container);
  });

  testWidgets('demo mode reads once and stops', (tester) async {
    // There is no backend whose answer could change, and a widget test left
    // holding the timer would never finish pumping — every golden in the
    // suite renders against these fixtures.
    final repository = _FakeRepository(demo: true);
    final container = _containerFor(repository);
    addTearDown(container.dispose);
    container.listen(liveLessonProvider, (_, _) {});
    container.listen(todaysLessonsProvider, (_, _) {});

    await tester.pump();
    expect(repository.liveReads, 1);
    expect(repository.dayReads, 1);

    await tester.pump(const Duration(minutes: 5));
    expect(repository.liveReads, 1, reason: 'nothing to poll');
    expect(repository.dayReads, 1);
  });
}

/// Closes a polling container down cleanly.
///
/// Disposing stops the stream, but the `Future.delayed` it is parked on is
/// already scheduled and fires regardless; the generator only gets to see
/// that it was cancelled when it resumes. Pumping past that last interval
/// lets it end, so the test does not finish with a timer still pending.
Future<void> _drain(WidgetTester tester, ProviderContainer container) async {
  container.dispose();
  await tester.pump(const Duration(seconds: 21));
}
