import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../lessons/data/lessons_repository.dart';
import 'username.dart';

/// Sign-in against Supabase, by username.
///
/// There is no sign-up here on purpose: accounts are issued by an
/// administrator through the `admin-users` Edge Function. A student cannot
/// create their own.
///
/// A null client means demo mode — nothing to sign in to, so the user counts
/// as already signed in and the app serves fixtures.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient? _client;

  bool get isDemo => _client == null;

  Session? get currentSession => _client?.auth.currentSession;

  bool get isSignedIn => isDemo || currentSession != null;

  /// Emits on sign in, sign out and token refresh. The router listens to it.
  Stream<AuthState> get onAuthStateChange =>
      _client?.auth.onAuthStateChange ?? const Stream.empty();

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    if (isDemo) return;
    await _client!.auth.signInWithPassword(
      email: HkAuthNaming.toAuthEmail(username),
      password: password,
    );
  }

  Future<void> signOut() async {
    if (isDemo) return;
    await _client!.auth.signOut();
  }

  /// Sets a new password for the signed-in user and clears the
  /// force-change flag.
  ///
  /// Both halves matter: updating the password alone would leave the account
  /// stuck behind the change-password gate forever, and clearing the flag
  /// alone would leave the admin-issued password live.
  Future<void> changeOwnPassword(String newPassword) async {
    final client = _client;
    if (client == null) return;

    await client.auth.updateUser(UserAttributes(password: newPassword));

    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client
        .from('ol_profiles')
        .update({'must_change_password': false}).eq('user_id', userId);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

/// Current session, refreshed whenever Supabase reports a change.
final authStateProvider = StreamProvider<Session?>((ref) async* {
  final auth = ref.watch(authRepositoryProvider);
  yield auth.currentSession;
  await for (final state in auth.onAuthStateChange) {
    yield state.session;
  }
});

/// Turns Supabase's English auth errors into something a student in Tashkent
/// can act on. Anything unrecognised falls through with its original text
/// rather than a generic "xatolik", which would hide real configuration
/// problems — a disabled provider, a rate limit — behind a shrug.
String hkAuthErrorText(Object error) {
  if (error is! AuthException) return '$error';

  final message = error.message.toLowerCase();
  if (message.contains('invalid login credentials')) {
    return "Login yoki parol noto'g'ri.";
  }
  if (message.contains('email not confirmed')) {
    // Should not happen: admin-created accounts are confirmed on creation.
    // If it does, the account was made by hand without email_confirm.
    return 'Hisob tasdiqlanmagan. Administratorga murojaat qiling.';
  }
  if (message.contains('rate limit') || message.contains('too many')) {
    return 'Juda ko‘p urinish. Bir necha daqiqadan so‘ng qayta urining.';
  }
  if (message.contains('password should be at least') ||
      message.contains('password is too short')) {
    return "Parol kamida 8 ta belgidan iborat bo'lsin.";
  }
  if (message.contains('same as the old') ||
      message.contains('should be different')) {
    return 'Yangi parol eskisidan farq qilsin.';
  }
  return error.message;
}
