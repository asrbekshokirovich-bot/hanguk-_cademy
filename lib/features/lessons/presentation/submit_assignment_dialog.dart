import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../data/lessons_repository.dart';
import '../domain/models.dart';

/// Hands in one piece of homework.
///
/// Text only. `ol_assignment_submissions.file_url` has been in the schema
/// from the start and there is still no storage bucket behind it, so an
/// upload button here would be the same promise the play button used to make.
/// A written answer is worth having on its own, and it is what makes the
/// teacher's grading queue stop being empty.
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

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(lessonsRepositoryProvider)
          .submitAssignment(widget.assignment.id, _note.text);
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
                const SizedBox(height: 8),
                Text(
                  'Fayl biriktirish hali mavjud emas — javobni matn '
                  'ko‘rinishida yozing.',
                  style: HkType.muted.copyWith(fontSize: 11.5),
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
