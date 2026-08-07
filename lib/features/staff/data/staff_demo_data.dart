import '../../../core/clock.dart';
import '../domain/staff_models.dart';

/// Fixtures for the teacher and admin panels, transcribed from the second
/// design round's prototype.
///
/// Only used when no Supabase credentials were supplied (see `HkEnv`). It
/// exists so the seven new screens can be reviewed against the design without
/// a backend, and so the golden tests have something deterministic to render.
abstract final class StaffDemoData {
  static const teacherStats = TeacherStats(
    lessonsToday: 4,
    students: 64,
    ungraded: 12,
    averageAttendance: 0.94,
  );

  static List<TeacherStudent> teacherStudents() {
    final now = hkNow();
    return [
      TeacherStudent(
        studentId: 'ts-dm',
        fullName: 'Dilshod Mahmudov',
        groupName: 'Daraja 2 · A',
        attendance: 0.96,
        progress: 0.78,
        lastSeenAt: now.subtract(const Duration(hours: 2)),
      ),
      TeacherStudent(
        studentId: 'ts-nr',
        fullName: 'Nilufar Rashidova',
        groupName: 'Daraja 2 · A',
        attendance: 1,
        progress: 0.92,
        lastSeenAt: now.subtract(const Duration(minutes: 15)),
      ),
      TeacherStudent(
        studentId: 'ts-sm',
        fullName: 'Sardor Mirzayev',
        groupName: 'Daraja 2 · B',
        attendance: 0.74,
        progress: 0.54,
        lastSeenAt: now.subtract(const Duration(days: 1)),
      ),
      TeacherStudent(
        studentId: 'ts-mt',
        fullName: 'Malika Tosheva',
        groupName: 'TOPIK guruhi',
        attendance: 0.92,
        progress: 0.81,
        lastSeenAt: now.subtract(const Duration(hours: 4)),
      ),
      TeacherStudent(
        studentId: 'ts-jb',
        fullName: 'Javohir Bekmurodov',
        groupName: 'Daraja 2 · B',
        attendance: 0.61,
        progress: 0.38,
        lastSeenAt: now.subtract(const Duration(days: 5)),
      ),
      TeacherStudent(
        studentId: 'ts-zs',
        fullName: 'Zilola Saidova',
        groupName: 'TOPIK guruhi',
        attendance: 0.98,
        progress: 0.88,
        lastSeenAt: now.subtract(const Duration(minutes: 30)),
      ),
    ];
  }

  static List<Submission> submissions() {
    final now = hkNow();
    return [
      Submission(
        assignmentId: 'sub-1',
        studentId: 'ts-dm',
        studentName: 'Dilshod Mahmudov',
        assignmentTitle: 'Dialog yozish',
        lessonTitle: '14-dars',
        submittedAt: now.subtract(const Duration(days: 2)),
      ),
      Submission(
        assignmentId: 'sub-2',
        studentId: 'ts-nr',
        studentName: 'Nilufar Rashidova',
        assignmentTitle: 'TOPIK test',
        lessonTitle: "3-bo'lim",
        submittedAt: now.subtract(const Duration(hours: 5)),
      ),
      Submission(
        assignmentId: 'sub-3',
        studentId: 'ts-sm',
        studentName: 'Sardor Mirzayev',
        assignmentTitle: 'Ovozli xabar',
        lessonTitle: 'talaffuz',
        submittedAt: now.subtract(const Duration(hours: 8)),
      ),
      Submission(
        assignmentId: 'sub-4',
        studentId: 'ts-mt',
        studentName: 'Malika Tosheva',
        assignmentTitle: "Yangi so'zlar testi",
        submittedAt: now.subtract(const Duration(days: 1)),
        grade: 88,
        gradedAt: now.subtract(const Duration(hours: 20)),
      ),
      Submission(
        assignmentId: 'sub-5',
        studentId: 'ts-zs',
        studentName: 'Zilola Saidova',
        assignmentTitle: 'Grammatika mashqi · 7',
        submittedAt: now.subtract(const Duration(days: 2)),
        grade: 95,
        gradedAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }

  static List<StudyGroup> groups() => const [
        StudyGroup(
          id: 'g-2a',
          name: 'Daraja 2 · A',
          level: 2,
          teacherId: 'tr-jk',
          teacherName: 'Jasur Karimov',
          memberCount: 24,
        ),
        StudyGroup(
          id: 'g-2b',
          name: 'Daraja 2 · B',
          level: 2,
          teacherId: 'tr-ny',
          teacherName: 'Nodira Yusupova',
          memberCount: 22,
        ),
        StudyGroup(
          id: 'g-1a',
          name: 'Daraja 1 · A',
          level: 1,
          teacherId: 'tr-ms',
          teacherName: 'Malika Sodiqova',
          memberCount: 18,
        ),
        StudyGroup(
          id: 'g-topik',
          name: 'TOPIK guruhi',
          teacherId: 'tr-ar',
          teacherName: 'Aziz Rahimov',
          memberCount: 20,
        ),
      ];

  static const adminKpis = AdminKpis(
    activeStudents: 132,
    weeklyLessons: 46,
    averageAttendance: 0.91,
    monthRevenue: 742000000,
    teacherCount: 8,
    outstandingAmount: 86000000,
    outstandingCount: 9,
  );

  static List<TeacherRosterEntry> teacherRoster() => const [
        TeacherRosterEntry(
          id: 'tr-jk',
          fullName: 'Jasur Karimov',
          subject: 'Suhbat · Daraja 1–3',
          weeklyLessons: 14,
          studentCount: 64,
          rating: 4.9,
          load: 0.86,
        ),
        TeacherRosterEntry(
          id: 'tr-ny',
          fullName: 'Nodira Yusupova',
          subject: 'Grammatika',
          weeklyLessons: 11,
          studentCount: 48,
          rating: 4.8,
          load: 0.68,
        ),
        TeacherRosterEntry(
          id: 'tr-ar',
          fullName: 'Aziz Rahimov',
          subject: 'TOPIK tayyorgarlik',
          weeklyLessons: 9,
          studentCount: 40,
          rating: 4.7,
          load: 0.58,
        ),
        TeacherRosterEntry(
          id: 'tr-ms',
          fullName: 'Malika Sodiqova',
          subject: 'Tinglab tushunish',
          weeklyLessons: 8,
          studentCount: 36,
          rating: 4.9,
          load: 0.52,
        ),
        TeacherRosterEntry(
          id: 'tr-sk',
          fullName: 'Shahnoza Karimova',
          subject: 'Yozma nutq',
          weeklyLessons: 6,
          studentCount: 28,
          rating: 4.6,
          load: 0.40,
          status: 'leave',
        ),
        TeacherRosterEntry(
          id: 'tr-bt',
          fullName: 'Bekzod Toshmatov',
          subject: "Talaffuz · boshlang'ich",
          weeklyLessons: 4,
          studentCount: 18,
          rating: 4.5,
          load: 0.28,
          status: 'new',
        ),
      ];

  static List<AdminStudent> adminStudents() {
    final now = hkNow();
    return [
      AdminStudent(
        studentId: 'ts-dm',
        fullName: 'Dilshod Mahmudov',
        phone: '+998 90 123 45 67',
        groupName: 'Daraja 2 · A',
        groupId: 'g-2a',
        teacherName: 'Jasur Karimov',
        attendance: 0.96,
        paymentStatus: PaymentStatus.confirmed,
        lastSeenAt: now.subtract(const Duration(hours: 2)),
      ),
      AdminStudent(
        studentId: 'ts-nr',
        fullName: 'Nilufar Rashidova',
        phone: '+998 91 234 56 78',
        groupName: 'Daraja 2 · A',
        groupId: 'g-2a',
        teacherName: 'Jasur Karimov',
        attendance: 1,
        paymentStatus: PaymentStatus.confirmed,
        lastSeenAt: now.subtract(const Duration(minutes: 15)),
      ),
      AdminStudent(
        studentId: 'ts-sm',
        fullName: 'Sardor Mirzayev',
        phone: '+998 93 345 67 89',
        groupName: 'Daraja 2 · B',
        groupId: 'g-2b',
        teacherName: 'Nodira Yusupova',
        attendance: 0.74,
        paymentStatus: PaymentStatus.pending,
        lastSeenAt: now.subtract(const Duration(days: 1)),
      ),
      AdminStudent(
        studentId: 'ts-mt',
        fullName: 'Malika Tosheva',
        phone: '+998 94 456 78 90',
        groupName: 'TOPIK guruhi',
        groupId: 'g-topik',
        teacherName: 'Aziz Rahimov',
        attendance: 0.92,
        paymentStatus: PaymentStatus.confirmed,
        lastSeenAt: now.subtract(const Duration(hours: 4)),
      ),
      AdminStudent(
        studentId: 'ts-jb',
        fullName: 'Javohir Bekmurodov',
        phone: '+998 97 567 89 01',
        groupName: 'Daraja 2 · B',
        groupId: 'g-2b',
        teacherName: 'Nodira Yusupova',
        attendance: 0.61,
        paymentStatus: PaymentStatus.overdue,
        lastSeenAt: now.subtract(const Duration(days: 5)),
      ),
      AdminStudent(
        studentId: 'ts-zs',
        fullName: 'Zilola Saidova',
        phone: '+998 99 678 90 12',
        groupName: 'TOPIK guruhi',
        groupId: 'g-topik',
        teacherName: 'Aziz Rahimov',
        attendance: 0.98,
        paymentStatus: PaymentStatus.confirmed,
        lastSeenAt: now.subtract(const Duration(minutes: 30)),
      ),
      AdminStudent(
        studentId: 'ts-at',
        fullName: 'Aziz Tursunov',
        phone: '+998 90 789 01 23',
        groupName: 'Daraja 1 · A',
        groupId: 'g-1a',
        teacherName: 'Malika Sodiqova',
        attendance: 0.88,
        paymentStatus: PaymentStatus.pending,
        lastSeenAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  static const plans = [
    PaymentPlan(code: 'standard', name: 'Standard', monthlyAmount: 5000000),
    PaymentPlan(code: 'premium', name: 'Premium', monthlyAmount: 10000000),
  ];

  static List<Payment> payments() {
    final now = hkNow();
    final period = DateTime(now.year, now.month);

    Payment of(
      String id,
      String studentId,
      String name,
      String plan,
      int amount,
      int day,
      PaymentStatus status,
    ) =>
        Payment(
          id: id,
          studentId: studentId,
          studentName: name,
          planCode: plan.toLowerCase(),
          planName: plan,
          amount: amount,
          period: period,
          dueDate: DateTime(now.year, now.month, 10),
          paidAt: status == PaymentStatus.confirmed
              ? DateTime(now.year, now.month, day)
              : null,
          status: status,
        );

    return [
      of('p1', 'ts-nr', 'Nilufar Rashidova', 'Premium', 10000000, 24,
          PaymentStatus.confirmed),
      of('p2', 'ts-dm', 'Dilshod Mahmudov', 'Standard', 5000000, 23,
          PaymentStatus.confirmed),
      of('p3', 'ts-mt', 'Malika Tosheva', 'Standard', 5000000, 22,
          PaymentStatus.confirmed),
      of('p4', 'ts-sm', 'Sardor Mirzayev', 'Standard', 5000000, 26,
          PaymentStatus.pending),
      of('p5', 'ts-zs', 'Zilola Saidova', 'Premium', 10000000, 20,
          PaymentStatus.confirmed),
      of('p6', 'ts-jb', 'Javohir Bekmurodov', 'Standard', 5000000, 18,
          PaymentStatus.overdue),
    ];
  }
}
