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
import 'package:hanguk_online/main.dart';

/// The admin tier is split in two. A superadmin issues administrator accounts
/// and is the only role that sees money; a plain admin runs the school day.
///
/// The database enforces both — `ol_is_super()` guards the payments policies
/// and the account RPCs — so these tests cover the half that lives in the app:
/// not offering an action that would only come back as an error.
UserProfile _profile(String role) => UserProfile(
      id: 'u-$role',
      fullName: role == 'superadmin' ? 'Asrbek' : 'Ofis xodimi',
      initials: 'AA',
      role: role,
    );

void main() {
  setUpAll(() => initializeDateFormatting('uz'));

  group('navigation', () {
    test('only the top tier is offered Moliya', () {
      final admin = HkNav.forRole('admin').map((d) => d.label);
      final superAdmin = HkNav.forRole('superadmin').map((d) => d.label);

      expect(admin, isNot(contains('Moliya')));
      expect(superAdmin, contains('Moliya'));

      // Otherwise the two are the same job: a superadmin who could not open
      // the roster would have to keep a second account to run the school.
      expect(
        superAdmin.where((l) => l != 'Moliya'),
        orderedEquals(admin),
      );
    });

    test('the finance route is gated on its own, not on being an admin', () {
      expect(HkNav.isSuperAdminRoute('/admin/finance'), isTrue);
      expect(HkNav.isSuperAdminRoute('/admin/students'), isFalse);
      // Still an admin route, so a teacher is turned away before the tier
      // check is ever reached.
      expect(HkNav.isAdminRoute('/admin/finance'), isTrue);
    });

    test('both tiers land on the same home', () {
      expect(HkNav.homeFor('superadmin'), '/admin');
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

  Future<void> pumpDashboard(WidgetTester tester, String role) async {
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
              GoRoute(path: '/', builder: (_, _) => const AdminDashboardScreen()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // Two tests rather than two pumps in one: pumping a second ProviderScope
  // into the same tree reuses the element and keeps the first override's
  // resolved value, so the assertion passes for the wrong reason.
  testWidgets('the top tier sees the revenue card', (tester) async {
    await pumpDashboard(tester, 'superadmin');
    expect(find.text('Bu oygi tushum'), findsOneWidget);
  });

  testWidgets('a plain admin does not', (tester) async {
    await pumpDashboard(tester, 'admin');
    expect(find.text('Bu oygi tushum'), findsNothing);
    // The rest of the dashboard is unchanged — this is one card removed, not
    // a different screen.
    expect(find.text('Faol talabalar'), findsOneWidget);
    expect(find.text('Haftalik darslar'), findsOneWidget);
  });

  testWidgets('an admin is not shown an alert they cannot open',
      (tester) async {
    // The overdue-payments alert routes to /admin/finance. Offering it to
    // someone the router will bounce is worse than not offering it.
    await pumpDashboard(tester, 'admin');
    expect(find.textContaining('to‘lov kechikkan'), findsNothing);
  });
}
