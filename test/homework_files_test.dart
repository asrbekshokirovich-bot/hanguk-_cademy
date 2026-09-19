import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hanguk_online/features/lessons/data/lessons_repository.dart';
import 'package:hanguk_online/features/lessons/domain/models.dart';
import 'package:hanguk_online/features/lessons/presentation/dashboard_screen.dart';
import 'package:hanguk_online/features/lessons/presentation/submit_assignment_dialog.dart';
import 'package:hanguk_online/features/staff/data/staff_repository.dart';
import 'package:hanguk_online/features/staff/presentation/assignment_dialog.dart';
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

  /// The dashboard needs a router above it — the shell navigates — so it is
  /// pumped through one rather than as a bare `home:`.
  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: MaterialApp.router(
          theme: hangukTheme,
          locale: hkLocale,
          supportedLocales: hkSupportedLocales,
          localizationsDelegates: hkLocalizationsDelegates,
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
            ],
          ),
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

  group('the handout the teacher gives out', () {
    // `ol_materials` has been in the schema since the first migration and
    // the recording screen has always listed it — but nothing ever inserted
    // a row, and the only screen that read one hangs off a recording, of
    // which there are none. So a worksheet was unreachable in both
    // directions at once.
    testWidgets('the set-homework dialog offers one', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAssignmentDialog(context),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Yangi vazifa'), findsOneWidget);
      expect(find.text('Material biriktirilmagan'), findsOneWidget);
      expect(find.text('Material biriktirish'), findsOneWidget);
    });

    testWidgets('the student sees it on the homework it belongs to',
        (tester) async {
      await pumpDashboard(tester);

      // Against the lesson the fixtures attach it to, and only that one: a
      // worksheet belongs to a lesson, and claiming the same file for every
      // piece of homework is how the demo used to read.
      expect(find.text('Dars taqdimoti.pdf'), findsOneWidget);
      expect(find.text("Yangi so'zlar lug'ati"), findsOneWidget);
    });

    test('demo mode refuses both halves, in Uzbek', () async {
      await expectLater(
        () => LessonsRepository(null).uploadMaterialFile(
          lessonId: 'd2',
          filename: 'taqdimot.pdf',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        ),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('Demo rejimda')),
        ),
      );
      await expectLater(
        () => StaffRepository(null).addMaterial(
          lessonId: 'd2',
          name: 'taqdimot.pdf',
          url: 'materials/d2/taqdimot.pdf',
        ),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('Demo rejimda')),
        ),
      );
    });

    test('an ordinary link is left alone, an object path is signed',
        () async {
      final repository = LessonsRepository(null);

      // The column holds both kinds. A link goes straight through; a path
      // has no address until it is signed, and in demo mode the signing is
      // what refuses — which is the proof it was treated as a path.
      expect(
        await repository.materialLink('https://example.uz/worksheet.pdf'),
        'https://example.uz/worksheet.pdf',
      );
      await expectLater(
        () => repository.materialLink('materials/d2/worksheet.pdf'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('a storage refusal is explained to the person who can fix it', () {
    // The likeliest failure here is neither the student's doing nor a bug in
    // this code: a bucket made in the dashboard arrives with no policies at
    // all, `storage.objects` has RLS on, and the refusal comes back in
    // untranslated Postgres. Raw, it reads as "the app is broken" to the one
    // person who cannot do anything about it.
    test('a missing policy names the file that adds it', () {
      final message = LessonsRepository.storageMessage(
        const StorageException(
          'new row violates row-level security policy',
          statusCode: '400',
        ),
      );
      expect(message, contains('ruxsatlar sozlanmagan'));
      expect(message, contains('20260919120000_storage_uploads.sql'));
    });

    test('a missing bucket says which one', () {
      final message = LessonsRepository.storageMessage(
        const StorageException('Bucket not found', statusCode: '404'),
      );
      expect(message, contains('uploads'));
      expect(message, contains('topilmadi'));
    });

    test('anything else is passed through rather than swallowed', () {
      final message = LessonsRepository.storageMessage(
        const StorageException('connection closed', statusCode: '500'),
      );
      expect(message, contains('connection closed'));
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
