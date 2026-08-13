import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lessons/data/providers.dart';
import '../../lessons/domain/models.dart';
import '../domain/staff_models.dart';
import 'staff_repository.dart';

/// Puts a lesson on air or takes it off, then refreshes every provider that
/// renders a status.
///
/// Centralised because the invalidation list is the easy half to get wrong:
/// a teacher starts the lesson from their dashboard, and the live dot in the
/// dock, the student's hero banner and the week grid all have to agree. A
/// screen that invalidated only its own provider would look correct while the
/// rest of the app went on claiming the lesson had not started.
Future<void> setLessonStatus(
  WidgetRef ref,
  String lessonId,
  LessonStatus status,
) async {
  await ref.read(staffRepositoryProvider).setLessonStatus(lessonId, status);
  ref.invalidate(liveLessonProvider);
  ref.invalidate(todaysLessonsProvider);
  ref.invalidate(weekLessonsProvider);
  ref.invalidate(dashboardStatsProvider);
  ref.invalidate(teacherStatsProvider);
  ref.invalidate(adminKpisProvider);
}

final teacherStatsProvider = FutureProvider<TeacherStats>((ref) {
  return ref.watch(staffRepositoryProvider).teacherStats();
});

final myStudentsProvider = FutureProvider<List<TeacherStudent>>((ref) {
  return ref.watch(staffRepositoryProvider).myStudents();
});

/// The grading queue, ungraded first.
final submissionsProvider = FutureProvider<List<Submission>>((ref) {
  return ref.watch(staffRepositoryProvider).submissions();
});

/// The four cards on the teacher's home screen need the same list the
/// grading screen shows, so it is derived rather than fetched twice.
final pendingSubmissionsProvider = Provider<List<Submission>>((ref) {
  final all = ref.watch(submissionsProvider).value ?? const <Submission>[];
  return all.where((s) => !s.isGraded).toList();
});

final adminKpisProvider = FutureProvider<AdminKpis>((ref) {
  return ref.watch(staffRepositoryProvider).adminKpis();
});

final teacherRosterProvider = FutureProvider<List<TeacherRosterEntry>>((ref) {
  return ref.watch(staffRepositoryProvider).teacherRoster();
});

final adminStudentsProvider = FutureProvider<List<AdminStudent>>((ref) {
  return ref.watch(staffRepositoryProvider).adminStudents();
});

final paymentsProvider = FutureProvider<List<Payment>>((ref) {
  return ref.watch(staffRepositoryProvider).payments();
});

final plansProvider = FutureProvider<List<PaymentPlan>>((ref) {
  return ref.watch(staffRepositoryProvider).plans();
});

final groupsProvider = FutureProvider<List<StudyGroup>>((ref) {
  return ref.watch(staffRepositoryProvider).groups();
});
