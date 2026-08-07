import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hanguk_online/features/auth/data/auth_repository.dart';
import 'package:hanguk_online/features/auth/data/username.dart';
import 'package:hanguk_online/features/auth/presentation/login_screen.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/main.dart';

void main() {
  group('username → auth email', () {
    test('a handle becomes an address on the internal domain', () {
      expect(
        HkAuthNaming.toAuthEmail('aziza.k'),
        'aziza.k@users.hanguk-academy.uz',
      );
    });

    test('case and surrounding space are forgiven', () {
      // A login copied off a slip of paper arrives like this, and refusing it
      // would be indistinguishable from a wrong password.
      expect(
        HkAuthNaming.toAuthEmail('  Aziza.K  '),
        'aziza.k@users.hanguk-academy.uz',
      );
    });

    test('a real address is passed through untouched', () {
      // The first admin account is created by hand with a genuine address.
      expect(
        HkAuthNaming.toAuthEmail('asrbek@hanguk.uz'),
        'asrbek@hanguk.uz',
      );
    });

    test('display strips the synthetic domain but keeps a real one', () {
      expect(
        HkAuthNaming.toDisplayName('aziza.k@users.hanguk-academy.uz'),
        'aziza.k',
      );
      expect(
        HkAuthNaming.toDisplayName('asrbek@hanguk.uz'),
        'asrbek@hanguk.uz',
      );
    });

    test('round trip is stable', () {
      const handle = 'bekzod-t';
      expect(
        HkAuthNaming.toDisplayName(HkAuthNaming.toAuthEmail(handle)),
        handle,
      );
    });
  });

  group('username validation', () {
    test('accepts the shapes an admin will issue', () {
      for (final ok in ['aziza.k', 'bekzod-t', 'user_1', 'abc', 'a1b']) {
        expect(HkAuthNaming.validationError(ok), isNull, reason: ok);
      }
    });

    test('rejects what the database constraint would reject', () {
      expect(HkAuthNaming.validationError(''), 'Login kiriting');
      expect(
        HkAuthNaming.validationError('ab'),
        "Login kamida 3 ta belgidan iborat bo'lsin",
      );
      expect(
        HkAuthNaming.validationError('a' * 40),
        'Login 32 ta belgidan oshmasin',
      );
      expect(
        HkAuthNaming.validationError('aziza@mail.uz'),
        "Loginda @ belgisi bo'lmasin",
      );
      // Punctuation at either end, and spaces, are out.
      expect(HkAuthNaming.validationError('.aziza'), isNotNull);
      expect(HkAuthNaming.validationError('aziza.'), isNotNull);
      expect(HkAuthNaming.validationError('aziza k'), isNotNull);
    });

    test('uppercase input is normalised, not rejected', () {
      expect(HkAuthNaming.validationError('AZIZA.K'), isNull);
      expect(HkAuthNaming.isValid('Aziza.K'), isTrue);
    });
  });

  group('login screen', () {
    Future<void> pumpLogin(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [supabaseClientProvider.overrideWithValue(null)],
          child: MaterialApp(theme: hangukTheme, home: const LoginScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('empty submit reports both fields', (tester) async {
      await pumpLogin(tester);

      await tester.tap(find.text('Kirish'));
      await tester.pump();

      expect(find.text('Login kiriting'), findsOneWidget);
      expect(find.text('Parol kiriting'), findsOneWidget);
    });

    testWidgets('there is no way to self-register', (tester) async {
      await pumpLogin(tester);

      // Accounts are issued by an admin. A sign-up affordance here would be a
      // dead end, so the screen explains instead.
      expect(find.textContaining("Ro'yxatdan o'tish"), findsNothing);
      expect(
        find.textContaining('administrator beradi', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('typing uppercase lands lowercase in the field',
        (tester) async {
      await pumpLogin(tester);

      await tester.enterText(find.byType(TextFormField).first, 'AZIZA.K');
      await tester.pump();

      expect(find.text('aziza.k'), findsOneWidget);
    });
  });

  group('error text', () {
    test('known Supabase errors are translated', () {
      expect(
        hkAuthErrorText(const AuthException('Invalid login credentials')),
        "Login yoki parol noto'g'ri.",
      );
      expect(
        hkAuthErrorText(const AuthException('Password should be at least 8')),
        "Parol kamida 8 ta belgidan iborat bo'lsin.",
      );
    });

    test('an unknown error keeps its original text', () {
      // Swallowing these behind a generic "xatolik" would hide real
      // configuration problems — a disabled provider, an SMTP failure.
      expect(
        hkAuthErrorText(const AuthException('Something entirely new')),
        'Something entirely new',
      );
    });
  });

  group('demo mode', () {
    test('counts as signed in, and every write is a no-op', () async {
      final auth = AuthRepository(null);
      expect(auth.isDemo, isTrue);
      expect(auth.isSignedIn, isTrue);
      expect(auth.currentSession, isNull);
      await auth.signOut();
      await auth.signIn(username: 'aziza.k', password: 'x');
      await auth.changeOwnPassword('whatever');
    });
  });
}
