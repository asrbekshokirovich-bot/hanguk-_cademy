import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../data/lessons_repository.dart';
import '../domain/models.dart';

/// What the `uploads` bucket will take, checked here as well as there.
///
/// The bucket rejects anything larger, but it does so after the whole file
/// has gone up the wire — which on a phone in Qarshi is several minutes of
/// waiting for a refusal that was knowable before the first byte left.
const _maxUploadBytes = 50 * 1024 * 1024;

/// Hands in one piece of homework: a written answer, a file, or both.
///
/// Both, because they are not alternatives — a photographed exercise usually
/// wants a sentence with it, and a sentence on its own is perfectly good
/// homework. The file is optional and the text is not, so there is always
/// something for the teacher to open.
///
/// Returns true when something was handed in.
Future<bool?> showSubmitAssignmentDialog(
  BuildContext context,
  Assignment assignment,
) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _SubmitDialog(assignment: assignment),
  );
}

class _SubmitDialog extends ConsumerStatefulWidget {
  const _SubmitDialog({required this.assignment});

  final Assignment assignment;

  @override
  ConsumerState<_SubmitDialog> createState() => _SubmitDialogState();
}

class _SubmitDialogState extends ConsumerState<_SubmitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  /// Held as a handle until the work is handed in. Picking a file and then
  /// closing the dialog must not leave an orphan in the bucket.
  PlatformFile? _file;

  /// Kept beside the file because the size is worth showing before sending
  /// and finding it can cost a disk read (see [_pick]).
  int? _size;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null || !mounted) return;

      // The picker hands back a handle, not the bytes: reading a 40 MB photo
      // into memory is the hand-in's job, not the picker's. The size usually
      // comes back with the pick; `length()` falls back to a read when the
      // platform did not report one, and returns null if even that failed.
      final size = picked.lengthSync() ?? await picked.length();
      if (!mounted) return;

      if (size != null && size > _maxUploadBytes) {
        setState(() {
          _file = null;
          _size = null;
          _error = 'Fayl juda katta (${_FileRow.size(size)}). '
              'Eng ko‘pi 50 MB.';
        });
        return;
      }

      setState(() {
        _file = picked;
        _size = size;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Faylni tanlab bo‘lmadi: $e');
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repository = ref.read(lessonsRepositoryProvider);

      // Uploaded first, so a failure here stops the whole hand-in rather than
      // recording an answer that claims a file it does not have.
      String? path;
      final file = _file;
      if (file != null) {
        path = await repository.uploadSubmissionFile(
          assignmentId: widget.assignment.id,
          filename: file.name,
          bytes: await file.readAsBytes(),
        );
      }

      await repository.submitAssignment(
        widget.assignment.id,
        _note.text,
        fileUrl: path,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(24),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Vazifani topshirish',
                          style: HkType.pageTitle),
                    ),
                    IconButton(
                      tooltip: 'Yopish',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: HkColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(a.title, style: HkType.cardTitle),
                if (a.body != null) ...[
                  const SizedBox(height: 6),
                  Text(a.body!, style: HkType.body.copyWith(fontSize: 12.5)),
                ],
                const SizedBox(height: 20),
                AuthField(
                  controller: _note,
                  label: 'Javobingiz',
                  icon: Icons.edit_note_rounded,
                  textInputAction: TextInputAction.newline,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Javob yozing' : null,
                ),
                const SizedBox(height: 12),
                _FileRow(
                  name: _file?.name,
                  bytes: _size,
                  onPick: _sending ? null : _pick,
                  onClear: _sending
                      ? null
                      : () => setState(() {
                            _file = null;
                            _size = null;
                          }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: HkType.body.copyWith(
                      fontSize: 12.5,
                      color: HkColors.dangerBright,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                LimeButton(
                  label: _sending ? 'Yuborilmoqda…' : 'Topshirish',
                  expand: true,
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The optional attachment.
///
/// Named and sized once chosen, because "fayl tanlandi" tells a student
/// nothing about whether they picked the right one — and a 50 MB limit is
/// only useful if the number is on screen before they press send.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.bytes,
    required this.onPick,
    required this.onClear,
  });

  final String? name;
  final int? bytes;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  /// Also used by the over-size message, which is why it is not private.
  static String size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final picked = name;
    final length = bytes;

    return Row(
      children: [
        Icon(
          picked == null
              ? Icons.attach_file_rounded
              : Icons.insert_drive_file_outlined,
          size: 18,
          color: picked == null ? HkColors.textSecondary : HkColors.lime,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            picked == null
                ? 'Fayl biriktirilmagan'
                : length == null
                    ? picked
                    : '$picked · ${size(length)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HkType.body.copyWith(fontSize: 12.5),
          ),
        ),
        if (picked != null)
          TextButton(
            onPressed: onClear,
            child: const Text(
              'Olib tashlash',
              style: TextStyle(
                fontFamily: HkType.family,
                fontSize: 12.5,
                color: HkColors.textTertiary,
              ),
            ),
          ),
        TextButton(
          onPressed: onPick,
          child: Text(
            picked == null ? 'Fayl biriktirish' : 'Almashtirish',
            style: const TextStyle(
              fontFamily: HkType.family,
              fontSize: 12.5,
              color: HkColors.lime,
            ),
          ),
        ),
      ],
    );
  }
}
