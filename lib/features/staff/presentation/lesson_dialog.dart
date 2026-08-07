import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Create or edit a lesson. Returns true when something was written, so the
/// caller knows to invalidate the schedule.
///
/// Only an admin reaches this — the schedule gates the buttons on the profile
/// role, and `ol_lessons` RLS rejects the write regardless.
Future<bool?> showLessonDialog(BuildContext context, {Lesson? lesson}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _LessonDialog(lesson: lesson),
  );
}

const _categories = [
  'Suhbat',
  'Grammatika',
  'Tinglash',
  'TOPIK',
  'Talaffuz',
  'Yozma nutq',
];

const _durations = [30, 45, 60, 75, 90, 120];

class _LessonDialog extends ConsumerStatefulWidget {
  const _LessonDialog({this.lesson});

  final Lesson? lesson;

  @override
  ConsumerState<_LessonDialog> createState() => _LessonDialogState();
}

class _LessonDialogState extends ConsumerState<_LessonDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.lesson?.title ?? '');
  late final _description =
      TextEditingController(text: widget.lesson?.description ?? '');

  late String _category = _categories.contains(widget.lesson?.category)
      ? widget.lesson!.category
      : _categories.first;
  late DateTime _date = _dateOnly(widget.lesson?.startsAt ?? _nextHour());
  late TimeOfDay _time =
      TimeOfDay.fromDateTime(widget.lesson?.startsAt ?? _nextHour());
  late int _duration = _durations.contains(widget.lesson?.durationMinutes)
      ? widget.lesson!.durationMinutes
      : 60;
  late String? _teacherId = widget.lesson?.teacher?.id;
  late String? _groupId = widget.lesson?.groupId;
  late bool _autoRecord = widget.lesson?.autoRecord ?? true;

  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.lesson != null;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _nextHour() {
    final now = hkNow();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  DateTime get _startsAt => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(hkNow().year - 1),
      lastDate: DateTime(hkNow().year + 3),
      helpText: 'Dars sanasi',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Boshlanish vaqti',
      // Nobody here writes lesson times as "2 PM".
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _run(Future<void> Function(StaffRepository repo) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(staffRepositoryProvider));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _run((repo) async {
      if (_isEdit) {
        await repo.updateLesson(
          widget.lesson!.id,
          title: _title.text,
          category: _category,
          startsAt: _startsAt,
          durationMinutes: _duration,
          teacherId: _teacherId,
          groupId: _groupId,
          description: _description.text,
          autoRecord: _autoRecord,
        );
      } else {
        await repo.createLesson(
          title: _title.text,
          category: _category,
          startsAt: _startsAt,
          durationMinutes: _duration,
          teacherId: _teacherId,
          groupId: _groupId,
          description:
              _description.text.trim().isEmpty ? null : _description.text,
          autoRecord: _autoRecord,
        );
      }
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF00C1430),
        title: const Text('Darsni o‘chirish', style: HkType.cardTitle),
        content: Text(
          '“${widget.lesson!.title}” o‘chiriladi. Bu amalni qaytarib '
          'bo‘lmaydi.',
          style: HkType.body.copyWith(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Bekor qilish'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'O‘chirish',
              style: TextStyle(color: HkColors.dangerBright),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run((repo) => repo.deleteLesson(widget.lesson!.id));
  }

  @override
  Widget build(BuildContext context) {
    final teachers = ref.watch(teacherRosterProvider).value ?? const [];
    final groups = ref.watch(groupsProvider).value ?? const [];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(24),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEdit ? 'Darsni tahrirlash' : 'Yangi dars',
                          style: HkType.pageTitle,
                        ),
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
                    'Guruh tanlansa, guruhdagi barcha talabalar shu darsga '
                    'avtomatik biriktiriladi.',
                    style: HkType.muted,
                  ),
                  const SizedBox(height: 20),
                  AuthField(
                    controller: _title,
                    label: 'Dars nomi',
                    icon: Icons.menu_book_outlined,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [LengthLimitingTextInputFormatter(120)],
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Dars nomini kiriting'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  HkDropdownField<String>(
                    value: _category,
                    label: 'Yo‘nalish',
                    icon: Icons.category_outlined,
                    items: [
                      for (final c in _categories)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _PickerField(
                          label: 'Sana',
                          icon: Icons.event_outlined,
                          value: DateFormat('d-MMMM, y', 'uz').format(_date),
                          onTap: _pickDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PickerField(
                          label: 'Vaqt',
                          icon: Icons.schedule_outlined,
                          value: '${_time.hour.toString().padLeft(2, '0')}:'
                              '${_time.minute.toString().padLeft(2, '0')}',
                          onTap: _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  HkDropdownField<int>(
                    value: _duration,
                    label: 'Davomiyligi',
                    icon: Icons.timelapse_outlined,
                    items: [
                      for (final d in _durations)
                        DropdownMenuItem(value: d, child: Text('$d daqiqa')),
                    ],
                    onChanged: (v) => setState(() => _duration = v!),
                  ),
                  const SizedBox(height: 14),
                  HkDropdownField<String?>(
                    value: teachers.any((t) => t.id == _teacherId)
                        ? _teacherId
                        : null,
                    label: 'O‘qituvchi',
                    icon: Icons.person_outline_rounded,
                    helperText: teachers.isEmpty
                        ? 'Avval “O‘qituvchilar” bo‘limida hisob oching'
                        : null,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final t in teachers)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(t.fullName),
                        ),
                    ],
                    onChanged: (v) => setState(() => _teacherId = v),
                  ),
                  const SizedBox(height: 14),
                  HkDropdownField<String?>(
                    value: groups.any((g) => g.id == _groupId) ? _groupId : null,
                    label: 'Guruh',
                    icon: Icons.groups_2_outlined,
                    helperText: groups.isEmpty
                        ? 'Hali guruh yo‘q — “Talabalar” bo‘limidan oching'
                        : null,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Guruhsiz'),
                      ),
                      for (final g in groups)
                        DropdownMenuItem(
                          value: g.id,
                          child: Text('${g.name} · ${g.memberCount} ta'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _groupId = v),
                  ),
                  const SizedBox(height: 14),
                  AuthField(
                    controller: _description,
                    label: 'Tavsif (ixtiyoriy)',
                    icon: Icons.notes_rounded,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 16),
                  // A plain row rather than a SwitchListTile: the tile paints
                  // its ink on the nearest Material, which the glass panel's
                  // own background sits on top of.
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Avto-yozuv', style: HkType.label),
                            const SizedBox(height: 2),
                            Text(
                              'Dars yozib olinadi va “Yozuvlar”ga tushadi',
                              style: HkType.muted,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _autoRecord,
                        onChanged: (v) => setState(() => _autoRecord = v),
                        activeThumbColor: HkColors.ink,
                        activeTrackColor: HkColors.lime,
                        inactiveThumbColor: HkColors.textTertiary,
                        inactiveTrackColor: const Color(0x14FFFFFF),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: HkType.muted.copyWith(
                        color: HkColors.dangerBright,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (_isEdit)
                        TextButton.icon(
                          onPressed: _busy ? null : _delete,
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('O‘chirish'),
                          style: TextButton.styleFrom(
                            foregroundColor: HkColors.dangerBright,
                          ),
                        ),
                      const Spacer(),
                      LimeButton(
                        label: _busy ? 'Saqlanmoqda…' : 'Saqlash',
                        height: 46,
                        onPressed: _busy ? null : _save,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A read-only field that opens a picker. Matches [AuthField] so the date and
/// time sit in the same column of boxes as everything else.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(HkRadius.control),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: HkType.body.copyWith(fontSize: 13.5),
          prefixIcon: Icon(icon, size: 18, color: HkColors.textTertiary),
          filled: true,
          fillColor: const Color(0x0FFFFFFF),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(HkRadius.control)),
            borderSide: BorderSide(color: HkGlass.border),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(HkRadius.control)),
            borderSide: BorderSide(color: HkGlass.border),
          ),
        ),
        child: Text(
          value,
          style: HkType.body.copyWith(
            fontSize: 14,
            color: HkColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
