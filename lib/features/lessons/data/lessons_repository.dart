import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';
import '../domain/models.dart';
import 'demo_data.dart';
import '../../../core/clock.dart';

/// Reads the online-lessons product out of Supabase.
///
/// Every method has a demo branch guarded by [HkEnv.hasSupabase]. When no
/// credentials were supplied at build time the repository serves the design
/// fixtures instead of throwing — see `demo_data.dart` for why.
class LessonsRepository {
  LessonsRepository(this._client);

  final SupabaseClient? _client;

  bool get isDemo => _client == null;

  SupabaseClient get _db => _client!;

  // ------------------------------------------------------------ profile ---

  Future<UserProfile> currentProfile() async {
    if (isDemo) return DemoData.profile;

    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Tizimga kirilmagan');
    }
    final row = await _db
        .from('ol_profiles')
        .select('user_id, full_name, initials, role, level, username, must_change_password')
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) {
      // The auth trigger creates this row, but a user who existed before the
      // migration ran will not have one. Fall back rather than blocking them
      // out of the whole app.
      return UserProfile(
        id: userId,
        fullName: _db.auth.currentUser?.email?.split('@').first ?? 'Talaba',
        initials: '?',
        role: 'student',
      );
    }
    return UserProfile.fromMap(row);
  }

  // ------------------------------------------------------------- lessons ---

  Future<List<Lesson>> lessonsBetween(DateTime from, DateTime to) async {
    if (isDemo) {
      return DemoData.weekSchedule()
          .where((l) => !l.startsAt.isBefore(from) && l.startsAt.isBefore(to))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }

    final rows = await _db
        .from('ol_v_lessons')
        .select()
        .gte('starts_at', from.toUtc().toIso8601String())
        .lt('starts_at', to.toUtc().toIso8601String())
        .order('starts_at');

    return rows.map((r) => Lesson.fromMap(r)).toList();
  }

  Future<List<Lesson>> todaysLessons() {
    final now = hkNow();
    final start = DateTime(now.year, now.month, now.day);
    return lessonsBetween(start, start.add(const Duration(days: 1)));
  }

  /// The lesson currently broadcasting, if any. Drives the dashboard hero and
  /// the dock's live dot.
  Future<Lesson?> liveLesson() async {
    if (isDemo) {
      return DemoData.todaysLessons()
          .where((l) => l.status == LessonStatus.live)
          .firstOrNull;
    }

    final rows = await _db
        .from('ol_v_lessons')
        .select()
        .eq('status', 'live')
        .order('starts_at', ascending: false)
        .limit(1);

    return rows.isEmpty ? null : Lesson.fromMap(rows.first);
  }

  Future<Lesson?> lessonById(String id) async {
    if (isDemo) {
      return DemoData.weekSchedule().where((l) => l.id == id).firstOrNull;
    }
    final row =
        await _db.from('ol_v_lessons').select().eq('id', id).maybeSingle();
    return row == null ? null : Lesson.fromMap(row);
  }

  Future<void> setAutoRecord(String lessonId, bool enabled) async {
    if (isDemo) return;
    await _db
        .from('ol_lessons')
        .update({'auto_record': enabled}).eq('id', lessonId);
  }

  Future<void> enrol(String lessonId) async {
    if (isDemo) return;
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    await _db
        .from('ol_enrollments')
        .upsert({'lesson_id': lessonId, 'student_id': userId});
  }

  // ---------------------------------------------------------- recordings ---

  Future<List<Recording>> recordings({String? category}) async {
    if (isDemo) {
      final all = DemoData.recordings();
      return category == null
          ? all
          : all.where((r) => r.category == category).toList();
    }

    var query = _db.from('ol_v_recordings').select();
    if (category != null) query = query.eq('category', category);

    final rows = await query.order('recorded_at', ascending: false);
    return rows.map((r) => Recording.fromMap(r)).toList();
  }

  Future<Recording?> recordingById(String id) async {
    if (isDemo) {
      return DemoData.recordings().where((r) => r.id == id).firstOrNull;
    }
    final row =
        await _db.from('ol_v_recordings').select().eq('id', id).maybeSingle();
    return row == null ? null : Recording.fromMap(row);
  }

  /// Persists where the student stopped watching, so the library's progress
  /// bars survive a restart.
  Future<void> saveProgress(
    String recordingId,
    int positionSeconds,
    int durationSeconds,
  ) async {
    if (isDemo) return;
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;

    await _db.from('ol_recording_progress').upsert({
      'recording_id': recordingId,
      'student_id': userId,
      'position_seconds': positionSeconds,
      // A student who watches to within the last 15 seconds has finished it;
      // requiring the exact final second means almost nothing ever reads as
      // "Ko'rildi".
      'completed': durationSeconds > 0 &&
          positionSeconds >= durationSeconds - 15,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // ----------------------------------------------- materials / homework ---

  Future<List<LessonMaterial>> materials(String lessonId) async {
    if (isDemo) return DemoData.materials();
    final rows = await _db
        .from('ol_materials')
        .select()
        .eq('lesson_id', lessonId)
        .order('created_at');
    return rows.map((r) => LessonMaterial.fromMap(r)).toList();
  }

  Future<LessonQuiz?> quiz(String lessonId) async {
    if (isDemo) return DemoData.quiz;
    final row = await _db
        .from('ol_quizzes')
        .select('id, title, question_count')
        .eq('lesson_id', lessonId)
        .maybeSingle();
    return row == null ? null : LessonQuiz.fromMap(row);
  }

  Future<Assignment?> assignment(String lessonId) async {
    if (isDemo) return DemoData.assignment;

    final row = await _db
        .from('ol_assignments')
        .select('id, title, due_at')
        .eq('lesson_id', lessonId)
        .maybeSingle();
    if (row == null) return null;

    final userId = _db.auth.currentUser?.id;
    final submission = userId == null
        ? null
        : await _db
            .from('ol_assignment_submissions')
            .select('assignment_id')
            .eq('assignment_id', row['id'] as String)
            .eq('student_id', userId)
            .maybeSingle();

    return Assignment.fromMap({...row, 'submitted': submission != null});
  }

  // -------------------------------------------------------------- search ---

  /// Matches [query] against lesson and recording titles, categories and
  /// teacher names.
  ///
  /// Two round trips rather than one RPC: the two tables have genuinely
  /// different shapes and a union would have to flatten them into a lowest
  /// common denominator that the result rows then could not render.
  Future<SearchResults> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return SearchResults.empty;

    if (isDemo) {
      final needle = q.toLowerCase();
      bool hitLesson(Lesson l) =>
          l.title.toLowerCase().contains(needle) ||
          l.category.toLowerCase().contains(needle) ||
          (l.teacher?.fullName.toLowerCase().contains(needle) ?? false);
      bool hitRecording(Recording r) =>
          r.title.toLowerCase().contains(needle) ||
          r.category.toLowerCase().contains(needle) ||
          (r.teacher?.fullName.toLowerCase().contains(needle) ?? false);

      return SearchResults(
        lessons: DemoData.weekSchedule().where(hitLesson).toList(),
        recordings: DemoData.recordings().where(hitRecording).toList(),
      );
    }

    // PostgREST `or` takes a comma-separated filter list. Commas and parens
    // inside the value would be read as filter syntax, so they are stripped
    // rather than escaped — a search term containing them is not meaningful
    // here anyway.
    final safe = q.replaceAll(RegExp(r'[,()*]'), ' ').trim();
    if (safe.isEmpty) return SearchResults.empty;
    final filter = 'title.ilike.%$safe%,'
        'category.ilike.%$safe%,'
        'teacher_name.ilike.%$safe%';

    final results = await Future.wait([
      _db
          .from('ol_v_lessons')
          .select()
          .or(filter)
          .order('starts_at', ascending: false)
          .limit(20),
      _db
          .from('ol_v_recordings')
          .select()
          .or(filter)
          .order('recorded_at', ascending: false)
          .limit(20),
    ]);

    return SearchResults(
      lessons: results[0].map((r) => Lesson.fromMap(r)).toList(),
      recordings: results[1].map((r) => Recording.fromMap(r)).toList(),
    );
  }

  // ------------------------------------------------------- notifications ---

  Future<List<AppNotification>> notifications() async {
    if (isDemo) return DemoData.notifications();

    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _db
        .from('ol_notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    return rows.map((r) => AppNotification.fromMap(r)).toList();
  }

  Future<void> markNotificationsRead() async {
    if (isDemo) return;
    await _db.rpc('ol_mark_notifications_read');
  }

  // --------------------------------------------------------------- stats ---

  Future<DashboardStats> dashboardStats() async {
    if (isDemo) return DemoData.stats;
    final rows = await _db.rpc('ol_dashboard_stats') as List<dynamic>;
    if (rows.isEmpty) return DashboardStats.empty;
    return DashboardStats.fromMap(rows.first as Map<String, dynamic>);
  }
}

/// Null in demo mode. Overridden in `main.dart` once Supabase is initialised.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  return HkEnv.hasSupabase ? Supabase.instance.client : null;
});

final lessonsRepositoryProvider = Provider<LessonsRepository>((ref) {
  return LessonsRepository(ref.watch(supabaseClientProvider));
});
