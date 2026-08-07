import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/core/clock.dart';
import 'package:hanguk_online/features/admin/presentation/password_result_dialog.dart';
import 'package:hanguk_online/features/admin/presentation/users_screen.dart';
import 'package:hanguk_online/features/auth/presentation/change_password_screen.dart';
import 'package:hanguk_online/features/auth/presentation/login_screen.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/main.dart';

final _fixedNow = DateTime(2026, 6, 26, 12, 58, 30);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('uz');
    await _loadBundledFonts();
    hkNow = () => _fixedNow;
  });

  tearDownAll(() => hkNow = DateTime.now);

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: MaterialApp.router(
          theme: hangukTheme,
          debugShowCheckedModeBanner: false,
          routerConfig: GoRouter(
            routes: [GoRoute(path: '/', builder: (_, _) => screen)],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('login screen', (tester) async {
    await pump(tester, const LoginScreen());
    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login.png'),
    );
  });

  testWidgets('forced password change', (tester) async {
    await pump(tester, const ChangePasswordScreen());
    await expectLater(
      find.byType(ChangePasswordScreen),
      matchesGoldenFile('goldens/change_password.png'),
    );
  });

  testWidgets('account roster', (tester) async {
    await pump(tester, const UsersScreen());

    expect(find.text('Aziza Karimova'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    // The account created two days ago has never signed in.
    expect(find.text('Hech qachon'), findsOneWidget);

    await expectLater(
      find.byType(UsersScreen),
      matchesGoldenFile('goldens/admin_users.png'),
    );
  });

  testWidgets('create dialog suggests a login from the name', (tester) async {
    await pump(tester, const UsersScreen());

    await tester.tap(find.text('Yangi hisob'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(
      find.byType(TextFormField).first,
      'Dilnoza Sattorova',
    );
    // Past the floating-label animation. A single pump captures the label
    // mid-flight, sitting on top of the value it is supposed to have moved
    // out of the way of.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Filling in a hundred students by hand is the daily job; the handle is
    // the field people hesitate over, so it is proposed.
    expect(find.text('dilnoza.s'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/admin_create.png'),
    );
  });

  testWidgets('the issued password is shown once and cannot be dismissed by '
      'tapping away', (tester) async {
    await pump(tester, const UsersScreen());

    showPasswordResultDialog(
      tester.element(find.byType(UsersScreen)),
      title: 'Hisob yaratildi',
      username: 'dilnoza.s',
      fullName: 'Dilnoza Sattorova',
      password: 'Kp7mRt4xQw2h',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Kp7mRt4xQw2h'), findsOneWidget);
    expect(find.textContaining('boshqa ko‘rsatilmaydi'), findsOneWidget);

    // Tapping the barrier must not close it: this is the only time the
    // password is readable.
    await tester.tapAt(const Offset(60, 60));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Kp7mRt4xQw2h'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/admin_password.png'),
    );
  });

  testWidgets('creating is refused in demo mode', (tester) async {
    await pump(tester, const UsersScreen());

    await tester.tap(find.text('Yangi hisob'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextFormField).first, 'Test User');
    await tester.pump();
    await tester.tap(find.text('Yaratish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // There is no backend to create anything in; say so rather than hang.
    expect(
      find.textContaining('Demo rejimda hisob yaratib bo‘lmaydi'),
      findsOneWidget,
    );
  });
}

Future<void> _loadBundledFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(
        File(path).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await loader.load();
  }

  await load('Inter', [
    for (final w in [400, 500, 600, 700, 800, 900])
      'assets/fonts/Inter-$w.ttf',
  ]);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-600.ttf']);
  await load('NotoSansKR', [
    'assets/fonts/NotoSansKR-500.ttf',
    'assets/fonts/NotoSansKR-700.ttf',
  ]);
}
