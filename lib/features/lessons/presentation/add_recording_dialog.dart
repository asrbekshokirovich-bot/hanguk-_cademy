import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors.dart';
import '../../../core/file_pick.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/dropdown_field.dart';
import '../../../design_system/widgets/file_row.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../../staff/data/staff_providers.dart';
import '../data/lessons_repository.dart';
import '../domain/models.dart';

/// "Yozuv qo'shish" — puts a recorded lesson in the library.
///
/// `ol_recordings` has been in the schema since the first migration, the
/// library reads it, the dashboard counts it, and nothing has ever written a
/// row — so "Yozuvlar" was empty in every build and every screen that hangs
/// off it (a student's progress, the teacher's "O'zlashtirish") was
/// permanently zero.
///
/// The recording itself is the teacher's own capture. Recording the room on
/// the server is a different piece of work — LiveKit egress, storage
/// credentials, and a database that can make an outbound request — and until
/// that exists this is how a lesson is kept rather than lost.
Future<bool?> showAddRecordingDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => const _AddRecordingDialog(),
  );
}

class _AddRecordingDialog extends ConsumerStatefulWidget {
  const _AddRecordingDialog();

  @override
  ConsumerState<_AddRecordingDialog> createState() =>
      _AddRecordingDialogState();
}

class _AddRecordingDialogState extends ConsumerState<_AddRecordingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();

  String? _lessonId;
  HkPickedFile? _file;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await hkPickFile();
      if (picked == null || !mounted) return;
      if (picked.isTooLarge) {
        setState(() {
          _file = null;
          _error = 'Fayl juda katta (${hkFileSizeLabel(picked.sizeBytes)}). '
              'Eng ko‘pi 50 MB — uzun darsni siqib yoki bo‘lib yuklang.';
        });
        return;
      }
      setState(() {
        _file = picked;
        _error = null;
        if (_title.text.trim().isEmpty) _title.text = picked.name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Faylni tanlab bo‘lmadi: ${hkErrorMessage(e)}');
    }
  }

  Future<void> _save(List<Lesson> lessons) async {
    if (!_formKey.currentState!.validate()) return;
    final file = _file;
    final lessonId = _lessonId;
    if (file == null || lessonId == null) {
      setState(() => _error = 'Darsni tanlang va yozuv faylini biriktiring.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(lessonsRepositoryProvider);
      // The same folder the handouts go to, because that is the one every
      // signed-in account may read. A recording nobody can open is not a
      // recording.
      final path = await repository.uploadMaterialFile(
        lessonId: lessonId,
        filename: file.name,
        bytes: await file.file.readAsBytes(),
      );

      final lesson = lessons.where((l) => l.id == lessonId).firstOrNull;
      await repository.addRecording(
        lessonId: lessonId,
        title: _title.text,
        videoUrl: path,
        category: lesson?.category,
        teacherId: lesson?.teacher?.id,
        recordedAt: lesson?.startsAt,
        durationSeconds: (lesson?.durationMinutes ?? 0) * 60,
        attendeeCount: lesson?.enrolledCount ?? 0,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = hkErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessons = ref.watch(assignableLessonsProvider).value ?? const [];
    final format = DateFormat('d-MMM, HH:mm', 'uz');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
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
                      child: Text('Yozuv qo‘shish', style: HkType.pageTitle),
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
                const SizedBox(height: 4),
                Text(
                  'Dars yozuvini shu yerga qo‘shsangiz, talabalar uni '
                  '“Yozuvlar” bo‘limida ochadi.',
                  style: HkType.muted,
                ),
                const SizedBox(height: 20),
                if (lessons.isEmpty)
                  Text(
                    'Sizga biriktirilgan dars yo‘q — yozuv darsga '
                    'biriktiriladi.',
                    style: HkType.body.copyWith(fontSize: 12.5),
                  )
                else
                  HkDropdownField<String>(
                    value: _lessonId,
                    label: 'Dars',
                    icon: Icons.menu_book_rounded,
                    validator: (v) => v == null ? 'Darsni tanlang' : null,
                    onChanged: (v) => setState(() => _lessonId = v),
                    items: [
                      for (final l in lessons)
                        DropdownMenuItem(
                          value: l.id,
                          child: Text(
                            '${format.format(l.startsAt)} · ${l.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _title,
                  label: 'Sarlavha',
                  icon: Icons.video_library_outlined,
                  textInputAction: TextInputAction.done,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Sarlavha kiriting' : null,
                ),
                const SizedBox(height: 12),
                HkFileRow(
                  name: _file?.name,
                  sizeBytes: _file?.sizeBytes,
                  onPick: _saving ? null : _pick,
                  onClear:
                      _saving ? null : () => setState(() => _file = null),
                  emptyLabel: 'Yozuv fayli biriktirilmagan',
                  pickLabel: 'Faylni tanlash',
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
                  label: _saving ? 'Yuklanmoqda…' : 'Saqlash',
                  expand: true,
                  onPressed: _saving || lessons.isEmpty
                      ? null
                      : () => _save(lessons),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
