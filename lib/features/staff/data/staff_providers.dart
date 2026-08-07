import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/staff_models.dart';
import 'staff_repository.dart';

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
