/// Build-time configuration.
///
/// Supply at build/run time:
///
///   flutter run -d windows \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// Nothing is hard-coded. When the values are absent the app runs in demo
/// mode against the seed fixtures in `lessons_repository.dart` — that keeps
/// `flutter run` useful for design review without handing every developer a
/// production key, and it is why no anon key appears in this repository.
abstract final class HkEnv {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
