import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 moved StateProvider out of the main barrel. Both remaining uses
// here are genuinely a single mutable value driven by a tap (the active
// filter chip, the visible week), which is what StateProvider is for.
import 'package:flutter_riverpod/legacy.dart';

import '../domain/models.dart';
import 'lessons_repository.dart';

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
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - 1));
});

final weekLessonsProvider = FutureProvider<List<Lesson>>((ref) {
  final start = ref.watch(scheduleWeekStartProvider);
  return ref
      .watch(lessonsRepositoryProvider)
      .lessonsBetween(start, start.add(const Duration(days: 7)));
});
