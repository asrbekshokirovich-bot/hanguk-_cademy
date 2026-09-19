import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/data_table.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/section_intro.dart';
import '../../../design_system/widgets/stat_card.dart';
import '../../../design_system/widgets/states.dart';
import '../data/staff_providers.dart';
import '../domain/staff_models.dart';
import 'group_dialogs.dart';

/// "Guruhlar" — the classes, who teaches each one and how full it is.
///
/// Admin only, and it is the hinge of the whole panel: a group is what ties a
/// student to a teacher and a lesson to a roster. Everything else on the
/// admin side reads the answer this screen sets.
class AdminGroupsScreen extends ConsumerWidget {
  const AdminGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);

    Future<void> edit({StudyGroup? group}) async {
      final saved = await showGroupFormDialog(context, group: group);
      if (saved == true) {
        ref.invalidate(groupsProvider);
        ref.invalidate(adminStudentsProvider);
        ref.invalidate(teacherRosterProvider);
      }
    }

    return AppShell(
      title: 'Guruhlar',
      subtitle: 'Sinflar va ularning o‘qituvchilari',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HkSectionIntro(
            text: 'Talaba guruhga qo‘shilganda o‘sha guruhning o‘qituvchisiga '
                'biriktiriladi va guruhning kelgusi darslariga yoziladi. '
                'Guruhga dars qo‘yilmasa, talaba jadvalda hech narsa '
                'ko‘rmaydi — “Jadval” bo‘limida dars yarating va guruhni '
                'tanlang.',
            action: FilledButton.icon(
              onPressed: () => edit(),
              style: FilledButton.styleFrom(
                backgroundColor: HkColors.royalBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HkRadius.control),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Yangi guruh',
                style: TextStyle(
                  fontFamily: HkType.family,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(groupsProvider),
            onRetry: () => ref.invalidate(groupsProvider),
            loadingHeight: 260,
            isEmpty: (g) => g.isEmpty,
            emptyMessage:
                'Hali guruh yo‘q — “Yangi guruh” tugmasi bilan yarating',
            builder: (groups) {
              final members = groups.fold<int>(0, (a, g) => a + g.memberCount);
              // Null while it loads: an unknown count must not be drawn as
              // "no lessons", which is the one thing this column is for.
              final upcoming = ref.watch(upcomingLessonsByGroupProvider).value;
              // How many distinct people are teaching, not how many rows have
              // a teacher: one teacher with three groups is one teacher.
              final teaching = groups
                  .map((g) => g.teacherId)
                  .whereType<String>()
                  .toSet()
                  .length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HkStatRow(
                    cards: [
                      HkStatCard(
                        label: 'Guruhlar',
                        value: '${groups.length}',
                        icon: Icons.groups_2_rounded,
                        note: 'Jami',
                      ),
                      HkStatCard(
                        label: 'Talabalar',
                        value: '$members',
                        icon: Icons.people_alt_rounded,
                        note: 'Guruhlarga biriktirilgan',
                        highlight: true,
                      ),
                      HkStatCard(
                        label: 'O‘qituvchilar',
                        value: '$teaching',
                        icon: Icons.school_rounded,
                        note: 'Guruh yuritmoqda',
                      ),
                    ],
                  ),
                  const SizedBox(height: HkSpace.gridGapWide),
                  HkTable(
                    showHeader: layout.isExpanded,
                    columns: const [
                      HkColumn('Guruh', 5),
                      HkColumn("O'qituvchi", 5),
                      HkColumn('Daraja', 3),
                      HkColumn('Talabalar', 3),
                      HkColumn('Kelgusi darslar', 4),
                      HkColumn('', 1),
                    ],
                    rows: [
                      for (final g in groups)
                        _GroupRow(
                          group: g,
                          lessons: upcoming?[g.id] ?? 0,
                          lessonsKnown: upcoming != null,
                          expanded: layout.isExpanded,
                          onEdit: () => edit(group: g),
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
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.lessons,
    required this.lessonsKnown,
    required this.expanded,
    required this.onEdit,
  });

  final StudyGroup group;

  /// Lessons ahead of this group, and whether that has been counted yet.
  final int lessons;
  final bool lessonsKnown;

  final bool expanded;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final g = group;

    // The empty case is the one worth a badge: it is the reason a correctly
    // assigned student sees an empty week, and it is invisible everywhere
    // else in the panel.
    final schedule = !lessonsKnown
        ? Text('—', style: HkType.muted)
        : lessons == 0
            ? const Align(
                alignment: Alignment.centerLeft,
                child: HkPill(
                  label: 'Dars qo‘yilmagan',
                  background: Color(0x29F0B24A),
                  foreground: HkColors.warningBright,
                ),
              )
            : Text('$lessons ta', style: HkType.label);

    final level = g.level == null
        ? Text('—', style: HkType.muted)
        : Align(
            alignment: Alignment.centerLeft,
            child: HkPill(
              label: '${g.level}-daraja',
              background: const Color(0x2E6EA0E0),
              foreground: HkColors.infoText,
            ),
          );

    if (!expanded) {
      return HkTableRow(
        padding: const EdgeInsets.all(14),
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name, style: HkType.cardTitle.copyWith(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  g.teacherName ?? 'O‘qituvchi belgilanmagan',
                  style: HkType.muted,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    level,
                    const SizedBox(width: 12),
                    Text('${g.memberCount} ta talaba', style: HkType.muted),
                    const SizedBox(width: 12),
                    Flexible(child: schedule),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Tahrirlash',
                      onPressed: onEdit,
                      icon: const Icon(
                        Icons.edit_outlined,
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
          child: Text(
            g.name,
            style: HkType.cardTitle.copyWith(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 5,
          child: Text(
            g.teacherName ?? '—',
            style: HkType.body.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(flex: 3, child: level),
        Expanded(
          flex: 3,
          child: Text('${g.memberCount}', style: HkType.label),
        ),
        Expanded(flex: 4, child: schedule),
        Expanded(
          flex: 1,
          child: IconButton(
            tooltip: 'Tahrirlash',
            onPressed: onEdit,
            icon: const Icon(
              Icons.edit_outlined,
              size: 17,
              color: HkColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
