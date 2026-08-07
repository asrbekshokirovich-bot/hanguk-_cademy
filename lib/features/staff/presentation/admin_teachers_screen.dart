import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/data_table.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/stat_card.dart';
import '../../../design_system/widgets/states.dart';
import '../data/staff_providers.dart';
import '../domain/staff_models.dart';

/// "O'qituvchilar" — the teaching staff, their load and their groups.
///
/// Load is the column this screen exists for: an academy discovers it has
/// overbooked one teacher and left another idle by looking at this, not by
/// reading a schedule week by week.
class AdminTeachersScreen extends ConsumerWidget {
  const AdminTeachersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);

    return AppShell(
      title: 'O‘qituvchilar',
      subtitle: 'Yuklama va guruhlar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Yuklama shu haftadagi darslar soniga qarab hisoblanadi. Yangi '
            'o‘qituvchi hisobi “Talabalar” bo‘limidagi hisob oynasidan, rol '
            'sifatida “O‘qituvchi” tanlab ochiladi.',
            style: HkType.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(teacherRosterProvider),
            onRetry: () => ref.invalidate(teacherRosterProvider),
            loadingHeight: 260,
            isEmpty: (t) => t.isEmpty,
            emptyMessage: 'Hali o‘qituvchi yo‘q',
            builder: (teachers) {
              final totalLessons = teachers.fold<int>(
                0,
                (a, t) => a + t.weeklyLessons,
              );
              final averageLoad = teachers.isEmpty
                  ? 0.0
                  : teachers.fold<double>(0, (a, t) => a + t.load) /
                        teachers.length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HkStatRow(
                    cards: [
                      HkStatCard(
                        label: 'O‘qituvchilar',
                        value: '${teachers.length}',
                        icon: Icons.school_rounded,
                        note: 'Ro‘yxatda',
                      ),
                      HkStatCard(
                        label: 'Haftalik darslar',
                        value: '$totalLessons',
                        icon: Icons.calendar_month_rounded,
                        note: 'Jami',
                      ),
                      HkStatCard(
                        label: "O'rtacha yuklama",
                        value: hkPercent(averageLoad),
                        icon: Icons.speed_rounded,
                        note: 'To‘liq hafta 16 darsdan',
                        highlight: true,
                      ),
                      HkStatCard(
                        label: 'Talabalar',
                        value:
                            '${teachers.fold<int>(0, (a, t) => a + t.studentCount)}',
                        icon: Icons.people_alt_rounded,
                        note: 'Guruhlarda',
                      ),
                    ],
                  ),
                  const SizedBox(height: HkSpace.gridGapWide),
                  HkTable(
                    showHeader: layout.isExpanded,
                    columns: const [
                      HkColumn('O‘qituvchi', 5),
                      HkColumn('Yo‘nalish', 4),
                      HkColumn('Darslar', 2),
                      HkColumn('Talabalar', 2),
                      HkColumn('Reyting', 2),
                      HkColumn('Yuklama', 4),
                      HkColumn('Holat', 3),
                    ],
                    rows: [
                      for (final t in teachers)
                        _TeacherRow(teacher: t, expanded: layout.isExpanded),
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

}

class _TeacherRow extends StatelessWidget {
  const _TeacherRow({required this.teacher, required this.expanded});

  final TeacherRosterEntry teacher;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final t = teacher;

    final rating = t.rating == null
        ? Text('—', style: HkType.muted)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.star_rounded,
                size: 14,
                color: HkColors.warningBright,
              ),
              const SizedBox(width: 4),
              Text(
                t.rating!.toStringAsFixed(1),
                style: HkType.label.copyWith(fontSize: 13),
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
                  name: t.fullName,
                  initials: t.initials,
                  gradient: t.gradient,
                  subtitle: t.subject,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Yuklama',
                            style: HkType.muted.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          HkRateCell(value: t.load, color: t.loadColor),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    rating,
                    const SizedBox(width: 12),
                    HkPill(
                      label: t.statusLabel,
                      background: t.statusBackground,
                      foreground: t.statusColor,
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
            name: t.fullName,
            initials: t.initials,
            gradient: t.gradient,
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            t.subject ?? '—',
            style: HkType.body.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text('${t.weeklyLessons}', style: HkType.label),
        ),
        Expanded(
          flex: 2,
          child: Text('${t.studentCount}', style: HkType.label),
        ),
        Expanded(flex: 2, child: rating),
        Expanded(
          flex: 4,
          child: HkRateCell(value: t.load, color: t.loadColor),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: HkPill(
              label: t.statusLabel,
              background: t.statusBackground,
              foreground: t.statusColor,
            ),
          ),
        ),
      ],
    );
  }
}
