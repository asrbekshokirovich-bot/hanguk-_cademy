import 'dart:async';

import 'package:flutter/foundation.dart';
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
        .order('starts_at', ascending: false);
    if (rows.isEmpty) return null;

    final live = rows.map(Lesson.fromMap).toList();
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return live.first;

    // Whose room is it? `ol_v_lessons` shows the whole school's timetable to
    // everyone, so "the most recent live lesson" was somebody's class picked
    // at random. With two lessons on air, a student pressing "Jonli" joined
    // whichever had started last — a different LiveKit room from their own
    // teacher's, where nobody could hear them and they were in nobody's
    // participant list. Mine first: enrolled in it, or teaching it.
    final ids = [for (final l in live) l.id];
    final results = await Future.wait([
      _db
          .from('ol_enrollments')
          .select('lesson_id')
          .eq('student_id', userId)
          .inFilter('lesson_id', ids),
      _db.from('ol_teachers').select('id').eq('user_id', userId).limit(1),
    ]);

    final enrolled = {
      for (final r in results[0]) r['lesson_id'] as String,
    };
    final teacherId =
        results[1].isEmpty ? null : results[1].first['id'] as String?;

    bool mine(Lesson l) =>
        enrolled.contains(l.id) ||
        (teacherId != null && l.teacher?.id == teacherId);

    return live.firstWhere(
      mine,
      // An administrator is in neither list and still needs to be able to
      // walk into any room, so the old answer stands as the fallback.
      orElse: () => live.first,
    );
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
    if (isDemo) return DemoData.materials(lessonId);
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

  /// Every assignment set on a lesson this account is enrolled in.
  ///
  /// Read here rather than on the lesson-detail screen, which is the only
  /// place homework used to appear — and which is reachable only through a
  /// recording. With no recordings, a student had no route to their homework
  /// at all, however carefully the teacher had set it.
  ///
  /// Three round trips rather than a view, because there is no view for this
  /// and adding one means a migration. `ol_enrollments` is readable only for
  /// your own rows, which is what scopes the first query.
  Future<List<Assignment>> myAssignments() async {
    if (isDemo) return DemoData.myAssignments();

    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    final enrolled = await _db
        .from('ol_enrollments')
        .select('lesson_id')
        .eq('student_id', userId);
    final lessonIds =
        enrolled.map((r) => r['lesson_id'] as String).toSet().toList();
    if (lessonIds.isEmpty) return const [];

    final rows = await _db
        .from('ol_assignments')
        .select('id, lesson_id, title, body, due_at, ol_lessons(title)')
        .inFilter('lesson_id', lessonIds)
        .order('due_at', ascending: true, nullsFirst: false);
    if (rows.isEmpty) return const [];

    // The mark comes back with the rest: the policy lets a student read their
    // own submission, and a grade the student cannot see is a teacher marking
    // into a void.
    final mine = await _db
        .from('ol_assignment_submissions')
        .select('assignment_id, grade, feedback, file_url')
        .eq('student_id', userId)
        .inFilter('assignment_id', rows.map((r) => r['id'] as String).toList());
    final byAssignment = {
      for (final r in mine) r['assignment_id'] as String: r,
    };

    return rows.map((r) {
      final lesson = r['ol_lessons'];
      final submission = byAssignment[r['id'] as String];
      return Assignment.fromMap({
        ...r,
        'submitted': submission != null,
        'grade': submission?['grade'],
        'feedback': submission?['feedback'],
        'file_url': submission?['file_url'],
        'lesson_title': lesson is Map<String, dynamic> ? lesson['title'] : null,
      });
    }).toList();
  }

  /// The bucket every upload goes into. One bucket, two folders — see
  /// `20260919120000_storage_uploads.sql`, which is what stops one student
  /// reading another's work.
  static const _uploadsBucket = 'uploads';

  /// Puts a student's answer file in the place the storage policy expects.
  ///
  /// `submissions/<assignment>/<student>/<file>`, with the student id as a
  /// folder of its own: that is the segment the policy compares against
  /// `auth.uid()`, and it is the whole of what keeps one pupil out of
  /// another's homework.
  ///
  /// Anything already in that folder is cleared first, so handing the work in
  /// again replaces it rather than leaving both files behind with no way to
  /// tell which one was meant.
  ///
  /// Returns the object path, which is what goes in the row. Not a URL: the
  /// bucket is private, so a link only exists for the few minutes somebody is
  /// actually opening it — see [signedUploadUrl].
  Future<String> uploadSubmissionFile({
    required String assignmentId,
    required String filename,
    required Uint8List bytes,
  }) async {
    if (isDemo) {
      throw StateError('Demo rejimda fayl yuklab bo‘lmaydi');
    }
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw StateError('Tizimga kirilmagan');

    final folder = 'submissions/$assignmentId/$userId';
    final storage = _db.storage.from(_uploadsBucket);

    try {
      final existing = await storage.list(path: folder);
      if (existing.isNotEmpty) {
        await storage.remove([for (final f in existing) '$folder/${f.name}']);
      }
    } catch (_) {
      // Tidying, not the work. A leftover file is untidy; a failed hand-in
      // is a student who did their homework for nothing.
    }

    final path = '$folder/${_safeFilename(filename)}';
    try {
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );
    } on StorageException catch (e) {
      throw StateError(storageMessage(e));
    }
    return path;
  }

  /// A link to an uploaded file, good for ten minutes.
  ///
  /// The bucket is private, so there is no permanent URL to store. Ten
  /// minutes is long enough to open or save the file and short enough that a
  /// link pasted into a chat stops working before it travels.
  Future<String> signedUploadUrl(String objectPath) async {
    if (isDemo) {
      throw StateError('Demo rejimda fayl ochib bo‘lmaydi');
    }
    try {
      return await _db.storage
          .from(_uploadsBucket)
          .createSignedUrl(objectPath, 600);
    } on StorageException catch (e) {
      throw StateError(storageMessage(e));
    }
  }

  /// Puts a handout where the storage policy expects a teacher's file.
  ///
  /// `materials/<lesson_id>/<file>`, which the policy lets any signed-in
  /// account read and only staff write — the opposite way round from a
  /// submission, and for the obvious reason: a worksheet a student cannot
  /// open is not a worksheet.
  ///
  /// Nothing is cleared first, unlike a hand-in. A lesson can have a
  /// presentation and a word list and a recording of the dialogue, and the
  /// second upload must not delete the first.
  Future<String> uploadMaterialFile({
    required String lessonId,
    required String filename,
    required Uint8List bytes,
  }) async {
    if (isDemo) {
      throw StateError('Demo rejimda fayl yuklab bo‘lmaydi');
    }
    if (_db.auth.currentUser == null) throw StateError('Tizimga kirilmagan');

    final path = 'materials/$lessonId/${_safeFilename(filename)}';
    try {
      await _db.storage.from(_uploadsBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );
    } on StorageException catch (e) {
      throw StateError(storageMessage(e));
    }
    return path;
  }

  /// Puts a recorded lesson in the library.
  ///
  /// `ol_recordings` has been in the schema since the first migration and
  /// nothing has ever written a row, so "Yozuvlar" has been empty in every
  /// build — the policy has always allowed it (`ol_recordings_write` admits
  /// `ol_is_staff()`), there was simply no way in.
  ///
  /// The file goes to `materials/<lesson_id>/`, which every signed-in account
  /// may read: a recording nobody can open is not a recording. [videoUrl] is
  /// the object path that comes back from [uploadMaterialFile], read through
  /// [materialLink] like any other.
  ///
  /// This is the teacher's own capture — Windows' recorder, OBS, whatever
  /// they use. Recording the room on the server is a different thing
  /// entirely: LiveKit egress, S3 credentials and a database that can make
  /// an outbound request. Until that exists, this is how a lesson is kept.
  Future<void> addRecording({
    required String lessonId,
    required String title,
    required String videoUrl,
    String? category,
    String? teacherId,
    DateTime? recordedAt,
    int durationSeconds = 0,
    int attendeeCount = 0,
  }) async {
    if (isDemo) {
      throw StateError('Demo rejimda yozuv qo‘shib bo‘lmaydi');
    }
    await _db.from('ol_recordings').insert({
      'lesson_id': lessonId,
      'title': title.trim(),
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
      'teacher_id': teacherId,
      'recorded_at': (recordedAt ?? hkNow()).toUtc().toIso8601String(),
      'duration_seconds': durationSeconds,
      'attendee_count': attendeeCount,
      'video_url': videoUrl,
    });
  }

  /// A link to a recorded lesson, whichever way it was kept.
  ///
  /// Two kinds live in `ol_recordings.video_url`: a path in Supabase Storage,
  /// from a teacher who uploaded their own capture, and an `r2://` key from
  /// a room the server recorded. The second cannot be signed here — the
  /// bucket's secret is in the database and belongs nowhere near a client —
  /// so the database signs it, for an hour, and hands back a URL.
  Future<String> recordingLink(Recording recording) async {
    final url = recording.videoUrl ?? '';
    if (url.isEmpty) {
      throw StateError('Bu yozuvga fayl biriktirilmagan.');
    }
    if (isDemo) {
      throw StateError('Demo rejimda yozuvni ochib bo‘lmaydi');
    }
    if (url.startsWith('r2://')) {
      final signed = await _db.rpc(
        'ol_recording_url',
        params: {'p_recording_id': recording.id},
      );
      return signed as String;
    }
    return materialLink(url);
  }

  /// Whatever is in `ol_materials.url`, turned into something openable.
  ///
  /// The column predates the bucket and holds both kinds: rows written by
  /// hand hold an ordinary link, rows written by the upload above hold an
  /// object path, which has no address until it is signed. Telling them
  /// apart here rather than at each call site is what stops a download
  /// button quietly launching the string `materials/…` at the browser.
  Future<String> materialLink(String url) {
    final direct = url.startsWith('http://') || url.startsWith('https://');
    return direct ? Future.value(url) : signedUploadUrl(url);
  }

  /// Turns a storage refusal into a sentence that names what to do about it.
  ///
  /// Worth the lines because the likeliest failure here is not the student's
  /// doing and not a bug in this code: a bucket created through the dashboard
  /// arrives with **no policies**, `storage.objects` has RLS on, and every
  /// upload then comes back as an untranslated "new row violates row-level
  /// security policy". Shown raw, that reads as "the app is broken" to the
  /// one person who cannot fix it, and says nothing to the one who can.
  @visibleForTesting
  static String storageMessage(StorageException e) {
    final code = e.statusCode ?? '';
    final text = e.message.toLowerCase();

    if (code == '403' ||
        code == '401' ||
        code == '42501' ||
        text.contains('row-level security') ||
        text.contains('unauthorized')) {
      return 'Faylni saqlab bo‘lmadi: serverda “uploads” bucket uchun '
          'ruxsatlar sozlanmagan. Administrator '
          '20260919120000_storage_uploads.sql ni ishga tushirishi kerak.';
    }
    if (code == '404' || text.contains('not found')) {
      return 'Faylni saqlab bo‘lmadi: “uploads” bucket topilmadi. '
          'Administrator uni Storage bo‘limida yaratishi kerak.';
    }
    if (code == '413' || text.contains('too large')) {
      return 'Fayl juda katta. Eng ko‘pi 50 MB.';
    }
    return 'Faylni saqlab bo‘lmadi: ${e.message}';
  }

  /// Keeps a filename to what an object key can hold, and to what a teacher
  /// can recognise. Uzbek and Korean names arrive here routinely, and a
  /// storage key is not the place to find out which bytes survive.
  static String _safeFilename(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+'), '');
    final trimmed = cleaned.isEmpty ? 'javob' : cleaned;
    return trimmed.length <= 80 ? trimmed : trimmed.substring(0, 80);
  }

  /// Hands in [note] against [assignmentId].
  ///
  /// A written answer, and optionally the object path of a file already
  /// uploaded by [uploadSubmissionFile]. Both are kept: a photographed
  /// exercise usually wants a sentence with it, and a sentence on its own is
  /// a perfectly good piece of homework.
  ///
  /// An upsert, so a student who realises they answered the wrong question
  /// can hand it in again — the primary key is (assignment, student), and
  /// the grading queue reads whatever is there when the teacher opens it.
  Future<void> submitAssignment(
    String assignmentId,
    String note, {
    String? fileUrl,
  }) async {
    if (isDemo) {
      throw StateError('Demo rejimda vazifa topshirib bo‘lmaydi');
    }
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw StateError('Tizimga kirilmagan');

    await _db.from('ol_assignment_submissions').upsert({
      'assignment_id': assignmentId,
      'student_id': userId,
      'note': note.trim(),
      'file_url': fileUrl,
      'submitted_at': hkNow().toUtc().toIso8601String(),
    }, onConflict: 'assignment_id,student_id');
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

  // ----------------------------------------------------------- live room ---

  /// Messages in a lesson's room, oldest first, pushed as they arrive.
  ///
  /// `.stream()` rather than a poll: a chat that refreshes every few seconds
  /// is a chat nobody uses, because the reply you are waiting for is always
  /// half a refresh away. The author's name travels on the row itself — see
  /// the denormalisation note in the migration.
  Stream<List<ChatMessage>> chatStream(String lessonId) {
    if (isDemo) return Stream.value(DemoData.chat());

    final me = _db.auth.currentUser?.id;
    return _db
        .from('ol_chat_messages')
        .stream(primaryKey: ['id'])
        .eq('lesson_id', lessonId)
        .order('sent_at')
        .map(
          (rows) => rows
              .map(
                (r) => ChatMessage(
                  id: r['id'] as String,
                  author: (r['author_name'] as String?)?.trim().isNotEmpty ==
                          true
                      ? r['author_name'] as String
                      : 'Foydalanuvchi',
                  sentAt:
                      DateTime.parse(r['sent_at'] as String).toLocal(),
                  text: r['body'] as String,
                  isSelf: me != null && r['author_id'] == me,
                ),
              )
              .toList(),
        );
  }

  Future<void> sendChatMessage(String lessonId, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    if (isDemo) {
      throw StateError('Demo rejimda xabar yuborib bo‘lmaydi');
    }
    // author_id, author_name and sent_at are all stamped by the trigger; the
    // values sent here are placeholders that the database overwrites. They
    // are sent at all because the INSERT policy checks author_id, and a
    // policy cannot see a column the statement never mentions.
    await _db.from('ol_chat_messages').insert({
      'lesson_id': lessonId,
      'author_id': _db.auth.currentUser?.id,
      'body': body,
    });
  }

  /// Everyone currently in the room, pushed as people come and go.
  ///
  /// Anyone whose heartbeat stopped more than a minute ago is dropped here
  /// rather than in SQL: the stream delivers whole rows, and a filter that
  /// depends on `now()` cannot be part of a subscription.
  ///
  /// Which is also why [recheckEvery] exists. The filter is applied where the
  /// rows arrive, so with nobody typing and nobody joining it is never
  /// applied again — and an expiry is not an event anything pushes. The last
  /// person to close their laptop would stay in the list for good, and a
  /// student walking in afterwards would be shown a room full of people who
  /// had already left. Passing an interval re-runs the mapping over the rows
  /// already in hand, against the clock as it is then.
  Stream<List<Participant>> participantsStream(
    String lessonId, {
    Duration? recheckEvery,
  }) {
    if (isDemo) return Stream.value(DemoData.participants());

    final me = _db.auth.currentUser?.id;
    final rows = _db
        .from('ol_room_presence')
        .stream(primaryKey: ['lesson_id', 'user_id'])
        .eq('lesson_id', lessonId);

    return (recheckEvery == null ? rows : reEmittedEvery(rows, recheckEvery))
        .map((rows) {
          // hkNow, not DateTime.now: this decides who is drawn, and the
          // golden tests pin the clock so that what they rasterise is a
          // function of the fixtures alone.
          final cutoff = hkNow().toUtc().subtract(
                const Duration(seconds: 75),
              );
          final live = rows.where((r) {
            final seen = DateTime.tryParse(
              (r['last_seen_at'] as String?) ?? '',
            )?.toUtc();
            return seen != null && seen.isAfter(cutoff);
          }).toList();

          live.sort((a, b) {
            // The teacher first, then whoever has their hand up, then by the
            // order people arrived — which is stable, so the list does not
            // reshuffle itself under a tap.
            final host = ((b['is_host'] as bool? ?? false) ? 1 : 0) -
                ((a['is_host'] as bool? ?? false) ? 1 : 0);
            if (host != 0) return host;
            final hand = ((b['hand_raised'] as bool? ?? false) ? 1 : 0) -
                ((a['hand_raised'] as bool? ?? false) ? 1 : 0);
            if (hand != 0) return hand;
            return ((a['joined_at'] as String?) ?? '')
                .compareTo((b['joined_at'] as String?) ?? '');
          });

          return live
              .map(
                (r) => Participant(
                  id: r['user_id'] as String,
                  name: (r['display_name'] as String?)?.trim().isNotEmpty ==
                          true
                      ? r['display_name'] as String
                      : 'Foydalanuvchi',
                  initials: (r['initials'] as String?) ?? '?',
                  isHost: r['is_host'] as bool? ?? false,
                  isSelf: me != null && r['user_id'] == me,
                  micOn: r['mic_on'] as bool? ?? false,
                  handRaised: r['hand_raised'] as bool? ?? false,
                ),
              )
              .toList();
        });
  }

  /// Announces this account as present, and refreshes the heartbeat on every
  /// later call. One upsert does both — the trigger re-stamps `last_seen_at`
  /// on update as well as insert, so there is no separate "still here" path
  /// to forget about.
  Future<void> enterRoom(
    String lessonId, {
    bool? micOn,
    bool? handRaised,
  }) async {
    if (isDemo) return;
    final me = _db.auth.currentUser?.id;
    if (me == null) return;

    // Built up rather than written as a literal with `if` entries: the
    // heartbeat calls this with both flags null and must not clobber the
    // state the control bar last set, so an absent key is meaningfully
    // different from a null one.
    final row = <String, dynamic>{
      'lesson_id': lessonId,
      'user_id': me,
    };
    if (micOn != null) row['mic_on'] = micOn;
    if (handRaised != null) row['hand_raised'] = handRaised;

    await _db
        .from('ol_room_presence')
        .upsert(row, onConflict: 'lesson_id,user_id');
  }

  /// Opens this account's attendance record for a lesson, and says how many
  /// seconds it already holds.
  ///
  /// `ol_attendance` has been in the schema since the first migration and is
  /// what every attendance figure in the app is computed from — the admin
  /// dashboard's average, the teacher's, the percentage beside each name in
  /// "Talabalarim". Nothing ever wrote a row, so against the real database
  /// all of them were zero, and the numbers on screen came from fixtures.
  ///
  /// Measured, not marked. The room already knows exactly who is in it and
  /// for how long, which is a better record than a register anyone has to
  /// remember to fill in — and it is what the columns were designed for:
  /// `seconds_attended` accumulates across rejoins, so a dropped connection
  /// does not zero somebody's lesson.
  Future<int> beginAttendance(String lessonId) async {
    if (isDemo) return 0;
    final me = _db.auth.currentUser?.id;
    if (me == null) return 0;

    try {
      final row = await _db
          .from('ol_attendance')
          .select('seconds_attended')
          .eq('lesson_id', lessonId)
          .eq('student_id', me)
          .maybeSingle();

      if (row != null) return (row['seconds_attended'] as num?)?.round() ?? 0;

      await _db.from('ol_attendance').insert({
        'lesson_id': lessonId,
        'student_id': me,
        'joined_at': hkNow().toUtc().toIso8601String(),
        'seconds_attended': 0,
      });
      return 0;
    } catch (_) {
      // Bookkeeping. A student whose attendance row will not open should
      // still get their lesson.
      return 0;
    }
  }

  /// Banks [seconds] against this lesson.
  ///
  /// Called on the room's heartbeat rather than only on the way out, because
  /// the way out is the half that does not happen: laptops close, tabs are
  /// killed, connections drop. `left_at` is re-stamped each time and so means
  /// "last seen", which is the only honest reading of it for a client that
  /// may never say goodbye.
  Future<void> recordAttendance(String lessonId, int seconds) async {
    if (isDemo) return;
    final me = _db.auth.currentUser?.id;
    if (me == null) return;

    try {
      await _db
          .from('ol_attendance')
          .update({
            'seconds_attended': seconds,
            'left_at': hkNow().toUtc().toIso8601String(),
          })
          .eq('lesson_id', lessonId)
          .eq('student_id', me);
    } catch (_) {
      // As above: the next heartbeat carries the same total, so one lost
      // request costs nothing.
    }
  }

  /// Leaves the room. Best-effort by nature: the window can be closed, the
  /// machine can sleep, the network can drop. The heartbeat cutoff is what
  /// makes the list correct anyway; this only makes it correct *immediately*
  /// for the common case where someone actually pressed "Chiqish".
  Future<void> leaveRoom(String lessonId) async {
    if (isDemo) return;
    final me = _db.auth.currentUser?.id;
    if (me == null) return;
    await _db
        .from('ol_room_presence')
        .delete()
        .eq('lesson_id', lessonId)
        .eq('user_id', me);
  }

  /// The credentials for joining this lesson's media room.
  ///
  /// Minted by the database, not here: the signing secret decides who may
  /// join as whom, so it lives where the client cannot read it. See
  /// `20260918140000_livekit_tokens.sql`.
  ///
  /// Null when media is not configured on this project — which is a state the
  /// room has to handle rather than crash on, since the chat and the
  /// participant list work perfectly well without it.
  Future<LiveMediaGrant?> liveMediaGrant(String lessonId) async {
    if (isDemo) return null;

    final rows = await _db.rpc(
      'ol_livekit_join',
      params: {'p_lesson_id': lessonId},
    ) as List<dynamic>;
    if (rows.isEmpty) return null;

    final row = rows.first as Map<String, dynamic>;
    final url = row['url'] as String?;
    final token = row['token'] as String?;
    if (url == null || token == null) return null;

    return LiveMediaGrant(
      url: url,
      token: token,
      room: row['room'] as String? ?? 'lesson_$lessonId',
    );
  }

  Future<bool> liveMediaConfigured() async {
    if (isDemo) return false;
    try {
      return await _db.rpc('ol_livekit_ready') as bool? ?? false;
    } catch (_) {
      // An older database without the migration answers 404. That is a "no",
      // not a reason to keep the room off the screen.
      return false;
    }
  }

  /// Ends every lesson that has run past its slot.
  ///
  /// Also scheduled in the database every five minutes, where a project has
  /// pg_cron. Called from the client too because a free-tier project may not,
  /// and "the lesson from three weeks ago is still live" is exactly the bug
  /// this is here to prevent.
  Future<void> endStaleLessons() async {
    if (isDemo) return;
    try {
      await _db.rpc('ol_end_stale_lessons');
    } catch (_) {
      // Housekeeping. A student whose room failed to tidy up somebody else's
      // lesson should still get their room.
    }
  }
}

/// [source], plus its most recent event again every [every].
///
/// For a mapping that depends on the wall clock rather than on the data: the
/// re-sent event is the same one, so what changes between two deliveries is
/// only the time the mapping reads.
///
/// Re-subscribing on a timer would do the same job in three lines, and is
/// the wrong three lines. A Supabase `.stream()` is a realtime channel:
/// tearing it down and building it again costs a channel join and a fresh
/// read of the whole table each time, and at four times a minute for every
/// person in a sixty-student room that is a great deal of traffic to pay for
/// a timestamp comparison over rows already in memory.
///
/// Public only so `test/status_polling_test.dart` can drive it without a
/// Supabase client behind it.
@visibleForTesting
Stream<T> reEmittedEvery<T>(Stream<T> source, Duration every) {
  StreamSubscription<T>? subscription;
  Timer? timer;
  late T latest;
  var arrived = false;

  final out = StreamController<T>();

  out.onListen = () {
    subscription = source.listen(
      (event) {
        latest = event;
        arrived = true;
        out.add(event);
      },
      onError: out.addError,
      onDone: () {
        timer?.cancel();
        out.close();
      },
    );
    // Nothing goes out before the source has spoken once. There is no latest
    // to re-send, and an empty list would read as an empty room.
    timer = Timer.periodic(every, (_) {
      if (arrived) out.add(latest);
    });
  };

  out.onCancel = () async {
    timer?.cancel();
    await subscription?.cancel();
  };

  return out.stream;
}

/// Null in demo mode. Overridden in `main.dart` once Supabase is initialised.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  return HkEnv.hasSupabase ? Supabase.instance.client : null;
});

final lessonsRepositoryProvider = Provider<LessonsRepository>((ref) {
  return LessonsRepository(ref.watch(supabaseClientProvider));
});
