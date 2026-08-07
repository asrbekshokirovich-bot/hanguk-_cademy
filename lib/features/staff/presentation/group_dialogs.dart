import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/dropdown_field.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../data/staff_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff_models.dart';

/// Puts one student in a group — which is how they get a teacher.
///
/// There is no separate "assign a teacher" action on purpose. A student's
/// teacher is whoever teaches their group; letting an admin set the two
/// independently is how a roster ends up saying one thing and the schedule
/// another.
Future<bool?> showAssignGroupDialog(
  BuildContext context, {
  required AdminStudent student,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _AssignGroupDialog(student: student),
  );
}

/// Create or edit one group. The list itself is a screen ("Guruhlar" in the
/// admin dock), not a dialog — it is where an admin spends real time.
Future<bool?> showGroupFormDialog(BuildContext context, {StudyGroup? group}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _GroupFormDialog(group: group),
  );
}

class _AssignGroupDialog extends ConsumerStatefulWidget {
  const _AssignGroupDialog({required this.student});

  final AdminStudent student;

  @override
  ConsumerState<_AssignGroupDialog> createState() => _AssignGroupDialogState();
}

class _AssignGroupDialogState extends ConsumerState<_AssignGroupDialog> {
  late String? _groupId = widget.student.groupId;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(staffRepositoryProvider)
          .assignStudentGroup(widget.student.studentId, _groupId);
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

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
    final groups = groupsAsync.value ?? const <StudyGroup>[];
    final selected = groups.where((g) => g.id == _groupId).firstOrNull;

    return _DialogFrame(
      title: 'Guruhga biriktirish',
      subtitle: widget.student.fullName,
      children: [
        if (groupsAsync.isLoading && groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          HkDropdownField<String?>(
            value: groups.any((g) => g.id == _groupId) ? _groupId : null,
            label: 'Guruh',
            icon: Icons.groups_2_outlined,
            helperText: groups.isEmpty
                ? 'Hali guruh yo‘q — avval “Guruhlar” dan yarating'
                : null,
            items: [
              const DropdownMenuItem(value: null, child: Text('Guruhsiz')),
              for (final g in groups)
                DropdownMenuItem(
                  value: g.id,
                  child: Text('${g.name} · ${g.memberCount} ta'),
                ),
            ],
            onChanged: (v) => setState(() => _groupId = v),
          ),
          const SizedBox(height: 12),
          Text(
            selected?.teacherName == null
                ? 'Guruh tanlansa, o‘qituvchi ham shu bilan belgilanadi.'
                : 'O‘qituvchi: ${selected!.teacherName}. Talaba guruhning '
                    'kelgusi darslariga avtomatik qo‘shiladi.',
            style: HkType.muted,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: HkType.muted.copyWith(color: HkColors.dangerBright),
          ),
        ],
        const SizedBox(height: 22),
        LimeButton(
          label: _busy ? 'Saqlanmoqda…' : 'Saqlash',
          expand: true,
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}

class _GroupFormDialog extends ConsumerStatefulWidget {
  const _GroupFormDialog({this.group});

  final StudyGroup? group;

  @override
  ConsumerState<_GroupFormDialog> createState() => _GroupFormDialogState();
}

class _GroupFormDialogState extends ConsumerState<_GroupFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late String? _teacherId = widget.group?.teacherId;
  late int? _level = widget.group?.level;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.group != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(StaffRepository repo) action) async {
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
        await repo.updateGroup(
          widget.group!.id,
          name: _name.text,
          teacherId: _teacherId,
          level: _level,
        );
      } else {
        await repo.createGroup(
          name: _name.text,
          teacherId: _teacherId!,
          level: _level,
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
        title: const Text('Guruhni o‘chirish', style: HkType.cardTitle),
        content: Text(
          '“${widget.group!.name}” o‘chiriladi. Undagi '
          '${widget.group!.memberCount} ta talaba guruhsiz qoladi.',
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
    await _run((repo) => repo.deleteGroup(widget.group!.id));
  }

  @override
  Widget build(BuildContext context) {
    final teachers = ref.watch(teacherRosterProvider).value ?? const [];

    return _DialogFrame(
      title: _isEdit ? 'Guruhni tahrirlash' : 'Yangi guruh',
      form: _formKey,
      children: [
        AuthField(
          controller: _name,
          label: 'Guruh nomi',
          icon: Icons.groups_2_outlined,
          textInputAction: TextInputAction.next,
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
          helperText: 'Masalan: “Daraja 2 · A”',
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'Guruh nomini kiriting' : null,
        ),
        const SizedBox(height: 14),
        HkDropdownField<String?>(
          value: teachers.any((t) => t.id == _teacherId) ? _teacherId : null,
          label: 'O‘qituvchi',
          icon: Icons.person_outline_rounded,
          helperText: teachers.isEmpty
              ? 'Avval “O‘qituvchilar” bo‘limida hisob oching'
              : null,
          items: [
            for (final t in teachers)
              DropdownMenuItem(value: t.id, child: Text(t.fullName)),
          ],
          onChanged: (v) => setState(() => _teacherId = v),
          validator: (v) => v == null ? 'O‘qituvchini tanlang' : null,
        ),
        const SizedBox(height: 14),
        HkDropdownField<int?>(
          value: _level,
          label: 'Daraja',
          icon: Icons.stairs_outlined,
          items: [
            const DropdownMenuItem(value: null, child: Text('Belgilanmagan')),
            for (var i = 1; i <= 6; i++)
              DropdownMenuItem(value: i, child: Text('$i-daraja')),
          ],
          onChanged: (v) => setState(() => _level = v),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: HkType.muted.copyWith(color: HkColors.dangerBright),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            if (_isEdit)
              TextButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('O‘chirish'),
                style:
                    TextButton.styleFrom(foregroundColor: HkColors.dangerBright),
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
    );
  }
}

/// The glass card every dialog on this screen sits in.
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.title,
    required this.children,
    this.subtitle,
    this.form,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final GlobalKey<FormState>? form;

  @override
  Widget build(BuildContext context) {
    Widget body = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: HkType.pageTitle)),
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
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: HkType.muted),
          ],
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );

    if (form != null) body = Form(key: form, child: body);

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
          child: body,
        ),
      ),
    );
  }
}
