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
