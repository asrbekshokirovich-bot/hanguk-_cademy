import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../lessons/data/lessons_repository.dart';
import '../../lessons/domain/models.dart';
import '../domain/staff_models.dart';
import 'staff_demo_data.dart';

/// Everything the teacher and admin panels read and write.
///
/// The heavy lifting is in SQL — attendance and progress percentages, teacher
/// load, outstanding balances all come out of views and RPCs rather than being
/// recomputed here. Two reasons: those numbers are aggregates over rows a
/// single user is not allowed to read individually, and a roster of sixty
/// students would otherwise be sixty round trips.
class StaffRepository {
  StaffRepository(this._client);

  final SupabaseClient? _client;

  bool get isDemo => _client == null;

  SupabaseClient get _db => _client!;

  // ------------------------------------------------------------- teacher ---

  /// This account's row in `ol_teachers`, or null if it does not have one.
  ///
  /// Two different ids are in play and conflating them is the whole reason
  /// this exists: `ol_lessons.teacher_id` points at `ol_teachers.id`, not at
  /// `auth.users.id`. A teacher is also allowed to exist on the timetable
  /// before they have an account at all, so the mapping is a lookup and not
  /// an assumption.
  ///
  /// Null for an admin — by design, since `20260807190000_admins_are_not_
  /// teachers.sql`. Callers read that as "not tied to any one teacher's day"
  /// rather than "teaches nothing".
  Future<String?> myTeacherId() async {
    // The demo build has no session to look up, so it answers as the teacher
    // the fixtures are written around — the one teaching the live lesson.
    // Answering null instead would empty the teacher panel in the demo, which
    // is the one place the panel is ever looked at without a backend.
    if (isDemo) return StaffDemoData.demoTeacherId;

    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _db
        .from('ol_teachers')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<TeacherStats> teacherStats() async {
    if (isDemo) return StaffDemoData.teacherStats;
    final rows = await _db.rpc('ol_teacher_stats') as List<dynamic>;
    if (rows.isEmpty) return TeacherStats.empty;
    return TeacherStats.fromMap(rows.first as Map<String, dynamic>);
  }

  Future<List<TeacherStudent>> myStudents() async {
    if (isDemo) return StaffDemoData.teacherStudents();
    final rows = await _db
        .from('ol_v_teacher_students')
        .select()
        .order('full_name');
    return rows.map((r) => TeacherStudent.fromMap(r)).toList();
  }

  /// The grading queue. Ungraded first — that is the whole point of the
  /// screen — then most recently handed in.
  Future<List<Submission>> submissions({bool ungradedOnly = false}) async {
    if (isDemo) {
      final all = StaffDemoData.submissions();
      return ungradedOnly ? all.where((s) => !s.isGraded).toList() : all;
    }

    var query = _db.from('ol_v_submissions').select();
    if (ungradedOnly) query = query.isFilter('graded_at', null);

    final rows = await query
        .order('graded_at', ascending: true, nullsFirst: true)
        .order('submitted_at', ascending: false);
    return rows.map((r) => Submission.fromMap(r)).toList();
  }

  Future<void> gradeSubmission({
    required String assignmentId,
    required String studentId,
    required int grade,
    String? feedback,
  }) async {
    if (isDemo) throw StateError('Demo rejimda baholab bo‘lmaydi');
    final graderId = _db.auth.currentUser?.id;

    await _db
        .from('ol_assignment_submissions')
        .update({
          'grade': grade,
          'feedback': feedback,
          'graded_at': DateTime.now().toUtc().toIso8601String(),
          'graded_by': graderId,
        })
        .eq('assignment_id', assignmentId)
        .eq('student_id', studentId);
  }

  // -------------------------------------------------------------- groups ---

  Future<List<StudyGroup>> groups() async {
    if (isDemo) return StaffDemoData.groups();
    final rows = await _db.from('ol_v_groups').select().order('name');
    return rows.map((r) => StudyGroup.fromMap(r)).toList();
  }

  Future<void> createGroup({
    required String name,
    required String teacherId,
    int? level,
  }) async {
    if (isDemo) throw StateError('Demo rejimda guruh yaratib bo‘lmaydi');
    await _db.from('ol_groups').insert({
      'name': name.trim(),
      'teacher_id': teacherId,
      'level': level,
    });
  }

  Future<void> updateGroup(
    String groupId, {
    String? name,
    String? teacherId,
    int? level,
  }) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _db.from('ol_groups').update({
      if (name != null) 'name': name.trim(),
      'teacher_id': ?teacherId,
      'level': level,
    }).eq('id', groupId);
  }

  Future<void> deleteGroup(String groupId) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _db.from('ol_groups').delete().eq('id', groupId);
  }

  /// Moves a student into a group, or out of every group when [groupId] is
  /// null. Which group they are in is what decides whose student they are, so
  /// this goes through one function rather than being assembled by the client.
  Future<void> assignStudentGroup(String studentId, String? groupId) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _db.rpc('ol_assign_student_group', params: {
      'p_student_id': studentId,
      'p_group_id': groupId,
    });
  }

  // --------------------------------------------------------------- admin ---

  Future<AdminKpis> adminKpis() async {
    if (isDemo) return StaffDemoData.adminKpis;
    final rows = await _db.rpc('ol_admin_kpis') as List<dynamic>;
    if (rows.isEmpty) return AdminKpis.empty;
    return AdminKpis.fromMap(rows.first as Map<String, dynamic>);
  }

  Future<List<TeacherRosterEntry>> teacherRoster() async {
    if (isDemo) return StaffDemoData.teacherRoster();
    final rows =
        await _db.from('ol_v_teacher_roster').select().order('full_name');
    return rows.map((r) => TeacherRosterEntry.fromMap(r)).toList();
  }

  Future<List<AdminStudent>> adminStudents() async {
    if (isDemo) return StaffDemoData.adminStudents();
    final rows =
        await _db.from('ol_v_admin_students').select().order('full_name');
    return rows.map((r) => AdminStudent.fromMap(r)).toList();
  }

  Future<List<Payment>> payments() async {
    if (isDemo) return StaffDemoData.payments();
    final rows = await _db
        .from('ol_v_payments')
        .select()
        .order('period', ascending: false)
        .order('student_name');
    return rows.map((r) => Payment.fromMap(r)).toList();
  }

  Future<List<PaymentPlan>> plans() async {
    if (isDemo) return StaffDemoData.plans;
    final rows = await _db.from('ol_plans').select().order('sort_order');
    return rows.map((r) => PaymentPlan.fromMap(r)).toList();
  }

  /// Records money as received. Sets `paid_at` alongside the status so a
  /// confirmed payment always carries the date it arrived — a status without
  /// a date cannot be reconciled against a bank statement later.
  Future<void> confirmPayment(String paymentId) async {
    if (isDemo) throw StateError('Demo rejimda o‘zgartirib bo‘lmaydi');
    await _db.from('ol_payments').update({
      'status': 'confirmed',
      'paid_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', paymentId);
  }

  Future<void> recordPayment({
    required String studentId,
    required String planCode,
    required int amount,
    required DateTime period,
    DateTime? dueDate,
    bool confirmed = false,
  }) async {
    if (isDemo) throw StateError('Demo rejimda qo‘shib bo‘lmaydi');
    final now = DateTime.now();

    await _db.from('ol_payments').upsert({
      'student_id': studentId,
      'plan_code': planCode,
      'amount': amount,
      // Stored as the first of the month; the unique index is on
      // (student_id, period), so normalising here is what makes a second
      // entry for the same month update rather than duplicate.
      'period': DateTime(period.year, period.month).toIso8601String()
          .split('T')
          .first,
      'due_date': (dueDate ?? DateTime(period.year, period.month, 10))
          .toIso8601String()
          .split('T')
          .first,
      'status': confirmed ? 'confirmed' : 'pending',
      'paid_at': confirmed ? now.toUtc().toIso8601String() : null,
      'recorded_by': _db.auth.currentUser?.id,
    }, onConflict: 'student_id,period');
  }
  // ------------------------------------------------------------- lessons ---

  Future<void> createLesson({
    required String title,
    required String category,
    required DateTime startsAt,
    required int durationMinutes,
    String? teacherId,
    String? groupId,
    String? description,
    bool autoRecord = true,
  }) async {
    if (isDemo) throw StateError('Demo rejimda dars yaratib bo‘lmaydi');
    await _db.from('ol_lessons').insert({
      'title': title.trim(),
      'category': category,
      // UTC on the wire, always. The column is timestamptz; sending a local
      // string without an offset is how a 16:00 lesson becomes 11:00 for
      // whoever reads it next.
      'starts_at': startsAt.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'teacher_id': teacherId,
      'group_id': groupId,
      'description': description?.trim(),
      'auto_record': autoRecord,
      'created_by': _db.auth.currentUser?.id,
    });
  }

  Future<void> updateLesson(
    String lessonId, {
    String? title,
    String? category,
    DateTime? startsAt,
    int? durationMinutes,
    String? teacherId,
    String? groupId,
    String? description,
    bool? autoRecord,
  }) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _db.from('ol_lessons').update({
      if (title != null) 'title': title.trim(),
      'category': ?category,
      'starts_at': ?startsAt?.toUtc().toIso8601String(),
      'duration_minutes': ?durationMinutes,
      'auto_record': ?autoRecord,
      // Null is meaningful for these two — "no teacher yet", "not tied to a
      // group" — so they are always written rather than only when non-null.
      'teacher_id': teacherId,
      'group_id': groupId,
      if (description != null) 'description': description.trim(),
    }).eq('id', lessonId);
  }

  /// Moves a lesson through its life cycle: `scheduled` → `live` → `ended`.
  ///
  /// Deliberately *not* a `status:` argument on [updateLesson]. That method
  /// always writes `teacher_id` and `group_id` because null is meaningful
  /// there, so flipping a status through it from a screen that never loaded
  /// the edit form would clear both — the lesson would go on air with no
  /// teacher attached.
  ///
  /// Who may call it is decided by the `ol_lessons_write` policy, not here:
  /// the button is hidden from students, but hiding is not the check.
  Future<void> setLessonStatus(String lessonId, LessonStatus status) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _db
        .from('ol_lessons')
        .update({'status': status.wire}).eq('id', lessonId);
  }

  Future<void> deleteLesson(String lessonId) async {
    if (isDemo) throw StateError('Demo rejimda mavjud emas');
    await _db.from('ol_lessons').delete().eq('id', lessonId);
  }
}

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(supabaseClientProvider));
});
