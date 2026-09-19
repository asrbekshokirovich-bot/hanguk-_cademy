import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/staff/data/staff_providers.dart';
import 'package:hanguk_online/features/staff/data/staff_repository.dart';
import 'package:hanguk_online/features/staff/domain/staff_models.dart';
import 'package:hanguk_online/features/staff/presentation/admin_groups_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_students_screen.dart';
import 'package:hanguk_online/main.dart';

/// The app read each list once per launch and then believed itself.
///
/// A Riverpod 3 provider is kept alive by default, so "Talabalarim" was
/// fetched when the teacher first opened it and never again. An administrator
/// put three students in that teacher's group; the teacher's screen — open
/// since the morning — went on saying "Sizga hali guruh biriktirilmagan",
/// while the admin panel three feet away showed the same three students
/// under that teacher's name. The database was right the whole time.
///
/// Two halves are covered here: that the lists are re-read, and that the
/// empty state stops guessing at why it is empty.
void main() {
  setUpAll(() => initializeDateFormatting('uz'));

  group('nothing outlives the screen that opened it', _lifetimes);

  group('a list is re-read when its screen comes back', () {
    test('the teacher roster is not cached for the run', () async {
      final repository = _CountingStaff();
      final container = ProviderContainer(
        overrides: [staffRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      var sub = container.listen(myStudentsProvider, (_, _) {});
      await container.read(myStudentsProvider.future);
      expect(repository.rosterReads, 1);

      // The teacher navigates away: the screen is the only listener.
      sub.close();
      await Future<void>.delayed(Duration.zero);

      sub = container.listen(myStudentsProvider, (_, _) {});
      await container.read(myStudentsProvider.future);
      expect(
        repository.rosterReads,
        2,
        reason: 'coming back to the screen has to ask the database again',
      );
      sub.close();
    });

    test('nothing kept alive pins the grading queue open', () {
      // `pendingSubmissionsProvider` feeds the teacher's home cards from the
      // grading queue. A kept-alive provider holds everything it watches
      // alive with it, so leaving this one as it was would have undone the
      // fix for the queue.
      expect(pendingSubmissionsProvider.isAutoDispose, isTrue);
      expect(submissionsProvider.isAutoDispose, isTrue);
    });
  });

  group('an empty screen says which nothing it is', () {
    Future<void> pump(
      WidgetTester tester, {
      required String? teacherId,
    }) async {
      tester.view.physicalSize = const Size(1440, 920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseClientProvider.overrideWithValue(null),
            myTeacherIdProvider.overrideWith((ref) async => teacherId),
            myStudentsProvider.overrideWith((ref) async => const []),
          ],
          // Through a router: the shell navigates, so it needs one above it.
          child: MaterialApp.router(
            theme: hangukTheme,
            locale: hkLocale,
            supportedLocales: hkSupportedLocales,
            localizationsDelegates: hkLocalizationsDelegates,
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const TeacherStudentsScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('no group assigned, for a teacher the roster knows',
        (tester) async {
      await pump(tester, teacherId: 't-1');
      expect(find.textContaining('Sizga hali guruh biriktirilmagan'),
          findsOneWidget);
    });

    testWidgets('not on the roster at all is a different sentence',
        (tester) async {
      await pump(tester, teacherId: null);

      // The one the teacher can act on: an administrator can see them under
      // the group and cannot see that the link is missing.
      expect(
        find.textContaining('o‘qituvchilar ro‘yxatiga bog‘lanmagan'),
        findsOneWidget,
      );
      expect(find.textContaining('Sizga hali guruh'), findsNothing);
    });
  });

  group('the admin can see the reason a student sees nothing', () {
    testWidgets('a group with no lesson ahead of it is marked',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(null)],
          child: MaterialApp.router(
            theme: hangukTheme,
            locale: hkLocale,
            supportedLocales: hkSupportedLocales,
            localizationsDelegates: hkLocalizationsDelegates,
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const AdminGroupsScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Enrolment only reaches lessons that have not happened yet, so a group
      // with nothing scheduled is a group whose students open the app to an
      // empty week — and that was invisible in every admin screen.
      expect(find.text('Dars qo‘yilmagan'), findsOneWidget);
      expect(find.text('2 ta'), findsOneWidget);
    });
  });
}

/// The lifetimes the audit found still pinned open.
///
/// Each of these is a stream or a list that used to live for the whole run:
/// every live room ever opened kept its realtime channel and its fifteen-
/// second timer; the room's own lesson never re-read its status, so the
/// screen stayed "live" after an administrator ended it and the first
/// keystroke came back as a row-level-security error; a handout uploaded
/// after the homework card had drawn stayed invisible; and the price list
/// behind the payment dialog went on charging last month's tariff.
void _lifetimes() {
  test('what the live room opens, the live room closes', () {
    expect(roomChatProvider('x').isAutoDispose, isTrue);
    expect(roomParticipantsProvider('x').isAutoDispose, isTrue);
    expect(lessonByIdProvider('x').isAutoDispose, isTrue);
    expect(materialsProvider('x').isAutoDispose, isTrue);
  });

  test('the price list is not cached for the run', () {
    expect(plansProvider.isAutoDispose, isTrue);
  });
}

/// Counts the reads, which is the whole point: the defect was a second read
/// that never happened.
class _CountingStaff extends StaffRepository {
  _CountingStaff() : super(null);

  int rosterReads = 0;

  @override
  Future<List<TeacherStudent>> myStudents() {
    rosterReads++;
    return super.myStudents();
  }
}
