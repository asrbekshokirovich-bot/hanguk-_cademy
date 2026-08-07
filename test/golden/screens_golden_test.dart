import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/presentation/dashboard_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/lesson_detail_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/live_room_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/recordings_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/schedule_screen.dart';
import 'package:hanguk_online/main.dart';

/// Renders each screen at the design's 1440×920 and compares against a
/// checked-in PNG.
///
/// This is the only way the layout gets verified without a GPU: the app is a
/// desktop-first design and CI has no display, but the Flutter test harness
/// rasterises in software. Regenerate with:
///
///     flutter test --update-goldens test/golden
///
/// Goldens are inherently platform-sensitive (font hinting differs between
/// hosts), so treat a diff as "look at it" rather than "the build is broken".
void main() {
  setUpAll(() async {
    await initializeDateFormatting('uz');
    await _loadBundledFonts();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: hangukTheme,
          debugShowCheckedModeBanner: false,
          // A throwaway router: the screens call `context.go`, which needs a
          // GoRouter ancestor even when nothing navigates during the test.
          routerConfig: GoRouter(
            routes: [GoRoute(path: '/', builder: (_, _) => screen)],
          ),
        ),
      ),
    );
    // Two pumps: one to resolve the demo-mode futures, one to lay out with
    // the data. pumpAndSettle would hang — the ambient orbs never stop.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
  }

  testWidgets('dashboard', (tester) async {
    await pumpScreen(tester, const DashboardScreen());
    await expectLater(
      find.byType(DashboardScreen),
      matchesGoldenFile('goldens/dashboard.png'),
    );
  });

  testWidgets('recordings', (tester) async {
    await pumpScreen(tester, const RecordingsScreen());
    await expectLater(
      find.byType(RecordingsScreen),
      matchesGoldenFile('goldens/recordings.png'),
    );
  });

  testWidgets('lesson detail', (tester) async {
    await pumpScreen(tester, const LessonDetailScreen(recordingId: 'r1'));
    await expectLater(
      find.byType(LessonDetailScreen),
      matchesGoldenFile('goldens/lesson_detail.png'),
    );
  });

  testWidgets('live room', (tester) async {
    await pumpScreen(tester, const LiveRoomScreen());
    await expectLater(
      find.byType(LiveRoomScreen),
      matchesGoldenFile('goldens/live_room.png'),
    );
  });

  testWidgets('schedule', (tester) async {
    await pumpScreen(tester, const ScheduleScreen());
    await expectLater(
      find.byType(ScheduleScreen),
      matchesGoldenFile('goldens/schedule.png'),
    );
  });
}

/// The test harness ships a placeholder font, so without this every golden
/// would be rows of identical boxes and would verify nothing.
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
