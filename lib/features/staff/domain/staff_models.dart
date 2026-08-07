import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../design_system/tokens.dart';

/// Deterministic avatar gradient shared by every roster in the staff panels,
/// so one person is the same colour on the teacher's list and the admin's.
LinearGradient hkGradientFor(String seed) {
  const palettes = [
    [Color(0xFF7E57C2), Color(0xFF311B69)],
    [Color(0xFF6FA0E0), Color(0xFF16305A)],
    [Color(0xFFE0A93A), Color(0xFF7A4900)],
    [Color(0xFF15A05A), Color(0xFF0C3D24)],
    [Color(0xFFE891B6), Color(0xFF7A2E54)],
    [Color(0xFFC2DA2E), Color(0xFF7D8F10)],
  ];
  final palette = palettes[seed.hashCode.abs() % palettes.length];
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: palette,
  );
}

String hkInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// "2 soat oldin" / "5 kun oldin" / "Hech qachon". Absolute timestamps in a
/// roster make the reader do the arithmetic.
String hkRelative(DateTime? at, {required DateTime now}) {
  if (at == null) return 'Hech qachon';
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'hozir';
  if (d.inMinutes < 60) return '${d.inMinutes} daqiqa oldin';
  if (d.inHours < 24) return '${d.inHours} soat oldin';
  if (d.inDays < 7) return '${d.inDays} kun oldin';
  return DateFormat('d-MMMM', 'uz').format(at);
}

/// Thresholds shared by every attendance and progress readout, so "74%" is
/// the same shade of amber wherever it appears.
Color hkRateColor(double rate) {
  if (rate >= 0.9) return HkColors.successBright;
  if (rate >= 0.75) return HkColors.lime;
  if (rate >= 0.6) return HkColors.warningBright;
  return HkColors.dangerBright;
}

String hkPercent(double rate) => '${(rate * 100).round()}%';

// ----------------------------------------------------------------- teacher ---

class TeacherStats {
  const TeacherStats({
    required this.lessonsToday,
    required this.students,
    required this.ungraded,
    required this.averageAttendance,
  });

  final int lessonsToday;
  final int students;
  final int ungraded;
  final double averageAttendance;

  static const empty = TeacherStats(
    lessonsToday: 0,
    students: 0,
    ungraded: 0,
    averageAttendance: 0,
  );

  factory TeacherStats.fromMap(Map<String, dynamic> map) => TeacherStats(
        lessonsToday: (map['lessons_today'] as num?)?.toInt() ?? 0,
        students: (map['students'] as num?)?.toInt() ?? 0,
        ungraded: (map['ungraded'] as num?)?.toInt() ?? 0,
        averageAttendance:
            ((map['average_attendance'] as num?) ?? 0).toDouble().clamp(0, 1),
      );
}

/// One of the teacher's students, as the "Talabalarim" table lists them.
class TeacherStudent {
  const TeacherStudent({
    required this.studentId,
    required this.fullName,
    required this.attendance,
    required this.progress,
    this.username,
    this.groupName,
    this.lastSeenAt,
  });

  final String studentId;
  final String fullName;
  final double attendance;
  final double progress;
  final String? username;
  final String? groupName;
  final DateTime? lastSeenAt;

  String get initials => hkInitials(fullName);
  LinearGradient get gradient => hkGradientFor(studentId);

  /// The design flags a student as needing attention rather than showing a
  /// bare number, because a teacher scanning sixty rows will not do the
  /// comparison themselves.
  bool get needsAttention => attendance < 0.8 || progress < 0.6;

  String get statusLabel => needsAttention ? 'Diqqat' : 'Faol';

  Color get statusColor =>
      needsAttention ? HkColors.warningBright : HkColors.successBright;

  Color get statusBackground => needsAttention
      ? const Color(0x29F0B24A)
      : const Color(0x2934C77B);

  factory TeacherStudent.fromMap(Map<String, dynamic> map) => TeacherStudent(
        studentId: map['student_id'] as String,
        fullName: (map['full_name'] as String?) ?? '—',
        attendance: ((map['attendance'] as num?) ?? 0).toDouble().clamp(0, 1),
        progress: ((map['progress'] as num?) ?? 0).toDouble().clamp(0, 1),
        username: map['username'] as String?,
        groupName: map['group_name'] as String?,
        lastSeenAt: map['last_seen_at'] == null
            ? null
            : DateTime.parse(map['last_seen_at'] as String).toLocal(),
      );
}

/// A handed-in piece of homework, graded or waiting.
class Submission {
  const Submission({
    required this.assignmentId,
    required this.studentId,
    required this.studentName,
    required this.assignmentTitle,
    required this.submittedAt,
    this.lessonTitle,
    this.grade,
    this.gradedAt,
    this.note,
  });

  final String assignmentId;
  final String studentId;
  final String studentName;
  final String assignmentTitle;
  final DateTime submittedAt;
  final String? lessonTitle;
  final int? grade;
  final DateTime? gradedAt;
  final String? note;

  bool get isGraded => gradedAt != null;

  String get statusLabel => isGraded ? 'Baholangan' : 'Kutilmoqda';

  Color get statusColor =>
      isGraded ? HkColors.successBright : HkColors.warningBright;

  Color get statusBackground =>
      isGraded ? const Color(0x2934C77B) : const Color(0x29F0B24A);

  String get initials => hkInitials(studentName);
  LinearGradient get gradient => hkGradientFor(studentId);

  factory Submission.fromMap(Map<String, dynamic> map) => Submission(
        assignmentId: map['assignment_id'] as String,
        studentId: map['student_id'] as String,
        studentName: (map['student_name'] as String?) ?? '—',
        assignmentTitle: (map['assignment_title'] as String?) ?? 'Vazifa',
        submittedAt: DateTime.parse(map['submitted_at'] as String).toLocal(),
        lessonTitle: map['lesson_title'] as String?,
        grade: (map['grade'] as num?)?.toInt(),
        gradedAt: map['graded_at'] == null
            ? null
            : DateTime.parse(map['graded_at'] as String).toLocal(),
        note: map['note'] as String?,
      );
}

// ------------------------------------------------------------------- admin ---

class AdminKpis {
  const AdminKpis({
    required this.activeStudents,
    required this.weeklyLessons,
    required this.averageAttendance,
    required this.monthRevenue,
    required this.teacherCount,
    required this.outstandingAmount,
    required this.outstandingCount,
  });

  final int activeStudents;
  final int weeklyLessons;
  final double averageAttendance;

  /// Whole so'm. Never a double — see the migration's note.
  final int monthRevenue;
  final int teacherCount;
  final int outstandingAmount;
  final int outstandingCount;

  static const empty = AdminKpis(
    activeStudents: 0,
    weeklyLessons: 0,
    averageAttendance: 0,
    monthRevenue: 0,
    teacherCount: 0,
    outstandingAmount: 0,
    outstandingCount: 0,
  );

  factory AdminKpis.fromMap(Map<String, dynamic> map) => AdminKpis(
        activeStudents: (map['active_students'] as num?)?.toInt() ?? 0,
        weeklyLessons: (map['weekly_lessons'] as num?)?.toInt() ?? 0,
        averageAttendance:
            ((map['average_attendance'] as num?) ?? 0).toDouble().clamp(0, 1),
        monthRevenue: (map['month_revenue'] as num?)?.toInt() ?? 0,
        teacherCount: (map['teacher_count'] as num?)?.toInt() ?? 0,
        outstandingAmount: (map['outstanding_amount'] as num?)?.toInt() ?? 0,
        outstandingCount: (map['outstanding_count'] as num?)?.toInt() ?? 0,
      );
}

/// A teacher as the admin roster lists them.
class TeacherRosterEntry {
  const TeacherRosterEntry({
    required this.id,
    required this.fullName,
    required this.weeklyLessons,
    required this.studentCount,
    required this.load,
    this.subject,
    this.rating,
    this.status = 'active',
  });

  final String id;
  final String fullName;
  final int weeklyLessons;
  final int studentCount;

  /// 0..1 against a nominal 16-lesson week.
  final double load;
  final String? subject;
  final double? rating;
  final String status;

  String get initials => hkInitials(fullName);
  LinearGradient get gradient => hkGradientFor(id);

  String get statusLabel => switch (status) {
        'leave' => "Ta'til",
        'new' => 'Yangi',
        'left' => 'Ketgan',
        _ => 'Faol',
      };

  Color get statusColor => switch (status) {
        'leave' => HkColors.warningBright,
        'new' => HkColors.infoText,
        'left' => HkColors.textTertiary,
        _ => HkColors.successBright,
      };

  Color get statusBackground => switch (status) {
        'leave' => const Color(0x29F0B24A),
        'new' => const Color(0x2E6EA0E0),
        'left' => const Color(0x14FFFFFF),
        _ => const Color(0x2934C77B),
      };

  /// Lime once the week is comfortably full, blue while there is room. The
  /// point of the column is spotting who is over- and under-booked.
  Color get loadColor =>
      load >= 0.8 ? HkColors.lime : const Color(0xFF6FA0E0);

  factory TeacherRosterEntry.fromMap(Map<String, dynamic> map) =>
      TeacherRosterEntry(
        id: map['id'] as String,
        fullName: (map['full_name'] as String?) ?? '—',
        weeklyLessons: (map['weekly_lessons'] as num?)?.toInt() ?? 0,
        studentCount: (map['student_count'] as num?)?.toInt() ?? 0,
        load: ((map['load'] as num?) ?? 0).toDouble().clamp(0, 1),
        subject: map['subject'] as String?,
        rating: (map['rating'] as num?)?.toDouble(),
        status: (map['status'] as String?) ?? 'active',
      );
}

enum PaymentStatus {
  confirmed('Tasdiqlangan'),
  pending('Kutilmoqda'),
  overdue('Kechikkan'),
  cancelled('Bekor qilingan');

  const PaymentStatus(this.label);

  final String label;

  static PaymentStatus fromWire(String? value) => switch (value) {
        'confirmed' => PaymentStatus.confirmed,
        'overdue' => PaymentStatus.overdue,
        'cancelled' => PaymentStatus.cancelled,
        _ => PaymentStatus.pending,
      };

  Color get color => switch (this) {
        PaymentStatus.confirmed => HkColors.successBright,
        PaymentStatus.pending => HkColors.warningBright,
        PaymentStatus.overdue => HkColors.dangerBright,
        PaymentStatus.cancelled => HkColors.textTertiary,
      };

  Color get background => switch (this) {
        PaymentStatus.confirmed => const Color(0x2934C77B),
        PaymentStatus.pending => const Color(0x29F0B24A),
        PaymentStatus.overdue => const Color(0x29F2746A),
        PaymentStatus.cancelled => const Color(0x14FFFFFF),
      };
}

/// A student as the admin roster lists them: contact, group, payment state.
class AdminStudent {
  const AdminStudent({
    required this.studentId,
    required this.fullName,
    required this.attendance,
    required this.paymentStatus,
    this.username,
    this.phone,
    this.level,
    this.groupName,
    this.groupId,
    this.teacherName,
    this.lastSeenAt,
  });

  final String studentId;
  final String fullName;
  final double attendance;
  final PaymentStatus paymentStatus;
  final String? username;
  final String? phone;
  final int? level;
  final String? groupName;

  /// Which group they are in, so the assignment dialog can preselect it. The
  /// group is what decides whose student they are.
  final String? groupId;
  final String? teacherName;
  final DateTime? lastSeenAt;

  String get initials => hkInitials(fullName);
  LinearGradient get gradient => hkGradientFor(studentId);

  factory AdminStudent.fromMap(Map<String, dynamic> map) => AdminStudent(
        studentId: map['student_id'] as String,
        fullName: (map['full_name'] as String?) ?? '—',
        attendance: ((map['attendance'] as num?) ?? 0).toDouble().clamp(0, 1),
        // No payment row at all reads as pending: the student owes this month
        // and nobody has recorded anything, which is exactly what the office
        // needs to see.
        paymentStatus: PaymentStatus.fromWire(map['payment_status'] as String?),
        username: map['username'] as String?,
        phone: map['phone'] as String?,
        level: (map['level'] as num?)?.toInt(),
        groupName: map['group_name'] as String?,
        groupId: map['group_id'] as String?,
        teacherName: map['teacher_name'] as String?,
        lastSeenAt: map['last_seen_at'] == null
            ? null
            : DateTime.parse(map['last_seen_at'] as String).toLocal(),
      );
}

class Payment {
  const Payment({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.amount,
    required this.period,
    required this.status,
    this.planCode,
    this.planName,
    this.dueDate,
    this.paidAt,
    this.note,
  });

  final String id;
  final String studentId;
  final String studentName;

  /// Whole so'm.
  final int amount;
  final DateTime period;
  final PaymentStatus status;
  final String? planCode;
  final String? planName;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final String? note;

  String get initials => hkInitials(studentName);
  LinearGradient get gradient => hkGradientFor(studentId);

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
        id: map['id'] as String,
        studentId: map['student_id'] as String,
        studentName: (map['student_name'] as String?) ?? '—',
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        period: DateTime.parse(map['period'] as String),
        status: PaymentStatus.fromWire(map['status'] as String?),
        planCode: map['plan_code'] as String?,
        planName: map['plan_name'] as String?,
        dueDate: map['due_date'] == null
            ? null
            : DateTime.parse(map['due_date'] as String),
        paidAt: map['paid_at'] == null
            ? null
            : DateTime.parse(map['paid_at'] as String).toLocal(),
        note: map['note'] as String?,
      );
}

class PaymentPlan {
  const PaymentPlan({
    required this.code,
    required this.name,
    required this.monthlyAmount,
  });

  final String code;
  final String name;
  final int monthlyAmount;

  factory PaymentPlan.fromMap(Map<String, dynamic> map) => PaymentPlan(
        code: map['code'] as String,
        name: (map['name'] as String?) ?? '—',
        monthlyAmount: (map['monthly_amount'] as num?)?.toInt() ?? 0,
      );
}

/// Money, formatted the way it is written in Uzbekistan: space-grouped
/// thousands, no decimals, currency spelled out.
///
///   5000000  -> "5 000 000 UZS"
String hkSum(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  final sign = amount < 0 ? '-' : '';
  return '$sign$buffer UZS';
}

/// The compact form used on stat cards, where the full number does not fit:
/// 742 000 000 -> "742M". Rounded, and only ever shown next to a label that
/// says what it is.
String hkSumShort(int amount) {
  if (amount.abs() >= 1000000000) {
    final b = amount / 1000000000;
    return '${b.toStringAsFixed(b.truncateToDouble() == b ? 0 : 1)} mlrd';
  }
  if (amount.abs() >= 1000000) return '${(amount / 1000000).round()}M';
  if (amount.abs() >= 1000) return '${(amount / 1000).round()}K';
  return '$amount';
}

/// A teaching group. The link between a student and a teacher: a student is
/// in a group, a group has a teacher.
class StudyGroup {
  const StudyGroup({
    required this.id,
    required this.name,
    required this.memberCount,
    this.level,
    this.teacherId,
    this.teacherName,
    this.isActive = true,
  });

  final String id;
  final String name;
  final int memberCount;
  final int? level;
  final String? teacherId;
  final String? teacherName;
  final bool isActive;

  String get subtitle {
    final parts = <String>[
      ?teacherName,
      '$memberCount ta talaba',
    ];
    return parts.join(' · ');
  }

  factory StudyGroup.fromMap(Map<String, dynamic> map) => StudyGroup(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '—',
        memberCount: (map['member_count'] as num?)?.toInt() ?? 0,
        level: (map['level'] as num?)?.toInt(),
        teacherId: map['teacher_id'] as String?,
        teacherName: map['teacher_name'] as String?,
        isActive: (map['is_active'] as bool?) ?? true,
      );
}
