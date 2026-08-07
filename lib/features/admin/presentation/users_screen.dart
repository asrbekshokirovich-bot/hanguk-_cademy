import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/command_dock.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/admin_repository.dart';
import '../domain/managed_user.dart';
import 'create_user_dialog.dart';
import 'password_result_dialog.dart';

/// "Talabalar" — the account roster.
///
/// Admin only. The router keeps everyone else out, but the screen also
/// degrades gracefully if it is reached another way: without the admin role
/// the underlying view returns just the caller's own row.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);

    return AppShell(
      destination: HkDestination.students,
      title: 'Talabalar',
      subtitle: 'Hisoblarni yaratish va boshqarish',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Har bir talaba va o‘qituvchiga login va parol shu yerdan '
                  'beriladi.',
                  style: HkType.body.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: () => _createUser(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: HkColors.royalBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HkRadius.control),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                  label: const Text(
                    'Yangi hisob',
                    style: TextStyle(
                      fontFamily: HkType.family,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(managedUsersProvider),
            onRetry: () => ref.invalidate(managedUsersProvider),
            loadingHeight: 240,
            isEmpty: (u) => u.isEmpty,
            emptyMessage: 'Hali hisob yaratilmagan',
            builder: (users) => GlassPanel(
              radius: HkRadius.cardLarge,
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  if (layout.isExpanded) const _TableHeader(),
                  for (final user in users)
                    _UserRow(user: user, expanded: layout.isExpanded),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createUser(BuildContext context, WidgetRef ref) async {
    final created = await showCreateUserDialog(context);
    if (created == null || !context.mounted) return;

    ref.invalidate(managedUsersProvider);
    // The generated password exists nowhere else in readable form, so it has
    // to be put in front of the admin before anything else happens.
    await showPasswordResultDialog(
      context,
      title: 'Hisob yaratildi',
      username: created.username,
      fullName: created.fullName,
      password: created.password,
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int flex) =>
        Expanded(flex: flex, child: Text(label, style: HkType.muted));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          cell('Ism familiya', 5),
          cell('Login', 4),
          cell('Rol', 3),
          cell('Oxirgi kirish', 4),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({required this.user, required this.expanded});

  final ManagedUser user;
  final bool expanded;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _busy = false;

  String get _lastSignIn {
    final at = widget.user.lastSignInAt;
    if (at == null) return 'Hech qachon';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'hozir';
    if (d.inMinutes < 60) return '${d.inMinutes} daq oldin';
    if (d.inHours < 24) return '${d.inHours} soat oldin';
    if (d.inDays < 7) return '${d.inDays} kun oldin';
    return DateFormat('d-MMMM y', 'uz').format(at);
  }

  Future<void> _resetPassword() async {
    final user = widget.user;
    final confirmed = await _confirm(
      title: 'Parolni tiklash',
      body: '${user.fullName} uchun yangi parol yaratiladi. Eski parol '
          'ishlamay qoladi.',
      action: 'Tiklash',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final password =
          await ref.read(adminRepositoryProvider).resetPassword(user.userId);
      ref.invalidate(managedUsersProvider);
      if (!mounted) return;
      await showPasswordResultDialog(
        context,
        title: 'Yangi parol',
        username: user.username ?? '—',
        fullName: user.fullName,
        password: password,
      );
    } catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final user = widget.user;
    final confirmed = await _confirm(
      title: 'Hisobni o‘chirish',
      body: '${user.fullName} (${user.username ?? '—'}) butunlay '
          'o‘chiriladi. Bu amalni qaytarib bo‘lmaydi.',
      action: 'O‘chirish',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).deleteUser(user.userId);
      ref.invalidate(managedUsersProvider);
    } catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole(String role) async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).updateRole(
            widget.user.userId,
            role,
            // Only students carry a level; keeping one on a promoted teacher
            // would show "Daraja 2" under their name forever.
            level: role == 'student' ? widget.user.level : null,
          );
      ref.invalidate(managedUsersProvider);
    } catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _report(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error')),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HkColors.royalBlue800,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HkRadius.card),
        ),
        title: Text(title, style: HkType.sectionTitle),
        content: Text(body, style: HkType.body.copyWith(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Bekor qilish', style: HkType.muted),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  destructive ? HkColors.danger : HkColors.royalBlue,
            ),
            child: Text(action, style: HkType.label),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;

    final actions = _busy
        ? const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HkColors.lime,
              ),
            ),
          )
        : PopupMenuButton<String>(
            tooltip: 'Amallar',
            color: HkColors.royalBlue800,
            icon: const Icon(
              Icons.more_horiz_rounded,
              size: 18,
              color: HkColors.textTertiary,
            ),
            onSelected: (value) => switch (value) {
              'reset' => _resetPassword(),
              'delete' => _delete(),
              _ => _changeRole(value.replaceFirst('role:', '')),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset',
                child: Text('Parolni tiklash'),
              ),
              const PopupMenuDivider(),
              for (final role in ['student', 'teacher', 'admin'])
                if (role != u.role)
                  PopupMenuItem(
                    value: 'role:$role',
                    child: Text(switch (role) {
                      'admin' => 'Administrator qilish',
                      'teacher' => "O'qituvchi qilish",
                      _ => 'Talaba qilish',
                    }),
                  ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'O‘chirish',
                  style: TextStyle(color: HkColors.dangerBright),
                ),
              ),
            ],
          );

    if (!widget.expanded) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            HkAvatar(initials: u.initials, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.fullName, style: HkType.cardTitle),
                  const SizedBox(height: 3),
                  Text('@${u.username ?? '—'}', style: HkType.muted),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      HkPill(
                        label: u.roleLabel,
                        background: u.roleBackground,
                        foreground: u.roleColor,
                      ),
                      if (u.mustChangePassword)
                        const HkPill(
                          label: 'Parol yangilanmagan',
                          background: Color(0x26E08600),
                          foreground: HkColors.warningBright,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions,
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                HkAvatar(initials: u.initials, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.fullName,
                        style: HkType.cardTitle.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (u.level != null) ...[
                        const SizedBox(height: 2),
                        Text('Daraja ${u.level}', style: HkType.muted),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    u.username ?? '—',
                    style: HkType.monoTime.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (u.mustChangePassword) ...[
                  const SizedBox(width: 8),
                  const Tooltip(
                    message: 'Parol hali o‘zgartirilmagan',
                    child: Icon(
                      Icons.key_off_outlined,
                      size: 15,
                      color: HkColors.warningBright,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: HkPill(
                label: u.roleLabel,
                background: u.roleBackground,
                foreground: u.roleColor,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _lastSignIn,
              style: HkType.muted.copyWith(
                color: u.hasNeverSignedIn
                    ? HkColors.textTertiary
                    : HkColors.textSecondary,
              ),
            ),
          ),
          SizedBox(width: 48, child: actions),
        ],
      ),
    );
  }
}
