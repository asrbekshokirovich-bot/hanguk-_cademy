import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/core/clock.dart';
import 'package:hanguk_online/design_system/navigation.dart';
import 'package:hanguk_online/design_system/tokens.dart';
import 'package:hanguk_online/design_system/widgets/glass.dart';
import 'package:hanguk_online/design_system/widgets/app_shell.dart';
import 'package:hanguk_online/design_system/widgets/command_dock.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/lessons/presentation/dashboard_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/live_room_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/recordings_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/schedule_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_dashboard_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_finance_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_groups_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_payments_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_students_screen.dart';
import 'package:hanguk_online/features/staff/presentation/admin_teachers_screen.dart';
import 'package:hanguk_online/features/staff/presentation/super_admin_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_dashboard_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_grading_screen.dart';
import 'package:hanguk_online/features/staff/presentation/teacher_students_screen.dart';
import 'package:hanguk_online/main.dart';

/// Every screen, at every width the app can be opened at.
///
/// One size proves nothing. The app ships to a 1440pt desktop window that the
/// user is free to drag down to half a laptop screen, and to phones from 320
/// to 430 — and each of the three layout branches was written while looking
/// at one of those. Checking a screen at the width it was drawn for is how
/// the timetable's edit button ended up existing only above 1180, how the
/// dock slid over the logo at 760, and how a lesson title on a 390pt phone
/// came out as "Koreys tili · Suhb…": all three were correct at the size
/// somebody looked at.
///
/// A Flutter overflow is a caught exception, so a screen that does not fit
/// fails here by itself — there is nothing to assert. What follows each sweep
/// is the part an overflow does not catch: text silently cut short, chrome
/// drawn over chrome, a control below a fold that does not scroll.
void main() {
  /// Sixteen widths, not three. The boundaries (759/760, 1179/1180) are in
  /// here on purpose: every layout bug found so far lived one pixel inside a
  /// branch nobody had opened the app at.
  const sizes = <Size>[
    Size(320, 640), // iPhone SE 1, the narrowest thing that runs this
    Size(360, 740), // the common budget Android in Tashkent
    Size(375, 812),
    Size(390, 844), // iPhone 14
    Size(414, 896),
    Size(430, 932), // iPhone 15 Pro Max
    Size(600, 960), // small tablet, still the compact branch
    Size(744, 1133), // iPad mini portrait
    Size(759, 1024), // last pixel of compact
    Size(760, 1024), // first pixel of medium
    Size(820, 1180),
    Size(900, 700), // a desktop window on half a laptop screen
    Size(1024, 768),
    Size(1179, 800), // last pixel of medium
    Size(1180, 820), // first pixel of expanded
    Size(1440, 920), // the size the design was drawn at
  ];

  setUpAll(() async {
    initializeDateFormatting('uz');
    // The default test font is roughly twice as wide as Inter, which invents
    // overflows the app does not have — and hides the ones it does.
    await _loadBundledFonts();
  });

  // The demo fixtures are relative to the wall clock, so what is "today" and
  // which lesson is live changes with the hour the suite runs at.
  setUp(() => hkNow = () => DateTime(2026, 9, 21, 12, 0));
  tearDown(() => hkNow = DateTime.now);

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    required Size size,
    String role = 'student',
    double textScale = 1.0,
    List<Lesson>? todaysLessons,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          profileProvider.overrideWith((ref) async => UserProfile(
                id: 'stress',
                fullName: 'Aziza Karimova',
                initials: 'AK',
                role: role,
                level: role == 'student' ? 2 : null,
              )),
          if (todaysLessons != null)
            todaysLessonsProvider.overrideWith((ref) async => todaysLessons),
        ],
        child: MaterialApp.router(
          theme: hangukTheme,
          locale: hkLocale,
          supportedLocales: hkSupportedLocales,
          localizationsDelegates: hkLocalizationsDelegates,
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

  /// Pumps one screen at all sixteen widths and fails naming the width.
  void sweep(String name, Widget Function() screen, {String role = 'student'}) {
    testWidgets('$name fits every width', (tester) async {
      for (final size in sizes) {
        await pump(tester, screen(), size: size, role: role);
        expect(
          tester.takeException(),
          isNull,
          reason: '$name overflows at ${size.width.toInt()}'
              '×${size.height.toInt()}',
        );
      }
    });
  }

  group('direction 1 — every screen at sixteen widths', () {
    sweep('the dashboard', () => const DashboardScreen());
    sweep('the timetable', () => const ScheduleScreen());
    sweep('the recordings shelf', () => const RecordingsScreen());
    sweep('the live room', () => const LiveRoomScreen());
    sweep("the teacher's home", () => const TeacherDashboardScreen(),
        role: 'teacher');
    sweep("the teacher's roster", () => const TeacherStudentsScreen(),
        role: 'teacher');
    sweep('the grading queue', () => const TeacherGradingScreen(),
        role: 'teacher');
    sweep("the admin's home", () => const AdminDashboardScreen(),
        role: 'admin');
    sweep('the student list', () => const AdminStudentsScreen(), role: 'admin');
    sweep('the teacher list', () => const AdminTeachersScreen(), role: 'admin');
    sweep('the group list', () => const AdminGroupsScreen(), role: 'admin');
    sweep('payments', () => const AdminPaymentsScreen(), role: 'admin');
    sweep('finance', () => const AdminFinanceScreen(), role: 'admin');
    // The owner's own account. Its dock carries ten sections — half as wide
    // again as anybody else's — so it is the one that runs out of room first.
    sweep('the owner\'s panel', () => const SuperAdminScreen(),
        role: 'superadmin');
    sweep('the owner on the timetable', () => const ScheduleScreen(),
        role: 'superadmin');
  });

  group('direction 2 — a phone with larger text', () {
    // Android's "Font size" slider and iOS's Display Zoom both land here. The
    // app has no control over it and every fixed-height row has to survive it.
    for (final scale in [1.15, 1.3]) {
      testWidgets('the dashboard at ×$scale', (tester) async {
        for (final size in [const Size(360, 740), const Size(390, 844)]) {
          await pump(tester, const DashboardScreen(),
              size: size, textScale: scale);
          expect(tester.takeException(), isNull,
              reason: 'dashboard at ×$scale, ${size.width.toInt()}pt');
        }
      });

      testWidgets('the timetable at ×$scale', (tester) async {
        await pump(tester, const ScheduleScreen(),
            size: const Size(390, 844), textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('direction 3 — the lesson title is not squeezed off the row', () {
    // What the owner saw on his phone: "Koreys tili · Suhbat amaliyoti" cut
    // to "Koreys tili · Suhb…" because a "Rejalashtirilgan" pill sat on the
    // same line and took its natural width first.
    const title = 'Koreys tili · Suhbat amaliyoti';

    Future<void> row(WidgetTester tester, Size size) async {
      await pump(
        tester,
        const DashboardScreen(),
        size: size,
        todaysLessons: [
          Lesson(
            id: 'l-1',
            title: title,
            category: 'Suhbat',
            startsAt: DateTime(2026, 9, 21, 14, 0),
            durationMinutes: 60,
            status: LessonStatus.scheduled,
            autoRecord: true,
            enrolledCount: 12,
            teacher: const Teacher(
              id: 't-1',
              fullName: 'Nodira Rahimova',
              initials: 'NR',
            ),
          ),
        ],
      );
    }

    /// The row's own copy of the title. The hero card above the timetable
    /// prints the same string in the display face, so the finder has to name
    /// the row's style to tell them apart.
    Finder titleText() => find.byWidgetPredicate(
          (w) => w is Text && w.data == title && w.style == HkType.cardTitle,
        );

    testWidgets('on every phone, in full', (tester) async {
      for (final size in [
        const Size(320, 640),
        const Size(360, 740),
        const Size(390, 844),
        const Size(430, 932),
      ]) {
        await row(tester, size);
        expect(
          tester.renderObject<RenderParagraph>(titleText()).didExceedMaxLines,
          isFalse,
          reason: 'cut short at ${size.width.toInt()}pt — the title is the '
              'one thing the row exists to show',
        );
      }
    });

    testWidgets('because the pill is not on its line', (tester) async {
      for (final size in [const Size(320, 640), const Size(390, 844)]) {
        await row(tester, size);
        final pill = tester.getRect(
          find.widgetWithText(HkPill, 'Rejalashtirilgan'),
        );
        expect(
          pill.top,
          greaterThanOrEqualTo(tester.getRect(titleText()).bottom),
          reason: 'the pill takes its width first, so it cannot share a line',
        );
      }
    });

    testWidgets('and on a desktop it still shares one', (tester) async {
      // The other direction: the pill belongs on the row where there is room
      // for it, and a phone-shaped row on a 1440pt screen would be a waste.
      await row(tester, const Size(1440, 920));
      final pill = tester.getRect(
        find.widgetWithText(HkPill, 'Rejalashtirilgan'),
      );
      expect(pill.top, lessThan(tester.getRect(titleText()).bottom));
    });
  });

  group('direction 4 — the bottom bar is chrome, not glass', () {
    testWidgets('nothing scrolls through the tab labels', (tester) async {
      await pump(tester, const DashboardScreen(), size: const Size(390, 844));

      final bar = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(CompactNavBar),
              matching: find.byType(Container),
            )
            .first,
      );
      final color = (bar.decoration! as BoxDecoration).color!;
      expect(
        color.a,
        1.0,
        reason: 'there is no blur behind the bar, so alpha is a hole in it',
      );
    });
  });

  group('direction 5 — the dock does not cover the logo', () {
    // At `medium` the dock was given the whole window to centre itself in,
    // and the logo capsule is pinned to the left of that same row.
    for (final width in [760.0, 900.0, 1024.0, 1179.0, 1180.0, 1440.0]) {
      testWidgets('at ${width.toInt()}pt', (tester) async {
        await pump(tester, const DashboardScreen(), size: Size(width, 900));

        final logo = tester.getRect(find.byType(LogoCapsule));
        final dock = tester.getRect(find.byType(CommandDock));
        expect(
          dock.left,
          greaterThanOrEqualTo(logo.right),
          reason: 'the dock overlaps "Hanguk Academy" at ${width.toInt()}pt',
        );
      });
    }
  });

  group('direction 6 — the live room can be reached to the bottom', () {
    // The room stacks a stage, a rail and the control bar. Above 1180 they
    // fit; below it they did not, and the page did not scroll — so the
    // microphone and "Chiqish" were simply below the fold.
    for (final size in [
      const Size(390, 844),
      const Size(760, 1024),
      const Size(900, 700),
      const Size(1179, 800),
    ]) {
      testWidgets('at ${size.width.toInt()}pt it scrolls', (tester) async {
        await pump(tester, const LiveRoomScreen(), size: size);
        expect(
          tester.widget<AppShell>(find.byType(AppShell)).scrollable,
          isTrue,
          reason: 'nothing below the fold is reachable otherwise',
        );
      });
    }

    testWidgets('at the design width it does not', (tester) async {
      await pump(tester, const LiveRoomScreen(), size: const Size(1440, 920));
      expect(
        tester.widget<AppShell>(find.byType(AppShell)).scrollable,
        isFalse,
        reason: 'the room manages its own height where it fits',
      );
    });
  });

  group('direction 7 — nothing is painted off the side of the window', () {
    // A `Row` that does not fit throws; a `Wrap` or a `Stack` that does not
    // fit says nothing at all and simply paints past its parent. This walks
    // the rendered text instead of trusting the framework to complain.
    Future<void> check(WidgetTester tester, Widget screen, Size size,
        {String role = 'student'}) async {
      await pump(tester, screen, size: size, role: role);
      for (final element in tester.allElements.toList()) {
        final paragraph = element.renderObject;
        if (paragraph is! RenderParagraph) continue;
        if (!paragraph.attached || paragraph.debugNeedsLayout) continue;
        if (_scrollsSideways(element)) continue;
        final left = paragraph.localToGlobal(Offset.zero).dx;
        final text = paragraph.text.toPlainText();
        expect(
          left + paragraph.size.width,
          lessThanOrEqualTo(size.width + 0.5),
          reason: '"$text" runs off the right edge '
              'at ${size.width.toInt()}pt',
        );
        expect(left, greaterThanOrEqualTo(-0.5),
            reason: '"$text" starts off the left edge '
                'at ${size.width.toInt()}pt');
      }
    }

    for (final size in [
      const Size(320, 640),
      const Size(390, 844),
      const Size(900, 700),
      const Size(1440, 920),
    ]) {
      testWidgets('the dashboard at ${size.width.toInt()}pt',
          (t) => check(t, const DashboardScreen(), size));
      testWidgets('the timetable at ${size.width.toInt()}pt',
          (t) => check(t, const ScheduleScreen(), size));
      testWidgets('the student list at ${size.width.toInt()}pt',
          (t) => check(t, const AdminStudentsScreen(), size, role: 'admin'));
    }
  });

  group('direction 8 — the library has a way in from every dock', () {
    // The owner is an administrator, and the admin dock had no "Yozuvlar"
    // entry at all: the person asking why a recording had not appeared was
    // the one person who could not open the screen it appears on.
    for (final role in ['student', 'teacher', 'admin', 'superadmin']) {
      test(role, () {
        expect(
          HkNav.forRole(role).map((d) => d.route),
          contains('/recordings'),
          reason: 'a $role cannot reach the recordings',
        );
      });
    }
  });

  group('direction 9 — every category a lesson can have has a chip', () {
    test('the shelf filters on the timetable\'s own list', () {
      for (final category in kLessonCategories) {
        expect(
          kRecordingCategories,
          contains(category),
          reason: '"$category" is a category the timetable writes and the '
              'recordings shelf cannot filter to',
        );
      }
      expect(kRecordingCategories.first, isNull, reason: '"Barchasi" first');
    });
  });

  group('direction 10 — the page heading is not scrolled through', () {
    Color scrimTop(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find.byKey(AppShell.headingScrimKey),
      );
      final gradient =
          (box.decoration as BoxDecoration).gradient! as LinearGradient;
      return gradient.colors.first;
    }

    testWidgets('invisible until something moves', (tester) async {
      await pump(tester, const DashboardScreen(), size: const Size(1440, 920));
      expect(scrimTop(tester).a, 0.0,
          reason: 'the screen as drawn has no band across the top');
    });

    testWidgets('and opaque once the page is scrolled', (tester) async {
      await pump(tester, const DashboardScreen(), size: const Size(1440, 920));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -200),
      );
      await tester.pump();
      expect(
        scrimTop(tester).a,
        greaterThan(0.9),
        reason: 'text passing behind the heading has to be covered',
      );
    });

    testWidgets('and it fades back out again', (tester) async {
      await pump(tester, const DashboardScreen(), size: const Size(1440, 920));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -200),
      );
      await tester.pump();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 400),
      );
      await tester.pump();
      expect(scrimTop(tester).a, 0.0);
    });
  });
}

/// Whether this sits inside something that scrolls sideways — the dock on a
/// phone, say — where running past the window is the point rather than a bug.
///
/// Asked of the element tree rather than the render tree: `SingleChildScrollView`
/// renders through a private viewport that exposes no axis, while every
/// scrollable there is builds a [Scrollable] that does.
bool _scrollsSideways(Element element) {
  var sideways = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Scrollable &&
        (widget.axisDirection == AxisDirection.left ||
            widget.axisDirection == AxisDirection.right)) {
      sideways = true;
      return false;
    }
    return true;
  });
  return sideways;
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

  final iconFont = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}'
    '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFont.existsSync()) {
    await load('MaterialIcons', [iconFont.path]);
  }

  await load('Inter', [
    for (final w in [400, 500, 600, 700, 800, 900]) 'assets/fonts/Inter-$w.ttf',
  ]);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-600.ttf']);
  await load('NotoSansKR', [
    'assets/fonts/NotoSansKR-500.ttf',
    'assets/fonts/NotoSansKR-700.ttf',
  ]);
}
