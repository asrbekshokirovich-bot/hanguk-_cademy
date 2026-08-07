import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/presentation/dashboard_screen.dart';
import 'package:hanguk_online/core/clock.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/main.dart';

/// Exercises the three user-cluster controls — search, notifications, profile
/// — by actually tapping them on a mounted dashboard, then capturing what
/// opens. These were shipped inert once; a golden that only renders the
/// closed state would not have caught that.

/// Pinned so the rendered output is a function of the fixtures alone. With a
/// real clock the live lesson's running timer ticks between the run that
/// writes a golden and the run that checks it, and every comparison fails on
/// a few changed digits. A Friday at 12:58, so "today" has a live lesson and
/// the week stepper lands mid-week.
final _fixedNow = DateTime(2026, 6, 26, 12, 58, 30);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('uz');
    await _loadBundledFonts();
    hkNow = () => _fixedNow;
  });

  tearDownAll(() => hkNow = DateTime.now);

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        // Pinned to demo mode. HkEnv now defaults to the real project, so
        // without this every test would issue live HTTP against Supabase —
        // slow, network-dependent, and dependent on whatever rows happen to
        // be in the database that day.
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: MaterialApp.router(
          theme: hangukTheme,
          debugShowCheckedModeBanner: false,
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
  }

  testWidgets('search finds lessons and recordings by teacher name',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    // Past showDialog's entrance transition. At 32ms the dialog is still
    // fading in, and the golden captures a half-transparent panel.
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField), 'Jasur');
    // Past the 300ms debounce.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Jasur Karimov teaches the live lesson and two recordings.
    expect(find.text('Darslar'.toUpperCase()), findsOneWidget);
    expect(find.text('Yozuvlar'.toUpperCase()), findsOneWidget);
    // Scoped to the dialog: the dashboard behind it also lists this
    // recording, so an unscoped finder matches twice and proves nothing.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Suhbat amaliyoti · 8-dars'),
      ),
      findsOneWidget,
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/search.png'),
    );
  });

  testWidgets('bell opens the panel and shows the unread count',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Bildirishnomalar'), findsOneWidget);
    expect(find.text('Suhbat amaliyoti boshlandi'), findsOneWidget);
    // Three of the four fixtures are unread, so the "mark read" action shows.
    expect(find.text("O'qildi"), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/notifications.png'),
    );
  });

  testWidgets('avatar opens the profile menu', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Aziza K.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Rol'), findsOneWidget);
    expect(find.text('Talaba'), findsOneWidget);
    // Demo mode has to be visible somewhere, and this is where.
    expect(find.text('Demo (offline)'), findsOneWidget);
    // No sign-out in demo mode: there is no session to end, and a button
    // that quietly does nothing is worse than no button.
    expect(find.text('Chiqish'), findsNothing);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/profile.png'),
    );
  });

  testWidgets('unread count drives the bell dot', (tester) async {
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);

    await container.read(notificationsProvider.future);
    expect(container.read(unreadCountProvider), 3);
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
