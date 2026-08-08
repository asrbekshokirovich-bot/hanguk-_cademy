import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design_system/navigation.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/lessons/data/providers.dart';
import '../features/lessons/presentation/dashboard_screen.dart';
import '../features/lessons/presentation/lesson_detail_screen.dart';
import '../features/lessons/presentation/live_room_screen.dart';
import '../features/lessons/presentation/recordings_screen.dart';
import '../features/lessons/presentation/schedule_screen.dart';
import '../features/staff/presentation/admin_dashboard_screen.dart';
import '../features/staff/presentation/admin_finance_screen.dart';
import '../features/staff/presentation/admin_groups_screen.dart';
import '../features/staff/presentation/admin_students_screen.dart';
import '../features/staff/presentation/admin_teachers_screen.dart';
import '../features/staff/presentation/teacher_dashboard_screen.dart';
import '../features/staff/presentation/teacher_grading_screen.dart';
import '../features/staff/presentation/teacher_students_screen.dart';

/// Real routes rather than the prototype's `setState({view})`, so the desktop
/// window's back/forward and the web build's URL bar both behave.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  // Built once and kept: rebuilding the GoRouter on every auth event would
  // throw away the navigation stack, so the router is refreshed through a
  // listenable instead.
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  // The redirect consults the profile, which loads asynchronously after sign
  // in and changes again when the password gate is cleared. Without this the
  // router would evaluate once against a null profile and stay there.
  ref.listen(profileProvider, (_, _) => refresh.poke());

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;

      // Demo mode has nothing to sign in to; the login screen would be a
      // dead end with no account behind it.
      if (auth.isDemo) {
        return const ['/login', '/change-password'].contains(location)
            ? '/'
            : null;
      }

      if (!auth.isSignedIn) {
        return location == '/login' ? null : '/login';
      }
      if (location == '/login') return '/';

      // Signed in. Everything past this point needs the profile, which
      // arrives a moment after the session; hold still rather than bouncing
      // the user somewhere on incomplete information.
      final profile = ref.read(profileProvider).value;
      if (profile == null) return null;

      // An admin-issued password is a password the admin has seen. Nothing
      // else in the app is reachable until it has been replaced.
      if (profile.mustChangePassword) {
        return location == '/change-password' ? null : '/change-password';
      }
      if (location == '/change-password') return '/';

      // The staff panels are gated here as well as hidden from the dock: a
      // hidden menu item is not access control, and a bookmarked URL from a
      // demoted account would otherwise still open.
      if (HkNav.isSuperAdminRoute(location) && !profile.isSuperAdmin) {
        return HkNav.homeFor(profile.role);
      }
      if (HkNav.isAdminRoute(location) && !profile.isAdmin) {
        return HkNav.homeFor(profile.role);
      }
      if (HkNav.isTeacherRoute(location) && !profile.isStaff) {
        return HkNav.homeFor(profile.role);
      }

      // Each role has its own home. A teacher landing on the student
      // dashboard would see a screen built around lessons they are teaching,
      // framed as lessons they are attending.
      if (location == '/' && profile.role != 'student') {
        return HkNav.homeFor(profile.role);
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fade(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _fade(state, const DashboardScreen()),
      ),
      GoRoute(
        path: '/live',
        pageBuilder: (context, state) => _fade(state, const LiveRoomScreen()),
      ),
      GoRoute(
        path: '/recordings',
        pageBuilder: (context, state) =>
            _fade(state, const RecordingsScreen()),
        routes: [
          GoRoute(
            path: ':id',
            pageBuilder: (context, state) => _fade(
              state,
              LessonDetailScreen(recordingId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/schedule',
        pageBuilder: (context, state) => _fade(state, const ScheduleScreen()),
      ),
      GoRoute(
        path: '/change-password',
        pageBuilder: (context, state) =>
            _fade(state, const ChangePasswordScreen()),
      ),
      GoRoute(
        path: '/teacher',
        pageBuilder: (context, state) =>
            _fade(state, const TeacherDashboardScreen()),
      ),
      GoRoute(
        path: '/teacher/students',
        pageBuilder: (context, state) =>
            _fade(state, const TeacherStudentsScreen()),
      ),
      GoRoute(
        path: '/teacher/grading',
        pageBuilder: (context, state) =>
            _fade(state, const TeacherGradingScreen()),
      ),
      GoRoute(
        path: '/admin',
        pageBuilder: (context, state) =>
            _fade(state, const AdminDashboardScreen()),
      ),
      GoRoute(
        path: '/admin/students',
        pageBuilder: (context, state) =>
            _fade(state, const AdminStudentsScreen()),
      ),
      GoRoute(
        path: '/admin/teachers',
        pageBuilder: (context, state) =>
            _fade(state, const AdminTeachersScreen()),
      ),
      GoRoute(
        path: '/admin/groups',
        pageBuilder: (context, state) =>
            _fade(state, const AdminGroupsScreen()),
      ),
      GoRoute(
        path: '/admin/finance',
        pageBuilder: (context, state) =>
            _fade(state, const AdminFinanceScreen()),
      ),
    ],
  );
});

/// Bridges Supabase's auth stream to the `Listenable` GoRouter wants.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  /// Re-run the redirect for a reason other than an auth event.
  void poke() => notifyListeners();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// A cross-fade rather than the platform default. The floating dock stays put
/// across a navigation, so a slide transition would drag the whole shell —
/// including the chrome that did not change — sideways.
CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
