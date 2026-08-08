import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/data_table.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../../admin/data/admin_repository.dart';
import '../../admin/domain/managed_user.dart';
import '../../admin/presentation/create_user_dialog.dart';
import '../../admin/presentation/password_result_dialog.dart';
import '../../lessons/data/providers.dart';
import '../domain/staff_models.dart';

/// "Adminlar" — the superadmin's own screen, and the only one besides Moliya.
///
/// The top tier does not run the school day. It hands the school day to
/// somebody: this screen is where an administrator account is issued, its
/// password reissued when it is lost, and revoked when the person leaves.
/// Everything else — students, groups, the timetable — belongs to the
/// administrators created here.
class SuperAdminScreen extends ConsumerWidget {
  const SuperAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);

    return AppShell(
      title: 'Adminlar',
      subtitle: 'Administrator hisoblari',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Outside the AsyncSection: an empty list must not hide the only way
          // to fill it.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Administrator akademiyaning kundalik ishini yuritadi — '
                  'talabalar, o‘qituvchilar, guruhlar va jadval. Moliya va '
                  'yangi admin ochish faqat sizda qoladi.',
                  style: HkType.body.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  onPressed: () => _create(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: HkColors.royalBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HkRadius.control),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                  label: const Text(
                    'Yangi admin',
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
            loadingHeight: 260,
            // The roster carries every account; this screen is about the ones
            // that carry rights.
            isEmpty: (users) => users.where((u) => u.isAdministrator).isEmpty,
            emptyMessage:
                'Hali admin yo‘q — “Yangi admin” tugmasi bilan oching',
            builder: (users) {
              final admins =
                  users.where((u) => u.isAdministrator).toList(growable: false);

              return HkTable(
                showHeader: layout.isExpanded,
                columns: const [
                  HkColumn('Hisob', 5),
                  HkColumn('Login', 3),
                  HkColumn('Rol', 3),
                  HkColumn('Oxirgi kirish', 3),
                  HkColumn('', 2),
                ],
                rows: [
                  for (final u in admins)
                    _AdminRow(
                      user: u,
                      expanded: layout.isExpanded,
                      onReset: () => _reset(context, ref, u),
                      onDelete: () => _delete(context, ref, u),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    // One role only. A superadmin issuing a student account would be doing an
    // administrator's job from the wrong screen.
    final created = await showCreateUserDialog(context, roles: const ['admin']);
    if (created == null || !context.mounted) return;

    ref.invalidate(managedUsersProvider);
    await showPasswordResultDialog(
      context,
      title: 'Admin hisobi yaratildi',
      username: created.username,
      fullName: created.fullName,
      password: created.password,
    );
  }

  Future<void> _reset(
    BuildContext context,
    WidgetRef ref,
    ManagedUser user,
  ) async {
    try {
      final password =
          await ref.read(adminRepositoryProvider).resetPassword(user.userId);
      if (!context.mounted) return;
      ref.invalidate(managedUsersProvider);
      await showPasswordResultDialog(
        context,
        title: 'Yangi parol',
        username: user.username ?? '—',
        fullName: user.fullName,
        password: password,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ManagedUser user,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF00C1430),
        title: const Text('Hisobni o‘chirish', style: HkType.cardTitle),
        content: Text(
          '${user.fullName} (${user.username ?? '—'}) hisobi o‘chiriladi va '
          'u tizimga kira olmaydi.',
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
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(adminRepositoryProvider).deleteUser(user.userId);
      ref.invalidate(managedUsersProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _AdminRow extends ConsumerWidget {
  const _AdminRow({
    required this.user,
    required this.expanded,
    required this.onReset,
    required this.onDelete,
  });

  final ManagedUser user;
  final bool expanded;
  final VoidCallback onReset;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = user;
    // No actions on a top-tier row. Resetting your own password here would
    // log you out of the screen you are standing on, and deleting the last
    // superadmin would lock the academy out of its own accounts — the
    // database refuses that one outright.
    final locked = u.role == 'superadmin' ||
        ref.watch(profileProvider).value?.id == u.userId;

    final lastSeen = u.lastSignInAt == null
        ? Text('Hech qachon', style: HkType.muted)
        : Text(
            DateFormat('d-MMM, HH:mm', 'uz').format(u.lastSignInAt!),
            style: HkType.muted,
          );

    final rolePill = HkPill(
      label: u.roleLabel,
      background: u.roleBackground,
      foreground: u.roleColor,
    );

    final actions = locked
        ? const SizedBox.shrink()
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Parolni tiklash',
                onPressed: onReset,
                icon: const Icon(
                  Icons.key_outlined,
                  size: 17,
                  color: HkColors.textTertiary,
                ),
              ),
              IconButton(
                tooltip: 'O‘chirish',
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: HkColors.textTertiary,
                ),
              ),
            ],
          );

    if (!expanded) {
      return HkTableRow(
        padding: const EdgeInsets.all(14),
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HkPersonCell(
                  name: u.fullName,
                  initials: u.initials,
                  gradient: hkGradientFor(u.userId),
                  subtitle: u.username,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    rolePill,
                    const SizedBox(width: 10),
                    Expanded(child: lastSeen),
                    actions,
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return HkTableRow(
      children: [
        Expanded(
          flex: 5,
          child: HkPersonCell(
            name: u.fullName,
            initials: u.initials,
            gradient: hkGradientFor(u.userId),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            u.username ?? '—',
            style: HkType.monoTime.copyWith(fontSize: 12.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(alignment: Alignment.centerLeft, child: rolePill),
        ),
        Expanded(flex: 3, child: lastSeen),
        Expanded(
          flex: 2,
          child: Align(alignment: Alignment.centerRight, child: actions),
        ),
      ],
    );
  }
}
