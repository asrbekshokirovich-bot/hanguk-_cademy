import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/core/clock.dart';
import 'package:hanguk_online/design_system/widgets/data_table.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/staff/presentation/admin_dashboard_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_finance_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_teachers_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_dashboard_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_grading_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_students_screen.dart';
import 'package:hanguk_online/main.dart';

final _fixedNow = DateTime(2026, 6, 26, 12, 58, 30);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('uz');
    await _loadBundledFonts();
    hkNow = () => _fixedNow;
  });

  tearDownAll(() => hkNow = DateTime.now);

  Future<void> pump(WidgetTester tester, Widget screen, {String? as}) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          // Who is looking. It matters on the admin panel now that the tier
          // decides what is on screen; the demo profile is a student, which
          // would render the panel as the one person who cannot open it.
          if (as != null)
            profileProvider.overrideWith((ref) async => UserProfile(
                  id: 'viewer',
                  fullName: 'Asrbek',
                  initials: 'A',
                  role: as,
                )),
        ],
        child: MaterialApp.router(
          theme: hangukTheme,
          debugShowCheckedModeBanner: false,
          routerConfig: GoRouter(
            routes: [GoRoute(path: '/', builder: (_, _) => screen)],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('teacher panel', () {
    testWidgets('dashboard', (tester) async {
      await pump(tester, const TeacherDashboardScreen());

      expect(find.text('Tekshirilmagan'), findsOneWidget);
      expect(find.text('Bugungi darslarim'), findsOneWidget);
      expect(find.text('Tekshirish kutilmoqda'), findsOneWidget);

      await expectLater(
        find.byType(TeacherDashboardScreen),
        matchesGoldenFile('goldens/teacher_dashboard.png'),
      );
    });

    testWidgets('students, with the struggling ones flagged', (tester) async {
      await pump(tester, const TeacherStudentsScreen());

      // Two of the six fixtures are below the attention thresholds.
      expect(find.text("2 ta e'tibor talab qiladi"), findsOneWidget);
      expect(find.text('Diqqat'), findsNWidgets(2));

      await expectLater(
        find.byType(TeacherStudentsScreen),
        matchesGoldenFile('goldens/teacher_students.png'),
      );
    });

    testWidgets('grading queue shows pending first', (tester) async {
      await pump(tester, const TeacherGradingScreen());

      // Three of five fixtures are ungraded, and the default view is those.
      expect(find.text('Kutilmoqda · 3'), findsOneWidget);
      expect(find.text('Barchasi · 5'), findsOneWidget);
      expect(find.text('Baholash'), findsNWidgets(4)); // title + 3 buttons

      await expectLater(
        find.byType(TeacherGradingScreen),
        matchesGoldenFile('goldens/teacher_grading.png'),
      );
    });

    testWidgets('the grade dialog validates its range', (tester) async {
      await pump(tester, const TeacherGradingScreen());

      // Scoped to the table: "Baholash" is also the page title, and the
      // heading floats under an IgnorePointer, so tapping it does nothing
      // and the dialog never opens.
      await tester.tap(
        find
            .descendant(
              of: find.byType(HkTable),
              matching: find.text('Baholash'),
            )
            .first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextFormField).first, '150');
      await tester.tap(find.text('Saqlash'));
      await tester.pump();

      expect(find.text('0 dan 100 gacha'), findsOneWidget);
    });
  });

  group('admin panel', () {
    testWidgets('dashboard, with alerts derived from the data',
        (tester) async {
      await pump(tester, const AdminDashboardScreen(), as: 'superadmin');

      expect(find.text('Boshqaruv'), findsWidgets);
      // One fixture payment is overdue, and one student has not been seen in
      // over two weeks — both are alerts rather than buried in a table.
      expect(find.textContaining('to‘lov kechikkan'), findsOneWidget);

      await expectLater(
        find.byType(AdminDashboardScreen),
        matchesGoldenFile('goldens/admin_dashboard.png'),
      );
    });

    testWidgets('teachers, with load', (tester) async {
      await pump(tester, const AdminTeachersScreen());

      expect(find.text('Jasur Karimov'), findsOneWidget);
      expect(find.text("Ta'til"), findsOneWidget);
      expect(find.text('Yangi'), findsOneWidget);

      await expectLater(
        find.byType(AdminTeachersScreen),
        matchesGoldenFile('goldens/admin_teachers.png'),
      );
    });

    testWidgets('finance', (tester) async {
      await pump(tester, const AdminFinanceScreen(), as: 'superadmin');

      // Money is written out in full in the table, short only on the cards.
      expect(find.text('10 000 000 UZS'), findsWidgets);
      expect(find.text('Tariflar'), findsOneWidget);
      expect(find.text('Tasdiqlash'), findsNWidgets(2));

      await expectLater(
        find.byType(AdminFinanceScreen),
        matchesGoldenFile('goldens/admin_finance.png'),
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
