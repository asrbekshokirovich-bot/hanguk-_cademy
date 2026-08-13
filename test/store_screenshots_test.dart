@Tags(['store', 'golden'])
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
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/lessons/presentation/dashboard_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/recordings_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/schedule_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_payments_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_students_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_dashboard_screen.dart';
import 'package:hanguk_online/main.dart';

/// Writes the Play listing's phone screenshots from the running app.
///
/// Not a test — nothing is asserted, and it is tagged out of the default run
/// so `flutter test` stays about correctness. It exists because the
/// alternative is a person photographing a phone once, and then the listing
/// showing last month's app forever.
///
///     flutter test test/store_screenshots_test.dart --tags store
///
/// 1080×2340 is a common Android phone at 3x. Play wants 320–3840px on each
/// side and a sane aspect ratio; this sits comfortably inside both.
const _size = Size(1080, 2340);
const _dpr = 3.0;
const _outDir = 'docs/play/screenshots';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('uz');
    await _loadBundledFonts();
    hkNow = () => DateTime(2026, 6, 26, 12, 58, 30);
    Directory(_outDir).createSync(recursive: true);
  });

  tearDownAll(() => hkNow = DateTime.now);

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget screen, {
    String role = 'student',
  }) async {
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding =
        const FakeViewPadding(top: 141, bottom: 102); // 47/34 at 3x
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          profileProvider.overrideWith((ref) async => UserProfile(
                id: 'store',
                fullName: role == 'student' ? 'Aziza Karimova' : 'Asrbek',
                initials: role == 'student' ? 'AK' : 'A',
                role: role,
                level: role == 'student' ? 2 : null,
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
    await tester.pump(const Duration(milliseconds: 500));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../$_outDir/$name.png'),
    );
  }

  testWidgets('01 student dashboard', (t) => shoot(t, '01-asosiy', const DashboardScreen()));
  testWidgets('02 schedule', (t) => shoot(t, '02-jadval', const ScheduleScreen()));
  testWidgets('03 recordings', (t) => shoot(t, '03-yozuvlar', const RecordingsScreen()));
  testWidgets('04 teacher', (t) =>
      shoot(t, '04-oqituvchi', const TeacherDashboardScreen(), role: 'teacher'));
  testWidgets('05 admin students', (t) =>
      shoot(t, '05-talabalar', const AdminStudentsScreen(), role: 'admin'));
  testWidgets('06 admin payments', (t) =>
      shoot(t, '06-tolovlar', const AdminPaymentsScreen(), role: 'admin'));
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

  // Material's icon font. flutter_test does not load it, so every Icon in a
  // golden renders as an empty box — which is only cosmetic in a regression
  // test and unusable in a store screenshot. Read from the SDK because that
  // is where it lives; the app itself gets it from the engine at runtime.
  final iconFont = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
    '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFont.existsSync()) {
    await load('MaterialIcons', [iconFont.path]);
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
