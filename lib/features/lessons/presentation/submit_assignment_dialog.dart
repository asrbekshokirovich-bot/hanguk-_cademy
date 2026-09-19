import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/file_pick.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/file_row.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../data/lessons_repository.dart';
import '../domain/models.dart';

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
  HkPickedFile? _file;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await hkPickFile();
      if (picked == null || !mounted) return;

      if (picked.isTooLarge) {
        setState(() {
          _file = null;
          _error = 'Fayl juda katta '
              '(${hkFileSizeLabel(picked.sizeBytes)}). Eng ko‘pi 50 MB.';
        });
        return;
      }

      setState(() {
        _file = picked;
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
          bytes: await file.file.readAsBytes(),
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
                HkFileRow(
                  name: _file?.name,
                  sizeBytes: _file?.sizeBytes,
                  onPick: _sending ? null : _pick,
                  onClear:
                      _sending ? null : () => setState(() => _file = null),
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
