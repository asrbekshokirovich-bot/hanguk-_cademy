import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/core/router.dart';
import 'package:hanguk_online/design_system/navigation.dart';
import 'package:hanguk_online/features/auth/data/auth_repository.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/staff/presentation/admin_dashboard_screen.dart';
import 'package:hanguk_online/features/staff/presentation/super_admin_screen.dart';
import 'package:hanguk_online/main.dart';

/// The admin tier is split in two, and the split is about the money.
///
/// A superadmin is the school owner: it does everything an admin does, plus
/// the two things an admin may not — it issues the administrator accounts,
/// and it reads the books. The database draws exactly that line
/// (`ol_is_super()`), and deliberately lets a superadmin outrank an admin
/// everywhere else, because issuing accounts needs that reach.
///
/// The app used to draw a second line on top of it, holding the top tier to
/// those two screens alone. It read well and worked badly: the owner could
/// not open the live room to end a lesson a teacher had left on air, or look
/// at the timetable he had just been asked about, without signing in as his
/// own administrator. What this file guards now is the line that is left —
/// an admin does not reach the money, and a superadmin is not shut out of
/// the school day.
UserProfile _profile(String role) => UserProfile(
      id: 'u-$role',
      fullName: role == 'superadmin' ? 'Asrbek' : 'Ofis xodimi',
      initials: 'AA',
      role: role,
    );

/// An account that is past the login screen, with no Supabase behind it.
///
/// The redirect short-circuits in demo mode — there is nothing to sign in to
/// — so the role rules are unreachable without this.
class _SignedIn extends AuthRepository {
  _SignedIn() : super(null);

  @override
  bool get isDemo => false;

  @override
  bool get isSignedIn => true;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('uz');
    // The redirect tests below walk into the dense staff screens — the
    // roster's table, the week grid. flutter_test's stand-in font draws every
    // glyph as a fixed-width box roughly twice Inter's width, so those
    // screens overflow here while fitting perfectly in the product. Loading
    // the faces the app ships measures what the app measures.
    await _loadBundledFonts();
  });

  group('navigation', () {
    test('the top tier’s dock carries the admin’s, and two more', () {
      final admin = HkNav.forRole('admin').map((d) => d.route).toSet();
      final superAdmin = HkNav.forRole('superadmin').map((d) => d.route);

      // Regression: it was ['Adminlar', 'Moliya'] and nothing else, so the
      // owner had no way in to the roster, the timetable or a live room.
      expect(superAdmin.toSet(), containsAll(admin));
      expect(superAdmin, contains('/admin/finance'));
      expect(superAdmin, contains('/super'));
      // The live room is the one the admin dock has no entry for at all —
      // an administrator does not teach; the owner does end a lesson.
      expect(superAdmin, contains('/live'));
      expect(admin, isNot(contains('/live')));
    });

    test('the money screens stay out of the admin’s dock', () {
      final admin = HkNav.forRole('admin').map((d) => d.route).toSet();

      // Taking a student's fee is front-desk work and stays. The totals and
      // the administrator accounts are the two the tier above keeps.
      expect(admin, contains('/admin/payments'));
      expect(admin, isNot(contains('/admin/finance')));
      expect(admin, isNot(contains('/super')));
    });

    test('the top tier’s routes are the ones an admin may not open', () {
      expect(HkNav.isSuperAdminRoute('/super'), isTrue);
      expect(HkNav.isSuperAdminRoute('/admin/finance'), isTrue);
      // Read one way only now: these are what an *admin* is turned away
      // from, not a fence around the superadmin. It opens the rest as well.
      expect(HkNav.isSuperAdminRoute('/admin/students'), isFalse);
      expect(HkNav.isSuperAdminRoute('/schedule'), isFalse);
      // Finance is still an admin route, so a teacher is turned away by the
      // broader check whichever order they are evaluated in.
      expect(HkNav.isAdminRoute('/admin/finance'), isTrue);
    });

    test('each tier lands on its own home', () {
      // Both land on the dashboard now: the owner opens the app to run the
      // school day, not to look at the ledger.
      expect(HkNav.homeFor('superadmin'), '/admin');
      expect(HkNav.homeFor('admin'), '/admin');
      expect(HkNav.homeFor('teacher'), '/teacher');
    });

    test('the dock highlights the section the top tier is actually on', () {
      // `currentFor` picks the longest matching route. With `/admin` now in
      // this dock, a superadmin on the roster must light up "Talabalar" and
      // not "Boshqaruv".
      expect(
        HkNav.currentFor('superadmin', '/admin/students')?.label,
        'Talabalar',
      );
      expect(HkNav.currentFor('superadmin', '/admin')?.label, 'Boshqaruv');
      expect(HkNav.currentFor('superadmin', '/admin/finance')?.label, 'Moliya');
      expect(HkNav.currentFor('superadmin', '/super')?.label, 'Adminlar');
    });
  });

  group('the router’s redirect', () {
    /// Where does the real router send an account that asks for [location]?
    ///
    /// The redirect leaves demo mode alone — there is nothing to sign in to,
    /// so it lets everything through and the role rules never run. Faking a
    /// signed-in session is therefore the only way to reach them.
    Future<String> landsOn(
      WidgetTester tester,
      String role,
      String location,
    ) async {
      tester.view.physicalSize = const Size(1440, 920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late final GoRouter router;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // The repositories stay in demo mode, so the screens the router
            // lands on render from the fixtures.
            supabaseClientProvider.overrideWithValue(null),
            authRepositoryProvider.overrideWithValue(_SignedIn()),
            profileProvider.overrideWith((ref) async => _profile(role)),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              router = ref.watch(appRouterProvider);
              return MaterialApp.router(
                theme: hangukTheme,
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      router.go(location);
      // pump, not pumpAndSettle: the live room's ambient background and its
      // "davom etmoqda" clock never stop ticking, so nothing there settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      return router.state.uri.path;
    }

    testWidgets('lets the owner into the school day', (tester) async {
      // Regression. A rule here used to send the top tier home from anything
      // outside /super and /admin/finance, which meant the school's owner
      // could not open a live room — and so could not end a lesson a teacher
      // had left running.
      expect(await landsOn(tester, 'superadmin', '/live'), '/live');
      expect(
        await landsOn(tester, 'superadmin', '/admin/students'),
        '/admin/students',
      );
      expect(await landsOn(tester, 'superadmin', '/schedule'), '/schedule');
    });

    testWidgets('still keeps an admin out of the money', (tester) async {
      // The half of the split that earns its keep, and the reason the mirror
      // rule stayed. `ol_is_super()` refuses these in SQL as well.
      expect(await landsOn(tester, 'admin', '/admin/finance'), '/admin');
      expect(await landsOn(tester, 'admin', '/super'), '/admin');
    });

    testWidgets('still keeps a student out of the staff panels',
        (tester) async {
      expect(await landsOn(tester, 'student', '/admin/students'), '/');
      expect(await landsOn(tester, 'student', '/teacher'), '/');
    });
  });

  group('profile', () {
    test('a superadmin is an admin, and says which it is', () {
      final s = _profile('superadmin');
      expect(s.isSuperAdmin, isTrue);
      expect(s.isAdmin, isTrue, reason: 'outranks admin everywhere');
      expect(s.isStaff, isTrue);
      expect(s.subtitle, 'Super admin');

      final a = _profile('admin');
      expect(a.isSuperAdmin, isFalse);
      expect(a.isAdmin, isTrue);
      expect(a.subtitle, 'Administrator');
    });
  });

  Future<void> pumpDashboard(
    WidgetTester tester,
    Widget screen,
    String role,
  ) async {
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
            routes: [
              GoRoute(path: '/', builder: (_, _) => screen),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the admin dashboard carries no money at all', (tester) async {
    await pumpDashboard(tester, const AdminDashboardScreen(), 'admin');

    expect(find.text('Bu oygi tushum'), findsNothing);
    // The overdue-payments alert used to route to /admin/finance. Offering
    // someone an alert they cannot open is worse than not offering it.
    expect(find.textContaining('to‘lov kechikkan'), findsNothing);

    // Still the same screen otherwise.
    expect(find.text('Faol talabalar'), findsOneWidget);
    expect(find.text('Haftalik darslar'), findsOneWidget);
  });

  testWidgets('the superadmin screen lists administrators only',
      (tester) async {
    await pumpDashboard(tester, const SuperAdminScreen(), 'superadmin');

    expect(find.text('Adminlar'), findsWidgets);
    expect(find.text('Yangi admin'), findsOneWidget);
    // The demo roster carries students and teachers too; this screen is about
    // the accounts that carry rights.
    expect(find.text('Ofis xodimi'), findsOneWidget);
    expect(find.text('Asrbek'), findsWidgets);
    expect(find.text('Aziza Karimova'), findsNothing);
    expect(find.text('Jasur Karimov'), findsNothing);
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
