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
import 'package:hanguk_online/features/staff/presentation/admin_payments_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_students_screen.dart';
import 'package:hanguk_online/features/staff/presentation/super_admin_screen.dart';
import 'package:hanguk_online/main.dart';

/// The app on a phone, at the size the owner actually opened it on.
///
/// The compact header used to be an overlay pinned to the top of a stack,
/// with the content below it starting at a guessed 16pt. It was not 16pt: the
/// header carries a status-bar inset and a subtitle that wraps, so on a real
/// phone the heading was printed straight over the first paragraph of every
/// screen. Nothing on a 1440-wide desktop golden could show that.
const _phone = Size(390, 844);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('uz');
    await _loadBundledFonts();
    hkNow = () => DateTime(2026, 6, 26, 12, 58, 30);
  });

  tearDownAll(() => hkNow = DateTime.now);

  Future<void> pump(WidgetTester tester, Widget screen, String role) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    // A notch. The header sits inside a SafeArea, so an inset of zero would
    // test the one phone shape that cannot go wrong.
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          if (role != 'student')
            profileProvider.overrideWith((ref) async => UserProfile(
                  id: 'viewer',
                  fullName: 'Asrbek',
                  initials: 'A',
                  role: role,
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

  /// What went wrong on the phone, stated as a test: the page heading and the
  /// screen's first paragraph must not be drawn on top of each other.
  void expectHeaderClearsContent(WidgetTester tester, Finder firstParagraph) {
    final heading = tester.getRect(find.text('Adminlar').first);
    final paragraph = tester.getRect(firstParagraph);
    expect(
      paragraph.top,
      greaterThan(heading.bottom),
      reason: 'the content starts below the header, never under it',
    );
  }

  testWidgets('the superadmin screen on a phone', (tester) async {
    await pump(tester, const SuperAdminScreen(), 'superadmin');

    expectHeaderClearsContent(
      tester,
      find.textContaining('kundalik ishini yuritadi'),
    );
    // Stacked, so the button gets the full width instead of a sliver.
    final button = tester.getRect(find.text('Yangi admin'));
    expect(button.top, greaterThan(48));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_super_admin.png'),
    );
  });

  testWidgets('the student roster on a phone', (tester) async {
    await pump(tester, const AdminStudentsScreen(), 'admin');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_students.png'),
    );
  });

  testWidgets('every admin section is reachable on a phone', (tester) async {
    await pump(tester, const AdminPaymentsScreen(), 'admin');

    // Six sections, and a phone bar that used to show four. The timetable
    // and payments fell off the end and could not be opened at all.
    for (final label in const [
      'Boshqaruv',
      'Talabalar',
      'O‘qituvchilar',
      'Guruhlar',
      'Jadval',
      'To‘lovlar',
    ]) {
      expect(
        find.text(label),
        findsWidgets,
        reason: '"$label" must exist in the bar, scrolled to or not',
      );
    }
  });

  testWidgets('payments on a phone', (tester) async {
    await pump(tester, const AdminPaymentsScreen(), 'admin');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_payments.png'),
    );
  });

  testWidgets('the student dashboard on a phone', (tester) async {
    await pump(tester, const DashboardScreen(), 'student');

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_dashboard.png'),
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
