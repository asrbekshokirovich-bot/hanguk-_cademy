import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 moved StateProvider out of the main barrel. Both remaining uses
// here are genuinely a single mutable value driven by a tap (the active
// filter chip, the visible week), which is what StateProvider is for.
import 'package:flutter_riverpod/legacy.dart';

import '../domain/models.dart';
import 'lessons_repository.dart';
import '../../../core/clock.dart';

final profileProvider = FutureProvider<UserProfile>((ref) {
  return ref.watch(lessonsRepositoryProvider).currentProfile();
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) {
  return ref.watch(lessonsRepositoryProvider).dashboardStats();
});

final todaysLessonsProvider = FutureProvider<List<Lesson>>((ref) {
  return ref.watch(lessonsRepositoryProvider).todaysLessons();
});

/// Polled rather than subscribed to. A realtime channel for a single boolean
/// ("is anything live?") is a websocket per client for the whole session; a
/// 30-second poll is well inside how fast a student needs to learn a lesson
/// started, and it costs one indexed row read.
final liveLessonProvider = FutureProvider<Lesson?>((ref) {
  return ref.watch(lessonsRepositoryProvider).liveLesson();
});

final lessonByIdProvider =
    FutureProvider.family<Lesson?, String>((ref, id) {
  return ref.watch(lessonsRepositoryProvider).lessonById(id);
});

/// Which filter chip is active in the recordings library. `null` = "Barchasi".
final recordingsFilterProvider = StateProvider<String?>((ref) => null);

final recordingsProvider = FutureProvider<List<Recording>>((ref) {
  final category = ref.watch(recordingsFilterProvider);
  return ref.watch(lessonsRepositoryProvider).recordings(category: category);
});

/// The three most recent recordings, for the dashboard's "So'nggi yozuvlar".
final recentRecordingsProvider = FutureProvider<List<Recording>>((ref) async {
  final all = await ref.watch(lessonsRepositoryProvider).recordings();
  return all.take(3).toList();
});

final recordingByIdProvider =
    FutureProvider.family<Recording?, String>((ref, id) {
  return ref.watch(lessonsRepositoryProvider).recordingById(id);
});

final materialsProvider =
    FutureProvider.family<List<LessonMaterial>, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).materials(lessonId);
});

final quizProvider =
    FutureProvider.family<LessonQuiz?, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).quiz(lessonId);
});

final assignmentProvider =
    FutureProvider.family<Assignment?, String>((ref, lessonId) {
  return ref.watch(lessonsRepositoryProvider).assignment(lessonId);
});

/// Start of the week currently shown in the schedule, as a Monday.
final scheduleWeekStartProvider = StateProvider<DateTime>((ref) {
  final now = hkNow();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - 1));
});

final weekLessonsProvider = FutureProvider<List<Lesson>>((ref) {
  final start = ref.watch(scheduleWeekStartProvider);
  return ref
      .watch(lessonsRepositoryProvider)
      .lessonsBetween(start, start.add(const Duration(days: 7)));
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  return ref.watch(lessonsRepositoryProvider).notifications();
});

/// Drives the bell's red dot. Derived from the list rather than a separate
/// count query — the panel needs the rows anyway, and two sources would drift
/// (dot still red after the panel says everything is read).
final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value;
  if (list == null) return 0;
  return list.where((n) => n.isUnread).length;
});

/// What the user has typed into the search sheet.
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<SearchResults>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return SearchResults.empty;
  return ref.watch(lessonsRepositoryProvider).search(query);
});
