import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../lessons/data/lessons_repository.dart';
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
}

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(supabaseClientProvider));
});
