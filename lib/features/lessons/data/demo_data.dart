import '../../../core/clock.dart';
import '../domain/models.dart';

/// The prototype's fixture data, transcribed from the handoff's `recordings[]`
/// and `schedule[]` arrays.
///
/// Used only when no Supabase credentials were supplied at build time (see
/// `HkEnv.hasSupabase`). It exists so the UI can be reviewed against the
/// design without a backend — it is never mixed with live data, because a
/// half-real screen is worse than an obviously empty one.
abstract final class DemoData {
  static final _teachers = <String, Teacher>{
    'jk': const Teacher(id: 'jk', fullName: 'Jasur Karimov', initials: 'JK'),
    'ar': const Teacher(id: 'ar', fullName: 'Aziz Rahimov', initials: 'AR'),
    'ny': const Teacher(id: 'ny', fullName: 'Nodira Yusupova', initials: 'NY'),
    'ms': const Teacher(id: 'ms', fullName: 'Malika Sodiqova', initials: 'MS'),
  };

  /// Today at [hour]:[minute], so the dashboard's "today" filter and the live
  /// lesson's running clock behave the same on any day the demo is opened.
  static DateTime _todayAt(int hour, int minute) {
    final now = hkNow();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  static DateTime _dayAt(int addDays, int hour, int minute) {
    final d = _todayAt(hour, minute);
    return d.add(Duration(days: addDays));
  }

  static const profile = UserProfile(
    id: 'demo',
    fullName: 'Aziza K.',
    initials: 'AK',
    role: 'student',
    level: 2,
  );

  static const stats = DashboardStats(
    lessonsToday: 4,
    activeStudents: 24,
    averageAttendance: 0.92,
    recordingCount: 38,
  );

  static List<Lesson> todaysLessons() => [
        Lesson(
          id: 'd1',
          title: 'Grammatika · Daraja 2',
          category: 'Grammatika',
          startsAt: _todayAt(9, 0),
          durationMinutes: 45,
          status: LessonStatus.ended,
          autoRecord: true,
          enrolledCount: 24,
          teacher: _teachers['ny'],
        ),
        Lesson(
          id: 'd2',
          title: 'Koreys tili · Suhbat amaliyoti',
          category: 'Koreys tili',
          description:
              "Bugungi darsda kundalik suhbat iboralari, savol berish "
              "shakllari va tinglab tushunish mashqlari ko'rib chiqiladi.",
          // 12:45 elapsed in the design's hero. Anchoring the start 12m45s
          // ago keeps the running clock honest whenever the demo is opened.
          startsAt: hkNow().subtract(
            const Duration(minutes: 12, seconds: 45),
          ),
          durationMinutes: 60,
          status: LessonStatus.live,
          autoRecord: true,
          enrolledCount: 18,
          teacher: _teachers['jk'],
          liveRoom: 'demo-room',
        ),
        Lesson(
          id: 'd3',
          title: 'TOPIK tayyorgarlik',
          category: 'TOPIK',
          startsAt: _todayAt(16, 0),
          durationMinutes: 90,
          status: LessonStatus.scheduled,
          autoRecord: true,
          enrolledCount: 20,
          teacher: _teachers['ar'],
        ),
        Lesson(
          id: 'd4',
          title: 'Tinglab tushunish',
          category: 'Tinglash',
          startsAt: _todayAt(18, 30),
          durationMinutes: 45,
          status: LessonStatus.scheduled,
          autoRecord: true,
          enrolledCount: 22,
          // Jasur's as well, so the demo's teacher panel shows a day rather
          // than a single row: that panel now lists only the signed-in
          // teacher's lessons, and in the demo that is whoever is teaching
          // the live one.
          teacher: _teachers['jk'],
        ),
      ];

  static List<Lesson> weekSchedule() => [
        ...todaysLessons(),
        Lesson(
          id: 'd5',
          title: 'Grammatika · Daraja 2',
          category: 'Grammatika',
          startsAt: _dayAt(1, 10, 0),
          durationMinutes: 60,
          status: LessonStatus.scheduled,
          autoRecord: true,
          enrolledCount: 24,
          teacher: _teachers['ny'],
        ),
        Lesson(
          id: 'd6',
          title: 'Suhbat amaliyoti',
          category: 'Koreys tili',
          startsAt: _dayAt(1, 15, 0),
          durationMinutes: 90,
          status: LessonStatus.scheduled,
          // The one row in the design with auto-record switched off.
          autoRecord: false,
          enrolledCount: 18,
          teacher: _teachers['jk'],
        ),
      ];

  static List<Recording> recordings() => [
        Recording(
          id: 'r1',
          lessonId: 'd2',
          title: 'Suhbat amaliyoti · 8-dars',
          category: 'Koreys tili',
          recordedAt: DateTime(2026, 6, 22),
          durationSeconds: 3588, // 59:48
          progress: 0.65,
          teacher: _teachers['jk'],
          attendeeCount: 22,
          description:
              "Kundalik suhbatda ishlatiladigan iboralar, savol-javob "
              "amaliyoti va talaffuz mashqlari. Dars oxirida qisqa test bor.",
        ),
        Recording(
          id: 'r2',
          lessonId: 'd3',
          title: "TOPIK · O'qish bo'limi",
          category: 'TOPIK',
          recordedAt: DateTime(2026, 6, 20),
          durationSeconds: 5050, // 1:24:10
          progress: 1,
          teacher: _teachers['ar'],
          attendeeCount: 20,
        ),
        Recording(
          id: 'r3',
          lessonId: 'd1',
          title: 'Grammatika · Daraja 2 — 7-dars',
          category: 'Grammatika',
          recordedAt: DateTime(2026, 6, 19),
          durationSeconds: 2642, // 44:02
          progress: 0,
          teacher: _teachers['ny'],
          attendeeCount: 24,
        ),
        Recording(
          id: 'r4',
          lessonId: 'd4',
          title: 'Tinglab tushunish · 5-dars',
          category: 'Tinglash',
          recordedAt: DateTime(2026, 6, 17),
          durationSeconds: 2335, // 38:55
          progress: 0.30,
          teacher: _teachers['ms'],
          attendeeCount: 22,
        ),
        Recording(
          id: 'r5',
          lessonId: 'd2',
          title: 'Suhbat amaliyoti · 7-dars',
          category: 'Koreys tili',
          recordedAt: DateTime(2026, 6, 15),
          durationSeconds: 3680, // 61:20
          progress: 1,
          teacher: _teachers['jk'],
          attendeeCount: 21,
        ),
        Recording(
          id: 'r6',
          lessonId: 'd3',
          title: "TOPIK · Yozma bo'lim",
          category: 'TOPIK',
          recordedAt: DateTime(2026, 6, 13),
          durationSeconds: 3129, // 52:09
          progress: 0.45,
          teacher: _teachers['ar'],
          attendeeCount: 19,
        ),
      ];

  static List<LessonMaterial> materials() => const [
        LessonMaterial(
          id: 'm1',
          name: 'Dars taqdimoti.pdf',
          kind: MaterialKind.pdf,
          url: '',
          sizeBytes: 2411724,
        ),
        LessonMaterial(
          id: 'm2',
          name: "Yangi so'zlar lug'ati",
          kind: MaterialKind.doc,
          url: '',
          sizeBytes: 184320,
        ),
      ];

  static const quiz = LessonQuiz(
    id: 'q1',
    title: 'Dars testi',
    questionCount: 10,
  );

  static const assignment = Assignment(
    id: 'a1',
    title: 'Uy vazifasi',
    submitted: false,
  );

  /// What the student owes, across their lessons.
  ///
  /// One of each state the card has to draw: handed in, still open with a
  /// deadline ahead, and one that is already past it.
  static List<Assignment> myAssignments() {
    final now = hkNow();
    return [
      Assignment(
        id: 'a1',
        title: 'Yangi so‘zlarni yozib keling',
        body: '3-bo‘limdagi 20 ta so‘zni gap ichida ishlating.',
        submitted: false,
        dueAt: now.add(const Duration(days: 2)),
        lessonId: 'd2',
        lessonTitle: 'Koreys tili · Suhbat amaliyoti',
      ),
      Assignment(
        id: 'a2',
        title: 'Tinglash mashqi',
        body: 'Audioni tinglab, savollarga javob yozing.',
        submitted: false,
        dueAt: now.subtract(const Duration(days: 1)),
        lessonId: 'd4',
        lessonTitle: 'Tinglab tushunish',
      ),
      Assignment(
        id: 'a3',
        title: 'O‘zini tanishtirish',
        submitted: true,
        // Handed in with an attachment, so the demo shows the whole shape of
        // a hand-in and not just its text half.
        fileUrl: 'submissions/a3/demo-student/ozimni-tanishtirish.pdf',
        grade: 92,
        feedback: 'Yaxshi. Fe’l qo‘shimchalariga e’tibor bering.',
        dueAt: now.subtract(const Duration(days: 3)),
        lessonId: 'd1',
        lessonTitle: 'Grammatika · Daraja 2',
      ),
    ];
  }

  static List<AppNotification> notifications() {
    final now = hkNow();
    return [
      AppNotification(
        id: 'n1',
        kind: 'lesson_starting',
        title: 'Suhbat amaliyoti boshlandi',
        body: 'Jasur Karimov jonli efirga chiqdi.',
        createdAt: now.subtract(const Duration(minutes: 12)),
        lessonId: 'd2',
      ),
      AppNotification(
        id: 'n2',
        kind: 'new_recording',
        title: 'Yangi yozuv qo‘shildi',
        body: 'Grammatika · Daraja 2 — 7-dars arxivga tushdi.',
        createdAt: now.subtract(const Duration(hours: 5)),
        recordingId: 'r3',
      ),
      AppNotification(
        id: 'n3',
        kind: 'homework',
        title: 'Uy vazifasi topshirilmagan',
        body: 'Suhbat amaliyoti · 8-dars uchun vazifa kutilmoqda.',
        createdAt: now.subtract(const Duration(days: 1)),
        recordingId: 'r1',
        readAt: null,
      ),
      AppNotification(
        id: 'n4',
        kind: 'info',
        title: 'Jadval yangilandi',
        body: 'Kelasi hafta TOPIK darsi 16:00 ga ko‘chirildi.',
        createdAt: now.subtract(const Duration(days: 3)),
        readAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  static List<Participant> participants() => const [
        Participant(
          id: 'p0',
          name: 'Jasur Karimov',
          initials: 'JK',
          isHost: true,
          micOn: true,
        ),
        Participant(id: 'p1', name: 'Aziza Karimova', initials: 'AK',
            isSelf: true, micOn: false),
        Participant(id: 'p2', name: 'Bekzod Toshev', initials: 'BT',
            micOn: true),
        Participant(id: 'p3', name: 'Dilnoza Sattorova', initials: 'DS',
            handRaised: true),
        Participant(id: 'p4', name: 'Sardor Aliyev', initials: 'SA'),
        Participant(id: 'p5', name: 'Kamola Yusupova', initials: 'KY',
            micOn: true),
      ];

  static List<ChatMessage> chat() {
    final now = hkNow();
    return [
      ChatMessage(
        id: 'c1',
        author: 'Jasur Karimov',
        sentAt: now.subtract(const Duration(minutes: 9)),
        text: "Salom! Bugun 3-bo'limdan boshlaymiz.",
      ),
      ChatMessage(
        id: 'c2',
        author: 'Bekzod Toshev',
        sentAt: now.subtract(const Duration(minutes: 6)),
        text: '안녕하세요 선생님!',
      ),
      ChatMessage(
        id: 'c3',
        author: 'Dilnoza Sattorova',
        sentAt: now.subtract(const Duration(minutes: 3)),
        text: "Ustoz, oxirgi jumlani qaytarib bera olasizmi?",
      ),
    ];
  }
}
