import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 moved StateProvider out of the main barrel; the filter here is
// a single value driven by a tap, which is what it is for.
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/clock.dart';
import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/data_table.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/section_intro.dart';
import '../../../design_system/widgets/states.dart';
import '../../admin/data/admin_repository.dart';
import '../../admin/presentation/create_user_dialog.dart';
import '../../admin/presentation/password_result_dialog.dart';
import '../data/staff_providers.dart';
import '../domain/staff_models.dart';
import 'group_dialogs.dart';

/// Payment-state filter for the roster. `null` shows everyone.
final adminStudentFilterProvider = StateProvider<PaymentStatus?>((ref) => null);

/// "Talabalar" for an admin: the whole roster, with contact details, group,
/// teacher, attendance and payment state — plus account creation.
///
/// This replaces the earlier accounts-only screen. Two separate lists of the
/// same people, one for accounts and one for everything else, is how an
/// office ends up with two different answers to "who is enrolled".
class AdminStudentsScreen extends ConsumerWidget {
  const AdminStudentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final filter = ref.watch(adminStudentFilterProvider);
    final now = hkNow();

    return AppShell(
      title: 'Talabalar',
      subtitle: 'Hisoblar, guruhlar va to‘lov holati',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Outside the AsyncSection on purpose. It used to live inside the
          // data builder, so an empty roster replaced the whole block —
          // including this button — with "Hali talaba qo'shilmagan". The one
          // moment you certainly need to add a student is when there are
          // none.
          HkSectionIntro(
            text: 'Har bir talaba va o‘qituvchiga login va parol shu yerdan '
                'beriladi.',
            action: FilledButton.icon(
              onPressed: () => _createStudent(context, ref),
              style: FilledButton.styleFrom(
                backgroundColor: HkColors.royalBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HkRadius.control),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              icon: const Icon(Icons.person_add_alt_rounded, size: 18),
              label: const Text(
                'Yangi talaba',
                style: TextStyle(
                  fontFamily: HkType.family,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(adminStudentsProvider),
            onRetry: () => ref.invalidate(adminStudentsProvider),
            loadingHeight: 260,
            isEmpty: (s) => s.isEmpty,
            emptyMessage:
                'Hali talaba yo‘q — “Yangi talaba” tugmasi bilan qo‘shing',
            builder: (students) {
              final shown = filter == null
                  ? students
                  : students.where((s) => s.paymentStatus == filter).toList();

              int countOf(PaymentStatus s) =>
                  students.where((x) => x.paymentStatus == s).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _Chip(
                        label: 'Barchasi · ${students.length}',
                        active: filter == null,
                        onTap: () =>
                            ref
                                    .read(adminStudentFilterProvider.notifier)
                                    .state =
                                null,
                      ),
                      for (final s in [
                        PaymentStatus.confirmed,
                        PaymentStatus.pending,
                        PaymentStatus.overdue,
                      ])
                        if (countOf(s) > 0)
                          _Chip(
                            label: '${s.label} · ${countOf(s)}',
                            active: filter == s,
                            accent: s.color,
                            onTap: () =>
                                ref
                                        .read(
                                          adminStudentFilterProvider.notifier,
                                        )
                                        .state =
                                    s,
                          ),
                    ],
                  ),
                  const SizedBox(height: HkSpace.gridGapWide),
                  HkTable(
                    showHeader: layout.isExpanded,
                    columns: const [
                      HkColumn('Talaba', 5),
                      HkColumn('Telefon', 4),
                      HkColumn('Guruh', 4),
                      HkColumn("O'qituvchi", 4),
                      HkColumn('Davomat', 3),
                      HkColumn("To'lov", 3),
                      HkColumn('', 1),
                    ],
                    rows: [
                      for (final s in shown)
                        _StudentRow(
                          student: s,
                          expanded: layout.isExpanded,
                          now: now,
                          onAssign: () => _assignGroup(context, ref, s),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// A student's teacher follows from their group, so this one action covers
  /// both halves of "biriktirish".
  Future<void> _assignGroup(
    BuildContext context,
    WidgetRef ref,
    AdminStudent student,
  ) async {
    final saved = await showAssignGroupDialog(context, student: student);
    if (saved == true) {
      ref.invalidate(adminStudentsProvider);
      ref.invalidate(groupsProvider);
      ref.invalidate(teacherRosterProvider);
    }
  }

  Future<void> _createStudent(BuildContext context, WidgetRef ref) async {
    final created = await showCreateUserDialog(context);
    if (created == null || !context.mounted) return;

    ref.invalidate(adminStudentsProvider);
    ref.invalidate(managedUsersProvider);
    // The generated password exists nowhere else in readable form.
    await showPasswordResultDialog(
      context,
      title: 'Hisob yaratildi',
      username: created.username,
      fullName: created.fullName,
      password: created.password,
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.expanded,
    required this.now,
    required this.onAssign,
  });

  final AdminStudent student;
  final bool expanded;
  final DateTime now;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final s = student;

    if (!expanded) {
      return HkTableRow(
        padding: const EdgeInsets.all(14),
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HkPersonCell(
                  name: s.fullName,
                  initials: s.initials,
                  gradient: s.gradient,
                  subtitle: s.groupName,
                ),
                const SizedBox(height: 10),
                if (s.phone != null)
                  Text(s.phone!, style: HkType.monoTime.copyWith(fontSize: 12)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    HkPill(
                      label: s.paymentStatus.label,
                      background: s.paymentStatus.background,
                      foreground: s.paymentStatus.color,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Davomat ${hkPercent(s.attendance)}',
                      style: HkType.muted.copyWith(
                        color: hkRateColor(s.attendance),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Guruhga biriktirish',
                      onPressed: onAssign,
                      icon: const Icon(
                        Icons.group_add_outlined,
                        size: 18,
                        color: HkColors.textTertiary,
                      ),
                    ),
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
            name: s.fullName,
            initials: s.initials,
            gradient: s.gradient,
            subtitle: s.username == null ? null : '@${s.username}',
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            s.phone ?? '—',
            style: HkType.monoTime.copyWith(fontSize: 12.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            s.groupName ?? '—',
            style: HkType.body.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            s.teacherName ?? '—',
            style: HkType.body.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: HkRateCell(
            value: s.attendance,
            color: hkRateColor(s.attendance),
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: HkPill(
              label: s.paymentStatus.label,
              background: s.paymentStatus.background,
              foreground: s.paymentStatus.color,
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: IconButton(
            tooltip: 'Guruhga biriktirish',
            onPressed: onAssign,
            icon: const Icon(
              Icons.group_add_outlined,
              size: 17,
              color: HkColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? accent;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: widget.active && widget.accent == null
                ? kLimeGradient
                : null,
            color: widget.active
                ? widget.accent?.withValues(alpha: 0.22)
                : (_hovered ? HkGlass.hoverFill : const Color(0x0FFFFFFF)),
            borderRadius: BorderRadius.circular(HkRadius.pill),
            border: Border.all(
              color: widget.active
                  ? (widget.accent ?? Colors.transparent)
                  : HkGlass.border,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: HkType.family,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: widget.active
                  ? (widget.accent ?? HkColors.ink)
                  : HkColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
