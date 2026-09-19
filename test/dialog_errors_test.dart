import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hanguk_online/core/errors.dart';
import 'package:hanguk_online/design_system/widgets/glass.dart';
import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/staff/data/staff_providers.dart';
import 'package:hanguk_online/features/staff/presentation/assignment_dialog.dart';
import 'package:hanguk_online/main.dart';

/// A teacher pressed "Vazifani berish" and the app answered
/// "Null check operator used on a null value".
///
/// Two defects in one line. The picker becomes a sentence rather than a
/// dropdown when the teacher has no lessons, so there is no field for the
/// form to refuse — `validate()` passed and `_lessonId!` threw. And what it
/// threw was printed verbatim, in English, to somebody whose actual problem
/// was that nobody had put a lesson on their timetable.
void main() {
  setUpAll(() async {
    initializeDateFormatting('uz');
    await _loadBundledFonts();
  });

  testWidgets('with no lesson to attach it to, the button does not offer',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          // What the teacher in the report had: an account, a group, and
          // nothing on the timetable.
          assignableLessonsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: hangukTheme,
          locale: hkLocale,
          supportedLocales: hkSupportedLocales,
          localizationsDelegates: hkLocalizationsDelegates,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAssignmentDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Sizga biriktirilgan dars yo‘q'), findsOneWidget);

    // The save button is there but does nothing: pressing it could only ever
    // produce an error, and before this it produced a crash.
    final button = tester.widget<LimeButton>(find.byType(LimeButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Vazifani berish'), warnIfMissed: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('what the person is told when a write fails', () {
    test('a duplicate name is a duplicate name, not a Postgres string', () {
      final message = hkErrorMessage(
        const PostgrestException(
          message:
              'duplicate key value violates unique constraint "ol_groups_name_key"',
          code: '23505',
        ),
      );
      expect(message, contains('nom allaqachon band'));
      expect(message, isNot(contains('constraint')));
    });

    test('a refused policy names the person who can lift it', () {
      final message = hkErrorMessage(
        const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        ),
      );
      expect(message, contains('ruxsat yo‘q'));
      expect(message, contains('Administrator'));
    });

    test("the repositories' own Uzbek comes through untouched", () {
      // Demo mode, a missing bucket policy, not being signed in — all of
      // them already say something useful, and must not be re-wrapped.
      expect(
        hkErrorMessage(StateError('Demo rejimda fayl yuklab bo‘lmaydi')),
        'Demo rejimda fayl yuklab bo‘lmaydi',
      );
    });

    test('our own null is admitted as ours', () {
      Object? thrown;
      try {
        // ignore: null_check_on_nullable_type_parameter
        String? nothing;
        nothing!.length;
      } catch (e) {
        thrown = e;
      }
      expect(hkErrorMessage(thrown!), contains('ichki xatolik'));
      expect(hkErrorMessage(thrown), isNot(contains('Null check')));
    });
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
