import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../../lessons/data/lessons_repository.dart';

/// What the teacher entered.
class GradeResult {
  const GradeResult({required this.grade, this.feedback});

  final int grade;
  final String? feedback;
}

/// Collects a mark out of 100 and an optional comment.
Future<GradeResult?> showGradeDialog(
  BuildContext context, {
  required String studentName,
  required String assignmentTitle,
  String? answer,
  String? fileUrl,
  int? initialGrade,
}) {
  return showDialog<GradeResult>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _GradeDialog(
      studentName: studentName,
      assignmentTitle: assignmentTitle,
      answer: answer,
      fileUrl: fileUrl,
      initialGrade: initialGrade,
    ),
  );
}

class _GradeDialog extends StatefulWidget {
  const _GradeDialog({
    required this.studentName,
    required this.assignmentTitle,
    this.answer,
    this.fileUrl,
    this.initialGrade,
  });

  final String studentName;
  final String assignmentTitle;

  /// What the student actually handed in.
  ///
  /// It was not shown anywhere. `ol_assignment_submissions.note` is written
  /// by the student, carried all the way through `ol_v_submissions` and into
  /// `Submission.note` — and then no screen read it, so a teacher opened this
  /// dialog, saw a name and a title, and was asked for a mark out of 100 on
  /// work they had no way of reading.
  final String? answer;

  /// The object path of the file the student attached, or null.
  ///
  /// A path inside the private `uploads` bucket rather than a URL, despite
  /// the column's name: a private bucket has no permanent address, so the
  /// link has to be signed at the moment it is opened.
  final String? fileUrl;

  final int? initialGrade;

  @override
  State<_GradeDialog> createState() => _GradeDialogState();
}

class _GradeDialogState extends State<_GradeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _grade =
      TextEditingController(text: widget.initialGrade?.toString() ?? '');
  final _feedback = TextEditingController();

  @override
  void dispose() {
    _grade.dispose();
    _feedback.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      GradeResult(
        grade: int.parse(_grade.text),
        feedback: _feedback.text.trim().isEmpty ? null : _feedback.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
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
                      child: Text('Baholash', style: HkType.pageTitle),
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
                Text(widget.studentName, style: HkType.cardTitle),
                const SizedBox(height: 2),
                Text(widget.assignmentTitle, style: HkType.muted),
                const SizedBox(height: 16),
                _Answer(text: widget.answer),
                const SizedBox(height: 12),
                _Attachment(path: widget.fileUrl),
                const SizedBox(height: 16),
                AuthField(
                  controller: _grade,
                  label: 'Baho (0–100)',
                  icon: Icons.grade_outlined,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  validator: (v) {
                    final value = int.tryParse((v ?? '').trim());
                    if (value == null) return 'Baho kiriting';
                    if (value < 0 || value > 100) return '0 dan 100 gacha';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _feedback,
                  label: 'Izoh (ixtiyoriy)',
                  icon: Icons.chat_bubble_outline_rounded,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 22),
                LimeButton(label: 'Saqlash', expand: true, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The handed-in work, above the box the mark goes in.
///
/// Scrollable and capped rather than clipped: a long answer is still the
/// thing being marked, and a dialog that grows past the window is worse than
/// one you scroll inside.
class _Answer extends StatelessWidget {
  const _Answer({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final body = (text ?? '').trim();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        border: Border.all(color: HkGlass.border),
      ),
      child: body.isEmpty
          ? Text(
              'Talaba matn yozmagan.',
              style: HkType.muted.copyWith(fontSize: 12.5),
            )
          : SingleChildScrollView(
              child: Text(
                body,
                style: HkType.body.copyWith(fontSize: 13),
              ),
            ),
    );
  }
}

/// The file the student attached, if they attached one.
///
/// A link and not a preview. The bucket is private, so there is no address
/// to hold on to — every open costs a freshly signed URL, valid for ten
/// minutes — and what arrives may as easily be a 40 MB voice memo as a
/// photograph of an exercise book. Handing it to the browser or to the
/// desktop is what the teacher would do with it anyway.
///
/// Its own Consumer rather than lifting the dialog onto Riverpod: nothing
/// else here reads a provider, and a dialog that needs a container to be
/// shown is a dialog that is awkward to test.
class _Attachment extends ConsumerStatefulWidget {
  const _Attachment({required this.path});

  final String? path;

  @override
  ConsumerState<_Attachment> createState() => _AttachmentState();
}

class _AttachmentState extends ConsumerState<_Attachment> {
  bool _opening = false;
  String? _error;

  Future<void> _open() async {
    final path = widget.path;
    if (path == null) return;

    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final url =
          await ref.read(lessonsRepositoryProvider).signedUploadUrl(path);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      setState(() {
        _opening = false;
        // A false here is the platform declining to handle the link, not an
        // error thrown — silently doing nothing would look like a dead
        // button, which is the one thing this screen has enough of already.
        _error = opened ? null : 'Faylni ochib bo‘lmadi.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = hkErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    if (path == null) {
      return Row(
        children: [
          const Icon(
            Icons.attach_file_rounded,
            size: 16,
            color: HkColors.textTertiary,
          ),
          const SizedBox(width: 8),
          Text('Fayl biriktirilmagan', style: HkType.muted),
        ],
      );
    }

    // The last path segment is the stored filename, which the uploader
    // already reduced to something an object key can hold.
    final name = Uri.decodeComponent(path.split('/').last);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.insert_drive_file_outlined,
              size: 16,
              color: HkColors.lime,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HkType.body.copyWith(fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: _opening ? null : _open,
              child: Text(
                _opening ? 'Ochilmoqda…' : 'Ochish',
                style: const TextStyle(
                  fontFamily: HkType.family,
                  fontSize: 12.5,
                  color: HkColors.lime,
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: HkType.body.copyWith(
              fontSize: 12,
              color: HkColors.dangerBright,
            ),
          ),
        ],
      ],
    );
  }
}
