import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/clock.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/dropdown_field.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../../lessons/domain/models.dart';
import '../data/staff_providers.dart';
import '../data/staff_repository.dart';

/// "Yangi vazifa" — sets the homework on one of this teacher's lessons.
///
/// There was no way to do this anywhere in the app. `ol_assignments` has been
/// in the schema since the first migration, students' screens read from it
/// and the grading queue is built on what comes back against it — but nothing
/// ever wrote a row. A teacher was asked to mark work that could not be set,
/// so "Baholash" was an empty screen with no way of ever ceasing to be one.
///
/// Returns true when something was saved, so the caller can refresh.
Future<bool?> showAssignmentDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => const _AssignmentDialog(),
  );
}

class _AssignmentDialog extends ConsumerStatefulWidget {
  const _AssignmentDialog();

  @override
  ConsumerState<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends ConsumerState<_AssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Uy vazifasi');
  final _body = TextEditingController();

  String? _lessonId;
  DateTime? _dueAt;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = hkNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now.add(const Duration(days: 3)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      // No `locale:` here. The app declares `uz` and the picker inherits it;
      // naming it again only re-creates the way this crashed — a locale
      // passed to a widget whose delegates do not cover it fails to build,
      // and a failed build is a blank window.
    );
    if (picked == null) return;
    // End of the chosen day, not midnight at the start of it. "Due Friday"
    // means Friday is still fine, and a deadline that expires as Friday
    // begins would mark every on-time answer late.
    setState(() {
      _dueAt = DateTime(picked.year, picked.month, picked.day, 23, 59);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(staffRepositoryProvider).setAssignment(
            lessonId: _lessonId!,
            title: _title.text,
            body: _body.text,
            dueAt: _dueAt,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessons = ref.watch(assignableLessonsProvider);

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
                      child: Text('Yangi vazifa', style: HkType.pageTitle),
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
                  'Vazifa darsga biriktiriladi. Shu darsga yozilgan '
                  'talabalar uni ko‘radi.',
                  style: HkType.muted,
                ),
                const SizedBox(height: 20),
                _LessonPicker(
                  lessons: lessons,
                  value: _lessonId,
                  onChanged: (v) => setState(() => _lessonId = v),
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _title,
                  label: 'Sarlavha',
                  icon: Icons.assignment_outlined,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Sarlavha kiriting'
                      : null,
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _body,
                  label: 'Topshiriq (ixtiyoriy)',
                  icon: Icons.notes_rounded,
                  textInputAction: TextInputAction.newline,
                ),
                const SizedBox(height: 14),
                _DueRow(
                  dueAt: _dueAt,
                  onPick: _pickDue,
                  onClear: () => setState(() => _dueAt = null),
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
                  label: _saving ? 'Saqlanmoqda…' : 'Vazifani berish',
                  expand: true,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which lesson the homework hangs off.
///
/// Its own widget because the list arrives asynchronously and the three
/// states are genuinely different: still loading, nothing to attach to, and
/// a choice. A dropdown that renders empty while it loads reads as "you have
/// no lessons", which for a teacher is alarming and wrong.
class _LessonPicker extends StatelessWidget {
  const _LessonPicker({
    required this.lessons,
    required this.value,
    required this.onChanged,
  });

  final AsyncValue<List<Lesson>> lessons;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return lessons.when(
      loading: () => const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: HkColors.lime,
            ),
          ),
        ),
      ),
      error: (e, _) => Text(
        'Darslar ro‘yxatini yuklab bo‘lmadi: $e',
        style: HkType.body.copyWith(
          fontSize: 12.5,
          color: HkColors.dangerBright,
        ),
      ),
      data: (all) {
        if (all.isEmpty) {
          // Both ways of having no lesson point at the same person, so the
          // sentence names both: the timetable may be empty, or it may have
          // lessons with somebody else's name against them.
          return Text(
            'Sizga biriktirilgan dars yo‘q. Vazifa darsga biriktiriladi — '
            'administrator darsni yaratib, o‘qituvchi qilib sizni '
            'biriktirishi kerak.',
            style: HkType.body.copyWith(fontSize: 12.5),
          );
        }
        final format = DateFormat('d-MMM, HH:mm', 'uz');
        return HkDropdownField<String>(
          value: value,
          label: 'Dars',
          icon: Icons.menu_book_rounded,
          validator: (v) => v == null ? 'Darsni tanlang' : null,
          onChanged: onChanged,
          items: [
            for (final l in all)
              DropdownMenuItem(
                value: l.id,
                child: Text(
                  '${format.format(l.startsAt)} · ${l.title}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The deadline, which is optional on purpose: plenty of homework is "before
/// next lesson", and inventing a date for it would make every such piece
/// read as overdue the moment the week turned.
class _DueRow extends StatelessWidget {
  const _DueRow({
    required this.dueAt,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? dueAt;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final label = dueAt == null
        ? 'Muddat belgilanmagan'
        : DateFormat('d-MMMM, EEEE', 'uz').format(dueAt!);

    return Row(
      children: [
        const Icon(
          Icons.event_outlined,
          size: 18,
          color: HkColors.textSecondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: HkType.body.copyWith(fontSize: 13)),
        ),
        if (dueAt != null)
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
            dueAt == null ? 'Muddat qo‘yish' : 'O‘zgartirish',
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
