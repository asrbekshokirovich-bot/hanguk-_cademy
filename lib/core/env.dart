/// Backend configuration.
///
/// The defaults point at the project's own Supabase instance, so a plain
/// `flutter run -d windows` talks to the real backend with no flags.
///
/// The publishable key is safe to ship in the binary — that is what the key
/// type is for. It carries no privileges of its own: every request it makes
/// is still filtered by the row-level security policies in
/// `supabase/migrations/`, and an unauthenticated caller can read nothing.
/// The keys that must never appear here are `service_role` and any
/// `sb_secret_…`, which bypass those policies entirely.
///
/// Override per build when pointing at a different project (a staging copy,
/// a reviewer's own instance):
///
///   flutter run -d windows \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_…
///
/// Passing an empty URL forces demo mode, which serves the fixtures in
/// `demo_data.dart` instead of querying anything:
///
///   flutter run -d windows --dart-define=SUPABASE_URL=
abstract final class HkEnv {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
        defaultValue: 'https://iohchwogpzhqmtqyjrrz.supabase.co',
  );

  /// Supabase's current key format (`sb_publishable_…`), which replaced the
  /// legacy `anon` JWT. Sent as the `apikey` header exactly the same way.
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
        defaultValue: 'sb_publishable_zkcqpOhM_thc6J0pfwsnTg_eqgXqfcW',
  );

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Which build this binary is, printed under the login card.
  ///
  /// It exists because of one specific afternoon: three fixes were merged and
  /// built within twenty minutes of each other, the owner re-ran an .exe he
  /// had downloaded before the first of them, and nothing on screen could
  /// tell either of us which build he was looking at. "Is this fixed?" was
  /// unanswerable — the app looks identical either way.
  ///
  /// The Windows workflow passes the short commit sha and the build date:
  ///
  ///   flutter build windows --release --dart-define=BUILD_STAMP=52f293b·13.08
  ///
  /// A local build says `dev`, which is the honest answer for one.
  static const buildStamp = String.fromEnvironment(
    'BUILD_STAMP',
    defaultValue: 'dev',
  );

  /// Whether lessons are actually recorded. They are, now.
  ///
  /// The schema has carried `auto_record` since the first migration, and the
  /// screens drew it faithfully: a switch in the lesson dialog, a "Yozib
  /// olinmoqda" badge with a running clock on the live stage, a marker on the
  /// dashboard. Nothing behind any of it records anything — there is no
  /// egress, no storage bucket, and the recordings library has no player to
  /// play a file with.
  ///
  /// Telling a roomful of students they are being recorded when they are not
  /// is worse than a missing feature, and it runs the other way too: a
  /// teacher who believes the class is saved does not take notes. So the
  /// controls stayed behind this until recording existed.
  ///
  /// It exists: LiveKit egress writes the room to the bucket and the library
  /// row is written when the file is finished (see
  /// `20260921140000_livekit_egress_step2.sql`). Default true, and set it to
  /// false on a project with no `ol_egress_config` row rather than offering
  /// a switch that records nothing:
  ///
  ///   flutter run --dart-define=RECORDING_ENABLED=false
  static const recordingEnabled =
      bool.fromEnvironment('RECORDING_ENABLED', defaultValue: true);

  /// Whether a student's watch progress means anything. It does not.
  ///
  /// `ol_recording_progress` still has no writer: the app opens a recording
  /// in whatever the machine plays video with, and a file playing in another
  /// program cannot report a position. So every percentage derived from it
  /// is zero for everybody — which, left in the "Diqqat" rule, flagged the
  /// whole school.
  ///
  /// Split from [recordingEnabled] on the day recording started working,
  /// because the two are no longer the same question.
  static const watchProgressEnabled =
      bool.fromEnvironment('WATCH_PROGRESS_ENABLED');
}
