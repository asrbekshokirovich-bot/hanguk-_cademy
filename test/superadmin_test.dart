import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/design_system/navigation.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/staff/presentation/admin_dashboard_screen.dart';
import 'package:hanguk_online/features/staff/presentation/super_admin_screen.dart';
import 'package:hanguk_online/main.dart';

/// The admin tier is split in two, and the two docks do not overlap.
///
/// A superadmin does exactly two things — issues administrator accounts, and
/// holds the money. An admin does everything else. The database enforces the
/// money and the account rules (`ol_is_super()`), but it deliberately lets a
/// superadmin outrank an admin everywhere, because issuing accounts needs
/// that reach. So keeping the top tier *out* of the school day is the app's
/// job alone, and that is what most of this file covers.
UserProfile _profile(String role) => UserProfile(
      id: 'u-$role',
      fullName: role == 'superadmin' ? 'Asrbek' : 'Ofis xodimi',
      initials: 'AA',
      role: role,
    );

void main() {
  setUpAll(() => initializeDateFormatting('uz'));

  group('navigation', () {
    test('the top tier has two sections and they are its own', () {
      final superAdmin =
          HkNav.forRole('superadmin').map((d) => d.label).toList();

      expect(superAdmin, orderedEquals(['Adminlar', 'Moliya']));
    });

    test('the two docks do not overlap', () {
      final admin = HkNav.forRole('admin').map((d) => d.route).toSet();
      final superAdmin = HkNav.forRole('superadmin').map((d) => d.route).toSet();

      // A superadmin who could also open the roster and the timetable would
      // make the split decorative — it would just be an admin with extras.
      expect(admin.intersection(superAdmin), isEmpty);
      expect(admin, isNot(contains('/admin/finance')));
      expect(superAdmin, isNot(contains('/admin/students')));
    });

    test('the top tier’s routes are also the only ones it opens', () {
      expect(HkNav.isSuperAdminRoute('/super'), isTrue);
      expect(HkNav.isSuperAdminRoute('/admin/finance'), isTrue);
      expect(HkNav.isSuperAdminRoute('/admin/students'), isFalse);
      expect(HkNav.isSuperAdminRoute('/schedule'), isFalse);
      // Finance is still an admin route, so a teacher is turned away by the
      // broader check whichever order they are evaluated in.
      expect(HkNav.isAdminRoute('/admin/finance'), isTrue);
    });

    test('each tier lands on its own home', () {
      expect(HkNav.homeFor('superadmin'), '/super');
      expect(HkNav.homeFor('admin'), '/admin');
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
