import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors.dart';
import '../data/lessons_repository.dart';
import '../domain/models.dart';

/// Opens whatever `ol_materials.url` holds, and says what went wrong.
///
/// The column predates the storage bucket and holds two kinds of thing: a
/// row written by hand holds an ordinary link, a row written by the
/// set-homework dialog holds an object path inside a private bucket, which
/// has no address until it is signed. Telling them apart is
/// [LessonsRepository.materialLink]'s job; this adds the part every caller
/// would otherwise repeat — launching it, and turning "the platform declined
/// to handle this" into something the person can read.
///
/// Returns null when the file opened, and a message in Uzbek when it did not.
Future<String?> openLessonMaterial(WidgetRef ref, String url) async {
  if (url.isEmpty) return 'Bu materialga fayl biriktirilmagan.';
  try {
    final link = await ref.read(lessonsRepositoryProvider).materialLink(url);
    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    // A false here is the platform declining the link rather than an error
    // thrown, and doing nothing quietly is how a button comes to look dead.
    return opened ? null : 'Faylni ochib bo‘lmadi.';
  } catch (e) {
    return hkErrorMessage(e);
  }
}

/// Opens a recorded lesson, and says what went wrong.
///
/// A recording is kept one of two ways — a file the teacher uploaded, or one
/// the server recorded into the bucket — and only the database can sign the
/// second. Both end up here, and both end up in whatever this machine plays
/// video with: the app has no decoder of its own, and a door that opens is
/// worth more than a player that does not exist.
Future<String?> openRecording(WidgetRef ref, Recording recording) async {
  try {
    final link =
        await ref.read(lessonsRepositoryProvider).recordingLink(recording);
    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    return opened ? null : 'Yozuvni ochib bo‘lmadi.';
  } catch (e) {
    return hkErrorMessage(e);
  }
}
