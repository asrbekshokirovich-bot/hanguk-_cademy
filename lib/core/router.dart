import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/lessons/presentation/dashboard_screen.dart';
import '../features/lessons/presentation/lesson_detail_screen.dart';
import '../features/lessons/presentation/live_room_screen.dart';
import '../features/lessons/presentation/recordings_screen.dart';
import '../features/lessons/presentation/schedule_screen.dart';

/// Real routes rather than the prototype's `setState({view})`, so the desktop
/// window's back/forward and the web build's URL bar both behave.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) =>
          _fade(state, const DashboardScreen()),
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
            LessonDetailScreen(
              recordingId: state.pathParameters['id']!,
            ),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/schedule',
      pageBuilder: (context, state) => _fade(state, const ScheduleScreen()),
    ),
  ],
);

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
