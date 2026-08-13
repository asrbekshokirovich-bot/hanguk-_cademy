import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/lessons/presentation/live_room_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_dashboard_screen.dart';
import 'package:hanguk_online/main.dart';

/// A lesson has to be able to end.
///
/// `ol_lesson_status` has carried `live` and `ended` since the first
/// migration, and every screen already paints them — but for a while nothing
/// in the app ever *wrote* one. A lesson could only be put on air by hand in
/// the SQL editor, and once there it stayed on air forever: the dock's live
/// dot never went out, and the 30-day attendance average, which counts only
/// `ended` lessons, stayed at zero no matter how many were taught.
///
/// These tests hold the two ends of that life cycle in place — who is offered
/// them, and who is not.
UserProfile _profile(String role) => UserProfile(
      id: 'u-$role',
      fullName: role == 'student' ? 'Aziza Karimova' : 'Jasur Karimov',
      initials: 'JK',
      role: role,
    );

void main() {
  setUpAll(() => initializeDateFormatting('uz'));

  Future<void> pump(WidgetTester tester, Widget screen, String role) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          profileProvider.overrideWith((ref) async => _profile(role)),
        ],
        child: MaterialApp.router(
          theme: hangukTheme,
          routerConfig: GoRouter(
            routes: [GoRoute(path: '/', builder: (_, _) => screen)],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the status enum', () {
    test('round-trips every value the database can hold', () {
      // The write path sends `wire`; the read path parses it. If these two
      // ever disagree, a lesson silently reverts to 'scheduled' on the next
      // read — `fromWire` falls back rather than throwing.
      for (final status in LessonStatus.values) {
        expect(LessonStatus.fromWire(status.wire), status);
      }
    });
  });

  group('the teacher’s dashboard', () {
    testWidgets('offers to start a scheduled lesson, and to enter a live one',
        (tester) async {
      await pump(tester, const TeacherDashboardScreen(), 'teacher');

      // The demo day holds both a live lesson and scheduled ones, so both
      // labels are on screen at once — and they are different labels. They
      // used to be the same one: "Darsni boshlash" was shown *only* on a
      // lesson that was already live, where it did nothing but navigate.
      expect(find.text('Darsni boshlash'), findsWidgets);
      expect(find.text('Darsga kirish'), findsOneWidget);
    });
  });

  group('the live room', () {
    testWidgets('lets staff end the lesson', (tester) async {
      await pump(tester, const LiveRoomScreen(), 'teacher');

      expect(find.text('Darsni tugatish'), findsOneWidget);
      // Ending is not leaving, so both are offered.
      expect(find.text('Chiqish'), findsOneWidget);
    });

    testWidgets('asks before taking the lesson off air', (tester) async {
      await pump(tester, const LiveRoomScreen(), 'teacher');

      await tester.tap(find.text('Darsni tugatish'));
      // pump, not pumpAndSettle: the room's ambient background and its
      // "davom etmoqda" clock never stop ticking, so nothing here ever settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Sixty people are in the room and there is no undo, so the button on
      // its own is not enough — especially with "Chiqish" sitting next to it.
      expect(find.text('Bekor qilish'), findsOneWidget);

      await tester.tap(find.text('Bekor qilish'));
      // pump, not pumpAndSettle: the room's ambient background and its
      // "davom etmoqda" clock never stop ticking, so nothing here ever settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Bekor qilish'), findsNothing);
    });

    testWidgets('does not offer it to a student', (tester) async {
      await pump(tester, const LiveRoomScreen(), 'student');

      // Hiding it is not the check — `ol_lessons_write` is — but a student
      // must not be shown a control that ends the lesson for their class.
      expect(find.text('Darsni tugatish'), findsNothing);
      expect(find.text('Chiqish'), findsOneWidget);
    });
  });
}
