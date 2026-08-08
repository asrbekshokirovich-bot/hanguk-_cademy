import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/stat_card.dart';
import '../../../design_system/widgets/states.dart';
import '../../lessons/data/providers.dart';
import '../data/staff_providers.dart';
import '../domain/staff_models.dart';

/// "Boshqaruv" — the academy at a glance.
///
/// The alert panel is the part that earns its place: four KPIs tell you the
/// business is fine on average, and the alerts tell you which nine students
/// have not paid. Averages hide exactly the things an administrator is paid
/// to act on, so they sit side by side.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);

    return AppShell(
      title: 'Boshqaruv',
      subtitle: 'Akademiya ko‘rsatkichlari',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AsyncSection(
            value: ref.watch(adminKpisProvider),
            onRetry: () => ref.invalidate(adminKpisProvider),
            loadingHeight: 120,
            builder: (k) => HkStatRow(
              cards: [
                HkStatCard(
                  label: 'Faol talabalar',
                  value: '${k.activeStudents}',
                  icon: Icons.people_alt_rounded,
                  note: '${k.teacherCount} ta o‘qituvchi',
                ),
                HkStatCard(
                  label: 'Haftalik darslar',
                  value: '${k.weeklyLessons}',
                  icon: Icons.calendar_month_rounded,
                  note: 'Shu hafta rejalashtirilgan',
                ),
                HkStatCard(
                  label: "O'rtacha davomat",
                  value: hkPercent(k.averageAttendance),
                  icon: Icons.trending_up_rounded,
                  note: 'Barcha talabalar bo‘yicha',
                  highlight: true,
                ),
                // No money card. This screen belongs to the administrator,
                // and money belongs to the tier above — which never opens it.
                HkStatCard(
                  label: 'Guruhlar',
                  value: '${k.teacherCount}',
                  icon: Icons.school_rounded,
                  note: 'Faol o‘qituvchilar',
                ),
              ],
            ),
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          if (layout.isExpanded)
            IntrinsicHeight(
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _LiveNowCard()),
                  SizedBox(width: HkSpace.gridGapWide),
                  Expanded(flex: 2, child: _AlertsCard()),
                ],
              ),
            )
          else ...[
            const _LiveNowCard(),
            const SizedBox(height: HkSpace.gridGapWide),
            const _AlertsCard(),
          ],
        ],
      ),
    );
  }
}

class _LiveNowCard extends ConsumerWidget {
  const _LiveNowCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassPanel(
      radius: HkRadius.cardLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Hozir efirda', style: HkType.sectionTitle),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => context.go('/schedule'),
                  child: const Text(
                    'Jadval',
                    style: TextStyle(
                      fontFamily: HkType.family,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HkColors.lime,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AsyncSection(
            value: ref.watch(todaysLessonsProvider),
            onRetry: () => ref.invalidate(todaysLessonsProvider),
            isEmpty: (l) => l.isEmpty,
            emptyMessage: 'Bugun dars rejalashtirilmagan',
            builder: (lessons) => Column(
              children: [
                for (final l in lessons) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x0AFFFFFF),
                      borderRadius:
                          BorderRadius.circular(HkRadius.cardSmall),
                    ),
                    child: Row(
                      children: [
                        HkAvatar(
                          initials: l.teacher?.initials ?? '?',
                          size: 34,
                          gradient: l.teacher?.gradient,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.title,
                                style: HkType.cardTitle.copyWith(fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${l.teacher?.fullName ?? '—'} · '
                                '${l.enrolledCount} talaba',
                                style: HkType.muted,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        HkPill(
                          label: l.status.label,
                          background: l.status.pillBackground,
                          foreground: l.status.pillForeground,
                        ),
                      ],
                    ),
                  ),
                  if (l != lessons.last) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsCard extends ConsumerWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(adminStudentsProvider).value;

    // Derived from the same numbers the rest of the screen shows, rather than
    // stored: an alerts table would need a job to keep it true, and would be
    // silently stale the first time that job failed.
    final alerts = <_Alert>[
      // No payment alert: it pointed at /admin/finance, which nobody reading
      // this screen can open.
      if (students != null)
        ...(() {
          final inactive = students
              .where((s) =>
                  s.lastSeenAt == null ||
                  DateTime.now().difference(s.lastSeenAt!).inDays >= 14)
              .length;
          return inactive > 0
              ? [
                  _Alert(
                    title: '$inactive ta talaba 2 haftadan beri nofaol',
                    note: 'Bog‘lanish tavsiya etiladi',
                    icon: Icons.schedule_rounded,
                    color: HkColors.infoText,
                    route: '/admin/students',
                  ),
                ]
              : <_Alert>[];
        })(),
      if (students != null)
        ...(() {
          final lowAttendance =
              students.where((s) => s.attendance < 0.7).length;
          return lowAttendance > 0
              ? [
                  _Alert(
                    title: '$lowAttendance ta talabaning davomati past',
                    note: '70% dan kam · o‘qituvchi bilan gaplashish',
                    icon: Icons.warning_amber_rounded,
                    color: HkColors.dangerBright,
                    route: '/admin/students',
                  ),
                ]
              : <_Alert>[];
        })(),
    ];

    return GlassPanel(
      radius: HkRadius.cardLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("E'tibor talab qiladi", style: HkType.sectionTitle),
          const SizedBox(height: 16),
          if (alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 20,
                    color: HkColors.successBright,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Hozircha e‘tibor talab qiladigan narsa yo‘q',
                      style: HkType.body.copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final a in alerts) ...[
              _AlertRow(alert: a),
              if (a != alerts.last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _Alert {
  const _Alert({
    required this.title,
    required this.note,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String title;
  final String note;
  final IconData icon;
  final Color color;
  final String route;
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final _Alert alert;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(alert.route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: alert.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(HkRadius.cardSmall),
          ),
          child: Row(
            children: [
              Icon(alert.icon, size: 18, color: alert.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: HkType.cardTitle.copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      alert.note,
                      style: HkType.muted,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: HkColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
