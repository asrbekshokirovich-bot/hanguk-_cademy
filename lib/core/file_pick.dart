import 'package:file_picker/file_picker.dart';

/// What the `uploads` bucket will take.
///
/// Checked before an upload starts as well as by the bucket, because the
/// bucket only refuses after the whole file has gone up the wire — which on a
/// phone in Qarshi is several minutes of waiting for a refusal that was
/// knowable before the first byte left.
const hkMaxUploadBytes = 50 * 1024 * 1024;

/// A chosen file, with its size resolved.
///
/// The two arrive from different places. `file_picker` 13 hands back a handle
/// and not the bytes — which suits an upload, since a 40 MB video should be
/// read when the work is sent and not when it is chosen — but that means the
/// size has to be asked for, and may still come back null if the platform
/// does not know it and the read fails.
class HkPickedFile {
  const HkPickedFile(this.file, this.sizeBytes);

  final PlatformFile file;
  final int? sizeBytes;

  String get name => file.name;

  bool get isTooLarge =>
      sizeBytes != null && sizeBytes! > hkMaxUploadBytes;
}

/// Opens the platform's file picker, or returns null if it was cancelled.
///
/// One place for this because two screens need the same three steps in the
/// same order — pick, then size, then a limit matching the bucket's — and a
/// copy of them is a copy that will be half-fixed later.
Future<HkPickedFile?> hkPickFile() async {
  final picked = await FilePicker.pickFile();
  if (picked == null) return null;
  // `lengthSync` is what the native picker already reported; `length()` falls
  // back to reading the file to find out.
  return HkPickedFile(picked, picked.lengthSync() ?? await picked.length());
}

/// Human-readable size, or null when nothing could be determined.
String? hkFileSizeLabel(int? bytes) {
  if (bytes == null) return null;
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}
