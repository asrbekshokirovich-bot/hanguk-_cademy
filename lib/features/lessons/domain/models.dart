import 'package:flutter/material.dart';

import '../../../design_system/tokens.dart';

/// Where a lesson is in its life cycle. Mirrors the `ol_lesson_status` enum in
/// the database — keep the wire names in step with the migration.
enum LessonStatus {
  scheduled('Rejalashtirilgan'),
  live('Jonli'),
  ended('Yakunlandi'),
  cancelled('Bekor qilindi');

  const LessonStatus(this.label);

  final String label;

  static LessonStatus fromWire(String? value) => switch (value) {
        'live' => LessonStatus.live,
        'ended' => LessonStatus.ended,
        'cancelled' => LessonStatus.cancelled,
        _ => LessonStatus.scheduled,
      };

  String get wire => name;

  /// Pill colours from the handoff: live is the lime accent, upcoming is the
  /// blue tint, everything past is muted.
  Color get pillBackground => switch (this) {
        LessonStatus.live => HkColors.lime,
        LessonStatus.scheduled => const Color(0x2E6EA0E0),
        LessonStatus.ended => const Color(0x14FFFFFF),
        LessonStatus.cancelled => const Color(0x24DC2626),
      };

  Color get pillForeground => switch (this) {
        LessonStatus.live => HkColors.ink,
        LessonStatus.scheduled => HkColors.infoText,
        LessonStatus.ended => HkColors.textSecondary,
        LessonStatus.cancelled => HkColors.dangerBright,
      };
}

class Teacher {
  const Teacher({
    required this.id,
    required this.fullName,
    required this.initials,
    this.avatarUrl,
  });

  final String id;
  final String fullName;
  final String initials;
  final String? avatarUrl;

  /// Deterministic avatar gradient. The design gives every teacher a distinct
  /// two-stop gradient; deriving it from the id keeps a given person the same
  /// colour on every screen without storing a colour column.
  LinearGradient get gradient {
    const palettes = [
      [Color(0xFF6FA0E0), HkColors.royalBlue],
      [Color(0xFF7E57C2), Color(0xFF311B69)],
      [Color(0xFFE0A93A), Color(0xFF7A4900)],
      [Color(0xFF15A05A), Color(0xFF0C3D24)],
      [Color(0xFF2E5FA8), Color(0xFF0F213D)],
    ];
    final palette = palettes[id.hashCode.abs() % palettes.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: palette,
    );
  }

  factory Teacher.fromMap(Map<String, dynamic> map) {
    final name = (map['full_name'] as String?) ?? '—';
    return Teacher(
      id: map['id'] as String,
      fullName: name,
      initials: (map['initials'] as String?) ?? _initialsOf(name),
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.category,
    required this.startsAt,
    required this.durationMinutes,
    required this.status,
    required this.autoRecord,
    required this.enrolledCount,
    this.teacher,
    this.liveRoom,
    this.description,
    this.groupId,
  });

  final String id;
  final String title;
  final String category;
  final DateTime startsAt;
  final int durationMinutes;
  final LessonStatus status;
  final bool autoRecord;
  final int enrolledCount;
  final Teacher? teacher;

  /// The class this lesson belongs to, if any. Only the schedule's edit dialog
  /// reads it — but it has to, or re-saving would detach the class.
  final String? groupId;

  /// LiveKit room name. Populated by the backend when a lesson goes live;
  /// unused until the media layer lands.
  final String? liveRoom;
  final String? description;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  /// How long the lesson has been running. Only meaningful while [status] is
  /// [LessonStatus.live]; the live room shows it as the "davom etmoqda" clock.
  Duration elapsedAt(DateTime now) {
    final d = now.difference(startsAt);
    return d.isNegative ? Duration.zero : d;
  }

  /// The colour tick beside a schedule row. Live lessons take the accent;
  /// everything else is keyed off its category so the week reads at a glance.
  Color get accent {
    if (status == LessonStatus.live) return HkColors.lime;
    return switch (category) {
      'TOPIK' => const Color(0xFFA78BE0),
      'Grammatika' => const Color(0xFF6FA0E0),
      'Tinglash' => const Color(0xFFE0A93A),
      _ => const Color(0xFF6FA0E0),
    };
  }

  factory Lesson.fromMap(Map<String, dynamic> map) {
    final teacherMap = map['teacher'];
    return Lesson(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? '—',
      category: (map['category'] as String?) ?? 'Koreys tili',
      startsAt: DateTime.parse(map['starts_at'] as String).toLocal(),
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 60,
      status: LessonStatus.fromWire(map['status'] as String?),
      autoRecord: (map['auto_record'] as bool?) ?? true,
      enrolledCount: (map['enrolled_count'] as num?)?.toInt() ?? 0,
      teacher: teacherMap is Map<String, dynamic>
          ? Teacher.fromMap(teacherMap)
          : null,
      liveRoom: map['live_room'] as String?,
      description: map['description'] as String?,
      groupId: map['group_id'] as String?,
    );
  }
}

class Recording {
  const Recording({
    required this.id,
    required this.title,
    required this.category,
    required this.recordedAt,
    required this.durationSeconds,
    required this.progress,
    this.teacher,
    this.lessonId,
    this.videoUrl,
    this.thumbnailUrl,
    this.attendeeCount = 0,
    this.description,
  });

  final String id;
  final String title;
  final String category;
  final DateTime recordedAt;
  final int durationSeconds;

  /// 0..1 — how much of the recording this student has watched.
  final double progress;
  final Teacher? teacher;
  final String? lessonId;
  final String? videoUrl;
  final String? thumbnailUrl;
  final int attendeeCount;
  final String? description;

  bool get isWatched => progress >= 0.995;
  bool get isUnstarted => progress <= 0.001;

  /// "59:48" / "1:24:10"
  String get durationLabel {
    final d = Duration(seconds: durationSeconds);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  String get progressLabel {
    if (isWatched) return "Ko'rildi";
    if (isUnstarted) return 'Yangi';
    return '${(progress * 100).round()}%';
  }

  Color get progressColor =>
      isWatched ? HkColors.successBright : HkColors.lime;

  /// Thumbnail gradient, keyed off category so the library reads as grouped
  /// even before the labels are scanned.
  LinearGradient get thumbnailGradient {
    final colors = switch (category) {
      'TOPIK' => [const Color(0xFF7E57C2), const Color(0xFF311B69)],
      'Grammatika' => [const Color(0xFF15A05A), const Color(0xFF0C3D24)],
      'Tinglash' => [const Color(0xFFE0A93A), const Color(0xFF7A4900)],
      _ => [const Color(0xFF2E5FA8), const Color(0xFF0F213D)],
    };
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }

  factory Recording.fromMap(Map<String, dynamic> map) {
    final teacherMap = map['teacher'];
    return Recording(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? '—',
      category: (map['category'] as String?) ?? 'Koreys tili',
      recordedAt: DateTime.parse(map['recorded_at'] as String).toLocal(),
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      progress: ((map['progress'] as num?) ?? 0).toDouble().clamp(0, 1),
      teacher: teacherMap is Map<String, dynamic>
          ? Teacher.fromMap(teacherMap)
          : null,
      lessonId: map['lesson_id'] as String?,
      videoUrl: map['video_url'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      attendeeCount: (map['attendee_count'] as num?)?.toInt() ?? 0,
      description: map['description'] as String?,
    );
  }
}

enum MaterialKind { pdf, doc, link, audio }

class LessonMaterial {
  const LessonMaterial({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    this.sizeBytes,
  });

  final String id;
  final String name;
  final MaterialKind kind;
  final String url;
  final int? sizeBytes;

  IconData get icon => switch (kind) {
        MaterialKind.pdf => Icons.picture_as_pdf_rounded,
        MaterialKind.doc => Icons.description_rounded,
        MaterialKind.audio => Icons.headphones_rounded,
        MaterialKind.link => Icons.link_rounded,
      };

  factory LessonMaterial.fromMap(Map<String, dynamic> map) => LessonMaterial(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '—',
        kind: MaterialKind.values.firstWhere(
          (k) => k.name == map['kind'],
          orElse: () => MaterialKind.link,
        ),
        url: (map['url'] as String?) ?? '',
        sizeBytes: (map['size_bytes'] as num?)?.toInt(),
      );
}

class LessonQuiz {
  const LessonQuiz({
    required this.id,
    required this.title,
    required this.questionCount,
    this.completed = false,
  });

  final String id;
  final String title;
  final int questionCount;
  final bool completed;

  factory LessonQuiz.fromMap(Map<String, dynamic> map) => LessonQuiz(
        id: map['id'] as String,
        title: (map['title'] as String?) ?? 'Dars testi',
        questionCount: (map['question_count'] as num?)?.toInt() ?? 0,
        completed: (map['completed'] as bool?) ?? false,
      );
}

class Assignment {
  const Assignment({
    required this.id,
    required this.title,
    required this.submitted,
    this.dueAt,
  });

  final String id;
  final String title;
  final bool submitted;
  final DateTime? dueAt;

  String get statusLabel => submitted ? 'Topshirilgan' : 'Topshirilmagan';

  factory Assignment.fromMap(Map<String, dynamic> map) => Assignment(
        id: map['id'] as String,
        title: (map['title'] as String?) ?? 'Uy vazifasi',
        submitted: (map['submitted'] as bool?) ?? false,
        dueAt: map['due_at'] == null
            ? null
            : DateTime.parse(map['due_at'] as String).toLocal(),
      );
}

/// A person in the live room's right rail.
class Participant {
  const Participant({
    required this.id,
    required this.name,
    required this.initials,
    this.isHost = false,
    this.isSelf = false,
    this.micOn = false,
    this.handRaised = false,
  });

  final String id;
  final String name;
  final String initials;
  final bool isHost;
  final bool isSelf;
  final bool micOn;
  final bool handRaised;

  String? get roleLabel {
    if (isSelf) return 'Siz';
    if (isHost) return 'Host';
    return null;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.author,
    required this.sentAt,
    required this.text,
    this.isSelf = false,
  });

  final String id;
  final String author;
  final DateTime sentAt;
  final String text;
  final bool isSelf;
}

/// The four numbers on the dashboard's stat row.
class DashboardStats {
  const DashboardStats({
    required this.lessonsToday,
    required this.activeStudents,
    required this.averageAttendance,
    required this.recordingCount,
  });

  final int lessonsToday;
  final int activeStudents;

  /// 0..1
  final double averageAttendance;
  final int recordingCount;

  static const empty = DashboardStats(
    lessonsToday: 0,
    activeStudents: 0,
    averageAttendance: 0,
    recordingCount: 0,
  );

  factory DashboardStats.fromMap(Map<String, dynamic> map) => DashboardStats(
        lessonsToday: (map['lessons_today'] as num?)?.toInt() ?? 0,
        activeStudents: (map['active_students'] as num?)?.toInt() ?? 0,
        averageAttendance:
            ((map['average_attendance'] as num?) ?? 0).toDouble().clamp(0, 1),
        recordingCount: (map['recording_count'] as num?)?.toInt() ?? 0,
      );
}

/// The signed-in person.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.initials,
    required this.role,
    this.username,
    this.level,
    this.mustChangePassword = false,
  });

  final String id;
  final String fullName;
  final String initials;

  /// 'student' | 'teacher' | 'admin'
  final String role;

  /// The login an administrator issued. Null for an account created by hand
  /// with a real email address.
  final String? username;
  final int? level;

  /// Set when an admin issues or resets this account's password. While it is
  /// true the router holds the user on the change-password screen.
  final bool mustChangePassword;

  /// Teachers and admins both get the staff-only controls on the schedule.
  bool get isStaff => role == 'admin' || role == 'teacher';

  /// Only a full admin sees the account panel. A teacher managing the roster
  /// would be a different decision, and this is the conservative one.
  bool get isAdmin => role == 'admin';

  String get subtitle => switch (role) {
        'admin' => 'Administrator',
        'teacher' => "O'qituvchi",
        _ => level == null ? 'Talaba' : 'Daraja $level',
      };

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final name = (map['full_name'] as String?) ?? 'Talaba';
    return UserProfile(
      id: map['user_id'] as String,
      fullName: name,
      initials: (map['initials'] as String?) ?? Teacher._initialsOf(name),
      role: (map['role'] as String?) ?? 'student',
      username: map['username'] as String?,
      level: (map['level'] as num?)?.toInt(),
      mustChangePassword: (map['must_change_password'] as bool?) ?? false,
    );
  }
}

/// A row in the bell panel.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    this.body,
    this.lessonId,
    this.recordingId,
    this.readAt,
  });

  final String id;
  final String title;

  /// `lesson_starting` | `new_recording` | `homework` | `info`. Deliberately
  /// a string — see the migration for why it is not an enum.
  final String kind;
  final DateTime createdAt;
  final String? body;
  final String? lessonId;
  final String? recordingId;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  /// Where tapping the row goes, or null if it links nowhere.
  String? get route {
    if (recordingId != null) return '/recordings/$recordingId';
    if (kind == 'lesson_starting') return '/live';
    if (lessonId != null) return '/schedule';
    return null;
  }

  IconData get icon => switch (kind) {
        'lesson_starting' => Icons.videocam_rounded,
        'new_recording' => Icons.play_circle_outline_rounded,
        'homework' => Icons.assignment_outlined,
        _ => Icons.info_outline_rounded,
      };

  Color get accent => switch (kind) {
        'lesson_starting' => HkColors.lime,
        'new_recording' => HkColors.infoText,
        'homework' => HkColors.warningBright,
        _ => HkColors.textSecondary,
      };

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String,
        title: (map['title'] as String?) ?? '',
        kind: (map['kind'] as String?) ?? 'info',
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        body: map['body'] as String?,
        lessonId: map['lesson_id'] as String?,
        recordingId: map['recording_id'] as String?,
        readAt: map['read_at'] == null
            ? null
            : DateTime.parse(map['read_at'] as String).toLocal(),
      );
}

/// What the search sheet found. Kept as one object so the sheet can show
/// "nothing matched" once rather than per section.
class SearchResults {
  const SearchResults({required this.lessons, required this.recordings});

  final List<Lesson> lessons;
  final List<Recording> recordings;

  static const empty = SearchResults(lessons: [], recordings: []);

  bool get isEmpty => lessons.isEmpty && recordings.isEmpty;
  int get total => lessons.length + recordings.length;
}
