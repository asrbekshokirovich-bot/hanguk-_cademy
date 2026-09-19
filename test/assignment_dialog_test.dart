import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/staff/presentation/assignment_dialog.dart';
import 'package:hanguk_online/main.dart';

/// The deadline picker turned the window white.
///
/// `showDatePicker` needs `MaterialLocalizations` for the locale it is given,
/// and the app had never declared any: no `flutter_localizations`, no
/// `supportedLocales`, no delegates. Asking for `uz` therefore threw while
/// building, and a thrown build is a blank window with nothing written on it.
///
/// This opens the real picker through the real app shell. It is the cheapest
/// possible test and it would have caught the defect outright.
void main() {
  setUpAll(() => initializeDateFormatting('uz'));

  testWidgets('the deadline picker opens instead of blanking the window',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: hangukTheme,
          // The same declarations main.dart makes. Drop any of them and this
          // test goes red, which is the point of writing it out here.
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
    expect(find.text('Yangi vazifa'), findsOneWidget);

    await tester.tap(find.text('Muddat qo‘yish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // A Material date picker, built with Uzbek localisations behind it. Before
    // the fix this threw and nothing below rendered at all.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
