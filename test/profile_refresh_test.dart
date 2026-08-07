import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hanguk_online/features/auth/data/auth_repository.dart';
import 'package:hanguk_online/features/lessons/data/demo_data.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/data/providers.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';

/// Counts how many times the profile is actually fetched.
class _CountingRepository extends LessonsRepository {
  _CountingRepository() : super(null);

  int fetches = 0;

  @override
  Future<UserProfile> currentProfile() async {
    fetches++;
    return DemoData.profile;
  }
}

void main() {
  test('the profile is refetched when the session changes', () async {
    // Regression test. The router reads profileProvider on its first redirect,
    // which runs before anyone has signed in; that read fails and the failure
    // is cached. Without a dependency on the auth state nothing re-runs it, so
    // a signed-in admin kept showing as a nameless student — and the
    // must_change_password gate never fired, because the router saw a null
    // profile and skipped the check entirely.
    final repository = _CountingRepository();
    final sessions = StreamController<Session?>.broadcast();
    addTearDown(sessions.close);

    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(null),
        lessonsRepositoryProvider.overrideWithValue(repository),
        authStateProvider.overrideWith((ref) => sessions.stream),
      ],
    );
    addTearDown(container.dispose);

    // Keep the provider alive across the emissions below.
    container.listen(profileProvider, (_, _) {});

    await container.read(profileProvider.future);
    expect(repository.fetches, 1);

    // Signing in emits on the auth stream.
    sessions.add(null);
    await Future<void>.delayed(Duration.zero);
    await container.read(profileProvider.future);

    expect(
      repository.fetches,
      2,
      reason: 'a new session must produce a fresh profile, not the one '
          'cached from before sign-in',
    );
  });
}
