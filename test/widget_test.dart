import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/main.dart';
import 'package:hanguk_online/features/lessons/presentation/dashboard_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('uz'));

  // Without Supabase credentials the repository serves the design fixtures,
  // so this exercises the real widget tree end to end — shell, hero, stats
  // and both dashboard columns — rather than a mocked stand-in.
  testWidgets('dashboard renders the live hero and stats in demo mode',
      (tester) async {
    // Wide enough for HkLayout.expanded, which is the layout the design
    // targets and the only one with the floating dock.
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        // Demo mode: HkEnv defaults to the live project, and this test is
        // asserting on the fixture data, not on production rows.
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: MaterialApp.router(
          theme: hangukTheme,
          // AppShell reads the current location to decide which dock item is
          // active, so it needs a router above it — a bare MaterialApp is no
          // longer enough.
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Twice on purpose: the dock's active pill and the floating page heading.
    expect(find.text('Asosiy'), findsNWidgets(2));
    expect(find.text('HOZIR EFIRDA'), findsOneWidget);
    expect(find.text("Darsga qo'shilish"), findsOneWidget);
    expect(find.text('Bugungi jadval'), findsOneWidget);
    expect(find.text("So'nggi yozuvlar"), findsOneWidget);
    // The four stat cards from the design.
    expect(find.text('Bugungi darslar'), findsOneWidget);
    expect(find.text("O'rtacha davomat"), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);
  });
}
