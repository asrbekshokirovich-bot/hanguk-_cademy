@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/core/clock.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/staff/data/staff_demo_data.dart';
import 'package:hanguk_online/features/staff/presentation/admin_students_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_groups_screen.dart';
import 'package:hanguk_online/features/staff/presentation/group_dialogs.dart';
import 'package:hanguk_online/features/staff/presentation/lesson_dialog.dart';
import 'package:hanguk_online/main.dart';

/// The two dialogs an admin uses to run the timetable: creating a lesson, and
/// putting a student in a group (which is what gives them a teacher).
///
/// There is no GPU in CI, so a golden is the only way to see that these render
/// at all — every earlier layout defect in this app was found this way.
final _fixedNow = DateTime(2026, 6, 26, 12, 58, 30);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('uz');
    await _loadBundledFonts();
    hkNow = () => _fixedNow;
  });

  tearDownAll(() => hkNow = DateTime.now);

  Future<void> pump(WidgetTester tester, [Widget? screen]) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: MaterialApp.router(
          theme: hangukTheme,
          debugShowCheckedModeBanner: false,
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => screen ?? const AdminStudentsScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Past the dialog's entrance animation. One pump captures it mid-flight,
  /// half-scaled and half-transparent.
  Future<void> settleDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the lesson dialog collects a full schedule entry',
      (tester) async {
    await pump(tester);
    showLessonDialog(tester.element(find.byType(AdminStudentsScreen)));
    await settleDialog(tester);

    expect(find.text('Yangi dars'), findsOneWidget);
    // A lesson without a time is not a lesson; both pickers are prefilled so
    // the common case is one field and a tap.
    expect(find.text('Sana'), findsOneWidget);
    expect(find.text('Vaqt'), findsOneWidget);
    expect(find.text('60 daqiqa'), findsOneWidget);
    // The group is what pulls students in, so it says so rather than leaving
    // the admin to enrol sixty people by hand.
    expect(find.textContaining('avtomatik biriktiriladi'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lesson_dialog.png'),
    );
  });

  testWidgets('assigning a group is what gives a student a teacher',
      (tester) async {
    await pump(tester);
    showAssignGroupDialog(
      tester.element(find.byType(AdminStudentsScreen)),
      // Already in a group: the dialog must open on the current one rather
      // than on "Guruhsiz", or saving would silently detach them.
      student: StaffDemoData.adminStudents().first,
    );
    await settleDialog(tester);

    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Dilshod Mahmudov')),
      findsOneWidget,
    );
    // The teacher is shown as a consequence of the group, not chosen next to
    // it — that is the whole point of routing the assignment through a group.
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('Jasur Karimov'),
      ),
      findsOneWidget,
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/assign_group_dialog.png'),
    );
  });

  testWidgets('the groups section is the hinge of the admin panel',
      (tester) async {
    await pump(tester, const AdminGroupsScreen());

    // A group is what ties a student to a teacher, so the screen says which
    // teacher runs each one rather than leaving it to be inferred.
    expect(find.text('Daraja 2 · A'), findsOneWidget);
    expect(find.text('Jasur Karimov'), findsOneWidget);
    expect(find.text('Yangi guruh'), findsOneWidget);

    await expectLater(
      find.byType(AdminGroupsScreen),
      matchesGoldenFile('goldens/admin_groups.png'),
    );
  });

  testWidgets('the group form picks a teacher, not a student', (tester) async {
    await pump(tester, const AdminGroupsScreen());
    await tester.tap(find.text('Yangi guruh'));
    await settleDialog(tester);

    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Yangi guruh')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('O‘qituvchini tanlang')),
      findsNothing,
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/group_form_dialog.png'),
    );
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