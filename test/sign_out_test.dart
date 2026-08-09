import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hanguk_online/features/auth/data/auth_repository.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/presentation/profile_menu.dart';

/// Not demo mode — the sign-out button only exists outside it — and signing
/// out does nothing, standing in for the router redirect that would normally
/// follow the auth event.
class _FakeAuth extends AuthRepository {
  _FakeAuth() : super(null);

  int signOuts = 0;

  @override
  bool get isDemo => false;

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  testWidgets('signing out closes the menu and nothing else', (tester) async {
    // Regression test. The button used to sign out first and pop afterwards.
    // By then the redirect had already taken the dialog down, so the pop
    // removed the page underneath instead and left an empty navigator — a
    // black window with a title bar and nothing in it.
    final auth = _FakeAuth();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showHkProfileMenu(context),
                  child: const Text('ochish'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ochish'));
    await tester.pumpAndSettle();
    expect(find.text('Chiqish'), findsOneWidget);

    await tester.tap(find.text('Chiqish'));
    await tester.pumpAndSettle();

    expect(auth.signOuts, 1);
    expect(find.text('Chiqish'), findsNothing, reason: 'the menu closed');
    expect(
      find.text('ochish'),
      findsOneWidget,
      reason: 'the page underneath survived — exactly one pop happened',
    );
  });
}
