import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/lessons/presentation/submit_assignment_dialog.dart';
import 'package:hanguk_online/features/staff/presentation/grade_dialog.dart';
import 'package:hanguk_online/main.dart';

/// Homework you can only type.
///
/// Half of what this school sets is a photograph of an exercise book or a
/// recording of somebody reading aloud, and there was nowhere to put either:
/// `ol_assignment_submissions.file_url` has been in the schema since the
/// first migration, `ol_v_submissions` has always selected it, and no screen
/// ever wrote or read it. So a student could hand in a sentence about the
/// photograph they could not send, and a teacher marked the sentence.
///
/// These cover the round trip that closes it: the student attaches, the
/// teacher opens, and both of them can see the filename in between — the
/// last part matters most, because an upload with no acknowledgement is a
/// student sending the same photograph three times to be sure.
void main() {
  setUpAll(() => initializeDateFormatting('uz'));

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: hangukTheme,
          locale: hkLocale,
          supportedLocales: hkSupportedLocales,
          localizationsDelegates: hkLocalizationsDelegates,
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the student', () {
    testWidgets('is offered an attachment, and told none is attached yet',
        (tester) async {
      const assignment = Assignment(
        id: 'a1',
        title: 'Ovozli mashq',
        submitted: false,
        body: 'Matnni ovoz chiqarib o‘qing va yozib yuboring.',
      );

      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSubmitAssignmentDialog(context, assignment),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Vazifani topshirish'), findsOneWidget);
      expect(find.text('Fayl biriktirilmagan'), findsOneWidget);
      expect(find.text('Fayl biriktirish'), findsOneWidget);
      // The written answer stays compulsory: the file is the extra, so there
      // is always something for the teacher to read even when the attachment
      // fails to open on their machine.
      expect(find.text('Javobingiz'), findsOneWidget);
    });
  });

  group('the teacher', () {
    Future<void> pumpGrade(WidgetTester tester, {String? fileUrl}) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGradeDialog(
              context,
              studentName: 'Sardor Mirzayev',
              assignmentTitle: 'Ovozli xabar',
              answer: 'Yozib yubordim.',
              fileUrl: fileUrl,
            ),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('can open what the student attached', (tester) async {
      await pumpGrade(
        tester,
        fileUrl: 'submissions/sub-3/ts-sm/talaffuz%20mashqi.m4a',
      );

      // The stored name, decoded. A teacher marking thirty recordings needs
      // to know which one they are about to play.
      expect(find.text('talaffuz mashqi.m4a'), findsOneWidget);
      expect(find.text('Ochish'), findsOneWidget);
    });

    testWidgets('is told plainly when there is no file', (tester) async {
      await pumpGrade(tester);

      // Not a disabled button and not an empty row: "no attachment" is a
      // fact about the hand-in, and the teacher is about to give it a mark.
      expect(find.text('Fayl biriktirilmagan'), findsOneWidget);
      expect(find.text('Ochish'), findsNothing);
    });
  });

  group('demo mode refuses the storage calls, in Uzbek', () {
    // The same contract as every other write: a demo build has no session to
    // upload as, so it says so rather than throwing a null client at the wall.
    test('nothing is uploaded', () async {
      final repository = LessonsRepository(null);
      await expectLater(
        () => repository.uploadSubmissionFile(
          assignmentId: 'a1',
          filename: 'javob.pdf',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        ),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('Demo rejimda')),
        ),
      );
    });

    test('nothing is signed', () async {
      final repository = LessonsRepository(null);
      await expectLater(
        () => repository.signedUploadUrl('submissions/a1/s1/javob.pdf'),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('Demo rejimda')),
        ),
      );
    });
  });

  group('the model', () {
    test('the shown name is the stored path, decoded and stripped', () {
      const withFile = Assignment(
        id: 'a1',
        title: 'T',
        submitted: true,
        fileUrl: 'submissions/a1/u1/uy%20vazifasi.pdf',
      );
      expect(withFile.fileName, 'uy vazifasi.pdf');

      const withoutFile = Assignment(id: 'a1', title: 'T', submitted: true);
      expect(withoutFile.fileName, isNull);

      // An empty string is what a column default or a half-written row hands
      // back, and it must not render as a nameless paperclip.
      const empty = Assignment(
        id: 'a1',
        title: 'T',
        submitted: true,
        fileUrl: '',
      );
      expect(empty.fileName, isNull);
    });

    test('a hand-in carries its file through fromMap', () {
      final a = Assignment.fromMap({
        'id': 'a1',
        'title': 'Ovozli mashq',
        'submitted': true,
        'file_url': 'submissions/a1/u1/talaffuz.m4a',
      });
      expect(a.fileUrl, 'submissions/a1/u1/talaffuz.m4a');
      expect(a.fileName, 'talaffuz.m4a');
    });
  });
}
