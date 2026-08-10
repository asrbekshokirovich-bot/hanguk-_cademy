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

  /// Moves a lesson between scheduled, live and finished.
  ///
  /// Nothing did this before, so a lesson could never become live: the live
  /// room selects on status = 'live' and no code ever wrote that value. The
  /// schedule was a list of intentions with no way to act on one.
  ///
  /// Starting a lesson also names its room, derived from the lesson id rather
  /// than generated, so a reconnect — or a second device — lands in the room
  /// that is already running instead of an empty one of its own.
  ///
  /// Staff only, enforced by RLS on ol_lessons. Hiding the button is the
  /// courtesy; the database is the rule.
  Future<void> setLessonStatus(String lessonId, LessonStatus status) async {
    if (isDemo) return;
    await _db.from('ol_lessons').update({
      'status': switch (status) {
        LessonStatus.scheduled => 'scheduled',
        LessonStatus.live => 'live',
        LessonStatus.ended => 'ended',
        LessonStatus.cancelled => 'cancelled',
      },
      if (status == LessonStatus.live) 'live_room': 'lesson-$lessonId',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', lessonId);
  }

  /// Asks the Edge Function for a LiveKit token for this lesson.
  ///
  /// Null in demo mode, and null when the function reports that LiveKit is
  /// not configured — the room then says so instead of spinning. Anything
  /// else (lesson not live, not signed in) throws with the function's own
  /// Uzbek message, which is more use on screen than a status code.
  Future<LiveKitCredentials?> liveKitToken(String lessonId) async {
    if (isDemo) return null;

    final response = await _db.functions.invoke(
      'livekit-token',
      body: {'lesson_id': lessonId},
    );

    final data = response.data;
    if (data is Map && data['token'] is String && data['url'] is String) {
      return LiveKitCredentials(
        token: data['token'] as String,
        url: data['url'] as String,
        room: data['room'] as String? ?? 'lesson-$lessonId',
      );
    }
    if (data is Map && data['error'] is String) {
      if ((data['error'] as String).contains('sozlanmagan')) return null;
      throw StateError(data['error'] as String);
    }
    throw StateError('Video xizmatiga ulanib bo‘lmadi');
  }

  // -------------------------------------------------------- lesson chat ---

  /// Everything said in this lesson so far, oldest first.
  ///
  /// Read on joining the room, so somebody who arrives ten minutes late sees
  /// what has been asked instead of an empty panel.
  Future<List<LessonMessage>> lessonMessages(String lessonId) async {
    if (isDemo) return const [];
    final rows = await _db
        .from('ol_lesson_messages')
        .select()
        .eq('lesson_id', lessonId)
        .order('sent_at')
        // A lesson does not produce more than this, and a runaway loop should
        // not be able to drag the whole history into a phone's memory.
        .limit(500);
    return rows.map((r) => LessonMessage.fromMap(r)).toList();
  }

  /// Writes one line. Delivery to the people already in the room happens over
  /// LiveKit's data channel; this is what makes it survive the lesson.
  Future<void> sendLessonMessage({
    required String lessonId,
    required String authorName,
    required String body,
  }) async {
    if (isDemo) return;
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    await _db.from('ol_lesson_messages').insert({
      'lesson_id': lessonId,
      'author_id': userId,
      'author_name': authorName,
      'body': body,
    });
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
      // People and classes, for staff. RLS returns nothing to a student, so
      // this costs a wasted round trip on their side and nothing more — no
      // role check here that the database would not enforce anyway.
      _db
          .from('ol_v_admin_students')
          .select('student_id, full_name, group_name')
          .ilike('full_name', '%\$safe%')
          .limit(10),
      _db
          .from('ol_groups')
          .select('id, name')
          .ilike('name', '%\$safe%')
          .limit(10),
    ]);

    return SearchResults(
      lessons: results[0].map((r) => Lesson.fromMap(r)).toList(),
      recordings: results[1].map((r) => Recording.fromMap(r)).toList(),
      students: results[2]
          .map((r) => SearchPerson(
                id: r['student_id'] as String,
                name: (r['full_name'] as String?) ?? '—',
                subtitle: r['group_name'] as String?,
              ))
          .toList(),
      groups: results[3]
          .map((r) => SearchPerson(
                id: r['id'] as String,
                name: (r['name'] as String?) ?? '—',
              ))
          .toList(),
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
