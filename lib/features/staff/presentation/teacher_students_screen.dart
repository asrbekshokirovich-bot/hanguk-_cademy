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
import '../../../design_system/widgets/states.dart';
import '../data/staff_providers.dart';
import '../domain/staff_models.dart';

/// Which group the teacher is looking at. `null` is everyone.
final teacherGroupFilterProvider = StateProvider<String?>((ref) => null);

/// "Talabalarim" — the teacher's roster with attendance and progress.
///
/// The point of the screen is spotting the two or three students who are
/// slipping, so those are surfaced as a labelled state ("Diqqat") rather than
/// left for the reader to infer from a column of percentages.
class TeacherStudentsScreen extends ConsumerWidget {
  const TeacherStudentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final filter = ref.watch(teacherGroupFilterProvider);
    final now = hkNow();

    return AppShell(
      title: 'Talabalarim',
      subtitle: 'Davomat va o‘zlashtirish',
      child: AsyncSection(
        value: ref.watch(myStudentsProvider),
        onRetry: () => ref.invalidate(myStudentsProvider),
        loadingHeight: 260,
        isEmpty: (s) => s.isEmpty,
        emptyMessage: 'Sizga hali guruh biriktirilmagan',
        builder: (students) {
          final groups = <String>{
            for (final s in students)
              if (s.groupName != null) s.groupName!,
          }.toList()
            ..sort();

          final shown = filter == null
              ? students
              : students.where((s) => s.groupName == filter).toList();

          final attention = students.where((s) => s.needsAttention).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(
                    label: 'Barcha guruhlar',
                    active: filter == null,
                    onTap: () => ref
                        .read(teacherGroupFilterProvider.notifier)
                        .state = null,
                  ),
                  for (final g in groups)
                    _Chip(
                      label: g,
                      active: filter == g,
                      onTap: () => ref
                          .read(teacherGroupFilterProvider.notifier)
                          .state = g,
                    ),
                  if (attention > 0)
                    HkPill(
                      label: "$attention ta e'tibor talab qiladi",
                      icon: Icons.warning_amber_rounded,
                      background: const Color(0x29F0B24A),
                      foreground: HkColors.warningBright,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: HkSpace.gridGapWide),
              HkTable(
                showHeader: layout.isExpanded,
                columns: const [
                  HkColumn('Talaba', 5),
                  HkColumn('Guruh', 4),
                  HkColumn('Davomat', 3),
                  HkColumn("O'zlashtirish", 3),
                  HkColumn('Oxirgi faollik', 4),
                  HkColumn('Holat', 3),
                ],
                rows: [
                  for (final s in shown)
                    _StudentRow(
                      student: s,
                      expanded: layout.isExpanded,
                      now: now,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.expanded,
    required this.now,
  });

  final TeacherStudent student;
  final bool expanded;
  final DateTime now;

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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Davomat',
                        value: s.attendance,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _Metric(
                        label: "O'zlashtirish",
                        value: s.progress,
                      ),
                    ),
                    const SizedBox(width: 12),
                    HkPill(
                      label: s.statusLabel,
                      background: s.statusBackground,
                      foreground: s.statusColor,
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
            s.groupName ?? '—',
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
          child: HkRateCell(
            value: s.progress,
            color: hkRateColor(s.progress),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            hkRelative(s.lastSeenAt, now: now),
            style: HkType.muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: HkPill(
              label: s.statusLabel,
              background: s.statusBackground,
              foreground: s.statusColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: HkType.muted.copyWith(fontSize: 11)),
        const SizedBox(height: 4),
        HkRateCell(value: value, color: hkRateColor(value)),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

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
            gradient: widget.active ? kLimeGradient : null,
            color: widget.active
                ? null
                : (_hovered ? HkGlass.hoverFill : const Color(0x0FFFFFFF)),
            borderRadius: BorderRadius.circular(HkRadius.pill),
            border: Border.all(
              color: widget.active ? Colors.transparent : HkGlass.border,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: HkType.family,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: widget.active ? HkColors.ink : HkColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
