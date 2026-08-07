import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is exported from misc.dart in Riverpod 3, not the main barrel.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/staff/data/staff_providers.dart';
import 'package:hanguk_online/features/staff/domain/staff_models.dart';
import 'package:hanguk_online/features/staff/presentation/admin_students_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_teachers_screen.dart';
import 'package:hanguk_online/main.dart';

/// Regression tests for a defect the user hit on their own data.
///
/// The create button used to live inside the AsyncSection's data builder, so
/// an empty roster replaced the whole block — button included — with "Hali
/// talaba qo'shilmagan". The one moment you certainly need to add a student
/// is when there are none, and that was exactly when the button vanished.
void main() {
  setUpAll(() => initializeDateFormatting('uz'));

  Future<void> pump(
    WidgetTester tester,
    Widget screen,
    List<Override> overrides,
  ) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          ...overrides,
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

  testWidgets('an empty student roster still offers the create button',
      (tester) async {
    await pump(tester, const AdminStudentsScreen(), [
      adminStudentsProvider.overrideWith((ref) async => <AdminStudent>[]),
    ]);

    expect(find.textContaining('Hali talaba yo‘q'), findsOneWidget);
    expect(find.text('Yangi talaba'), findsOneWidget);
  });

  testWidgets('an empty teacher roster still offers the create button',
      (tester) async {
    await pump(tester, const AdminTeachersScreen(), [
      teacherRosterProvider
          .overrideWith((ref) async => <TeacherRosterEntry>[]),
    ]);

    expect(find.textContaining('Hali o‘qituvchi yo‘q'), findsOneWidget);
    expect(find.text('O‘qituvchi qo‘shish'), findsOneWidget);
  });

  testWidgets('the button is there while the roster is still loading',
      (tester) async {
    // Same reasoning: a slow connection must not hide the action either.
    // A Completer rather than Future.delayed — a pending timer outlives the
    // widget tree and the harness fails the test for it.
    final pending = Completer<List<AdminStudent>>();
    addTearDown(() => pending.complete(<AdminStudent>[]));

    await pump(tester, const AdminStudentsScreen(), [
      adminStudentsProvider.overrideWith((ref) => pending.future),
    ]);

    expect(find.text('Yangi talaba'), findsOneWidget);
  });
}
