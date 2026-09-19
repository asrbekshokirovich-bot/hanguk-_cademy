import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/lessons/presentation/dashboard_screen.dart';
import 'package:hanguk_online/features/staff/data/staff_repository.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_grading_screen.dart';
import 'package:hanguk_online/main.dart';

/// Homework had a middle and no ends.
///
/// `ol_assignments` has been in the schema since the first migration and the
/// grading queue is built on what comes back against it — but nothing in the
/// app ever wrote a row, and the only screen that showed one was the
/// recording detail, which is reachable through a recording and there are
/// none. So a teacher was asked to mark work that could not be set, for
/// students who could not have seen it if it had been.
///
/// These cover the two new ends: the student's side of the loop, and that
/// demo mode refuses both writes in plain Uzbek rather than hanging.
void main() {
  setUpAll(() async {
    initializeDateFormatting('uz');
    // The bundled fonts, because the default test font is about twice as wide
    // and overflows controls that fit perfectly in the app. A test that fails
    // on the font rather than on the layout teaches nothing; see the same
    // helper in the golden tests.
    await _loadBundledFonts();
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: MaterialApp.router(
          theme: hangukTheme,
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the student sees the homework they owe, and can hand it in',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.text('Uy vazifalari'), findsOneWidget);
    expect(find.text('Yangi so‘zlarni yozib keling'), findsOneWidget);
    // The lesson it came from: without it the student cannot tell which
    // class is asking, and homework is set per lesson.
    expect(
      find.textContaining('Koreys tili · Suhbat amaliyoti'),
      findsWidgets,
    );
    expect(find.text('Topshirish'), findsWidgets);
  });

  testWidgets('what is already handed in is not asked for again',
      (tester) async {
    await pumpDashboard(tester);

    // Three fixtures: two open, one already marked. The marked one shows the
    // score and the teacher's comment instead of a button, and the count at
    // the top counts only what is still owed.
    expect(find.text('92 ball'), findsOneWidget);
    expect(find.textContaining('O‘qituvchi:'), findsOneWidget);
    expect(find.text('Topshirish'), findsNWidgets(2));
    expect(find.text('2 ta topshirilmagan'), findsOneWidget);
  });

  testWidgets('a mark the student cannot see is a mark made into a void',
      (tester) async {
    await pumpDashboard(tester);

    // Regression in spirit: the grade dialog has always written a score and a
    // comment, and until now nothing on the student's side read either.
    expect(find.text('92 ball'), findsOneWidget);
    expect(
      find.textContaining('Fe’l qo‘shimchalariga'),
      findsOneWidget,
      reason: 'the comment is the half of a mark that teaches anything',
    );
  });

  testWidgets('a deadline that has passed says so', (tester) async {
    await pumpDashboard(tester);

    // Derived from the due date at read time, the way an overdue payment is
    // — nothing stores "late".
    expect(find.text('Muddati o‘tgan'), findsOneWidget);
  });

  group('the teacher can see the work they set', () {
    // The queue is built from `ol_v_submissions`, which has a row only once a
    // student has handed something in — so setting homework changed nothing
    // on screen, and "saved but nobody enrolled", "saved on somebody else's
    // lesson" and "not saved at all" all read as the same empty state.
    testWidgets('set assignments are listed with what has come back',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(null)],
          child: MaterialApp.router(
            theme: hangukTheme,
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const TeacherGradingScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Berilgan vazifalar'), findsOneWidget);
      expect(find.text('Yangi so‘zlar · 8-bo‘lim'), findsOneWidget);
      // Set, answered by nobody yet — which is a different thing from not
      // being set, and the screen could not tell them apart.
      expect(find.text('0/22 topshirdi'), findsOneWidget);
      expect(find.text('1/18 topshirdi'), findsNWidgets(2));
    });
  });

  group('demo mode refuses the writes, in Uzbek', () {
    test('a student cannot hand work in', () async {
      final repository = LessonsRepository(null);
      await expectLater(
        () => repository.submitAssignment('a1', 'javob'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Demo rejimda'),
          ),
        ),
      );
    });

    test('a teacher cannot set work', () async {
      final repository = StaffRepository(null);
      await expectLater(
        () => repository.setAssignment(lessonId: 'd1', title: 'Uy vazifasi'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Demo rejimda'),
          ),
        ),
      );
    });
  });

  group('attendance is measured, not marked', () {
    // Every attendance figure in the app — the admin dashboard's average, the
    // teacher's, the percentage beside each name in "Talabalarim" — divides
    // `ol_attendance.seconds_attended` by the lesson's length. Nothing ever
    // wrote a row, so against the real database all of them were zero and
    // what appeared on screen came from fixtures. The room now banks the
    // time, because it is the one thing that already knows.
    test('demo mode neither opens nor banks anything', () async {
      final repository = LessonsRepository(null);

      expect(await repository.beginAttendance('d2'), 0);
      // A no-op rather than a throw: this runs on a timer inside the room,
      // and a demo room must not start raising errors on the half-minute.
      await repository.recordAttendance('d2', 600);
    });
  });

  group('the model', () {
    test('overdue is not stored, it is the clock against the due date', () {
      final due = DateTime(2026, 6, 20, 23, 59);
      const base = Assignment(id: 'a', title: 'T', submitted: false);

      final open = Assignment(
        id: base.id,
        title: base.title,
        submitted: false,
        dueAt: due,
      );
      expect(open.isOverdueAt(due.subtract(const Duration(hours: 1))), isFalse);
      expect(open.isOverdueAt(due.add(const Duration(hours: 1))), isTrue);

      final handedIn = Assignment(
        id: base.id,
        title: base.title,
        submitted: true,
        dueAt: due,
      );
      expect(
        handedIn.isOverdueAt(due.add(const Duration(days: 30))),
        isFalse,
        reason: 'handed in late is still handed in',
      );

      expect(
        base.isOverdueAt(DateTime(2030)),
        isFalse,
        reason: 'no deadline, nothing to be late for',
      );
    });
  });
}

Future<void> _loadBundledFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(
        File(path).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await loader.load();
  }

  await load('Inter', [
    for (final w in [400, 500, 600, 700, 800, 900])
      'assets/fonts/Inter-$w.ttf',
  ]);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-600.ttf']);
  await load('NotoSansKR', [
    'assets/fonts/NotoSansKR-500.ttf',
    'assets/fonts/NotoSansKR-700.ttf',
  ]);
}
