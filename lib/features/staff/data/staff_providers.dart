import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../auth/data/auth_repository.dart';
import '../../lessons/data/lessons_repository.dart';
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
  // The room reads the lesson through this one, and it is what decides
  // whether there is still a room to be in.
  ref.invalidate(lessonByIdProvider);
}

/// This account's `ol_teachers.id`, or null when it has no teacher row —
/// an admin, or a student who somehow reached a staff screen.
/// Every list below is `isAutoDispose: true`, and that is a fix rather than
/// a preference.
///
/// A Riverpod 3 provider is kept alive for the whole run by default, so each
/// of these was fetched **once per app launch**. Every screen here shows
/// something somebody else maintains: an administrator puts three students in
/// a group, and the teacher — whose app has been open since the morning — is
/// told "Sizga hali guruh biriktirilmagan" until they restart it. The
/// administrator sees their own change, because the dialog invalidates what
/// it wrote, which is exactly what makes the stale half so hard to believe.
///
/// Auto-disposing ties the data to the screen: leaving it drops the cache,
/// opening it asks again. The lesson-status providers keep their 20-second
/// tick instead, because those move on their own while somebody watches.
final myTeacherIdProvider = FutureProvider<String?>((ref) {
  // Rebound when the session changes: signing out and back in as somebody
  // else must not leave the previous teacher's id cached, or a lesson row
  // would still say "mine".
  ref.watch(authStateProvider);
  return ref.watch(staffRepositoryProvider).myTeacherId();
}, isAutoDispose: true);

/// Whether this account is the one teaching [lesson] — the test for the
/// controls that belong to whoever is running the lesson, not to staff at
/// large. An admin passes it for any lesson: they run the school day, and a
/// room left on air by a teacher who closed their laptop is theirs to clear.
bool ownsLesson(WidgetRef ref, Lesson lesson) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null || !profile.isStaff) return false;
  if (profile.isAdmin) return true;
  final mine = ref.watch(myTeacherIdProvider).value;
  return mine != null && lesson.teacher?.id == mine;
}

final teacherStatsProvider = FutureProvider<TeacherStats>((ref) {
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).teacherStats();
}, isAutoDispose: true);

final myStudentsProvider = FutureProvider<List<TeacherStudent>>((ref) {
  // Re-read on the roster tick as well as on re-entry: a teacher looking at
  // this screen while an administrator fills their group should not have to
  // know that leaving and coming back is what makes it true.
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).myStudents();
}, isAutoDispose: true);

/// The lessons this teacher can attach homework to.
///
/// A wide window rather than a tight one. This was a fortnight either side of
/// today, which sounded reasonable and told a teacher with a lesson three
/// weeks out that they had **no lessons at all** — the dialog's empty state
/// then sends them to an administrator who has already done the work. A term
/// is the right unit; the query is bounded so it cannot run away on a school
/// with years of history.
///
/// Scoped to their own lessons where there is a teacher row. An admin has
/// none and sees every lesson, which is what `ol_is_staff()` lets them write
/// to anyway.
final assignableLessonsProvider = FutureProvider<List<Lesson>>((ref) async {
  final now = hkNow();
  final today = DateTime(now.year, now.month, now.day);
  final lessons = await ref.watch(lessonsRepositoryProvider).lessonsBetween(
        today.subtract(const Duration(days: 120)),
        today.add(const Duration(days: 180)),
      );

  final mine = await ref.watch(myTeacherIdProvider.future);
  final scoped = mine == null
      ? lessons
      : lessons.where((l) => l.teacher?.id == mine).toList();

  // Most recent first: homework is nearly always set for the lesson that has
  // just finished, and that one should not be at the bottom of a long list.
  return scoped.reversed.toList();
}, isAutoDispose: true);

/// The grading queue, ungraded first.
final submissionsProvider = FutureProvider<List<Submission>>((ref) {
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).submissions();
}, isAutoDispose: true);

/// The four cards on the teacher's home screen need the same list the
/// grading screen shows, so it is derived rather than fetched twice.
/// Auto-disposing too, and not only for symmetry: a provider that is kept
/// alive holds everything it watches alive with it, so leaving this one as it
/// was would have pinned the grading queue for the whole run and undone half
/// the fix above.
final pendingSubmissionsProvider = Provider<List<Submission>>((ref) {
  final all = ref.watch(submissionsProvider).value ?? const <Submission>[];
  return all.where((s) => !s.isGraded).toList();
}, isAutoDispose: true);

final adminKpisProvider = FutureProvider<AdminKpis>((ref) {
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).adminKpis();
}, isAutoDispose: true);

final teacherRosterProvider = FutureProvider<List<TeacherRosterEntry>>((ref) {
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).teacherRoster();
}, isAutoDispose: true);

final adminStudentsProvider = FutureProvider<List<AdminStudent>>((ref) {
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).adminStudents();
}, isAutoDispose: true);

final paymentsProvider = FutureProvider<List<Payment>>((ref) {
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).payments();
}, isAutoDispose: true);

final plansProvider = FutureProvider<List<PaymentPlan>>((ref) {
  // The one list the first pass missed, and the one where stale is worst: the
  // payment dialog prices from it, so a tariff changed elsewhere went on
  // being charged at the old amount for the rest of the session.
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).plans();
}, isAutoDispose: true);

final groupsProvider = FutureProvider<List<StudyGroup>>((ref) {
  ref.watch(hkRosterTick);
  return ref.watch(staffRepositoryProvider).groups();
}, isAutoDispose: true);

/// How many lessons each group has ahead of it.
///
/// A student is enrolled through their group, and the enrolment trigger only
/// reaches lessons that have not happened yet. So a group with nothing on the
/// timetable is a group whose students open the app to an empty week — while
/// the admin panel shows them correctly assigned to a teacher and nothing
/// anywhere says why they see nothing. This is what makes that visible.
///
/// Counted from the schedule the app already reads. A view would be tidier
/// and would also be a migration.
final upcomingLessonsByGroupProvider =
    FutureProvider<Map<String, int>>((ref) async {
  ref.watch(hkRosterTick);
  final now = hkNow();
  final lessons = await ref.watch(lessonsRepositoryProvider).lessonsBetween(
        now,
        now.add(const Duration(days: 90)),
      );

  final counts = <String, int>{};
  for (final lesson in lessons) {
    final id = lesson.groupId;
    if (id != null) counts[id] = (counts[id] ?? 0) + 1;
  }
  return counts;
}, isAutoDispose: true);
