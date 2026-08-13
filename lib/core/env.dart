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
    defaultValue: 'https://dfduzrzqzghsiblpztdm.supabase.co',
  );

  /// Supabase's current key format (`sb_publishable_…`), which replaced the
  /// legacy `anon` JWT. Sent as the `apikey` header exactly the same way.
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_3B5-KHohbmx-cysPPo4e7Q_uou0x2o1',
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
}
