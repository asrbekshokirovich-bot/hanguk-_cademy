import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 moved StateProvider out of the main barrel; the filter here is
// a single value driven by a tap, which is what it is for.
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/data_table.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/stat_card.dart';
import '../../../design_system/widgets/states.dart';
import '../data/staff_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff_models.dart';

final financeFilterProvider = StateProvider<PaymentStatus?>((ref) => null);

/// "Moliya" — monthly fees.
///
/// Deliberately a ledger, not a payment gateway. Money arrives in cash or by
/// bank transfer and someone in the office records it here; nothing in this
/// app moves funds. That boundary is why "Tasdiqlash" writes a timestamp
/// alongside the status — a confirmation with no date cannot be reconciled
/// against a bank statement later.
class AdminFinanceScreen extends ConsumerWidget {
  const AdminFinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final filter = ref.watch(financeFilterProvider);

    return AppShell(
      title: 'Moliya',
      subtitle: 'To‘lovlar va tariflar',
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
                  label: 'Bu oygi tushum',
                  value: hkSumShort(k.monthRevenue),
                  icon: Icons.payments_rounded,
                  note: 'UZS · tasdiqlangan',
                  highlight: true,
                ),
                HkStatCard(
                  label: 'Kutilayotgan to‘lovlar',
                  value: hkSumShort(k.outstandingAmount),
                  icon: Icons.hourglass_bottom_rounded,
                  note: 'UZS · yig‘ilmagan',
                  valueColor: k.outstandingAmount > 0
                      ? HkColors.warningBright
                      : HkColors.textPrimary,
                ),
                HkStatCard(
                  label: 'Kechikkanlar',
                  value: '${k.outstandingCount}',
                  icon: Icons.warning_amber_rounded,
                  note: 'Muddati o‘tgan',
                  valueColor: k.outstandingCount > 0
                      ? HkColors.dangerBright
                      : HkColors.textPrimary,
                ),
                HkStatCard(
                  label: 'Faol talabalar',
                  value: '${k.activeStudents}',
                  icon: Icons.people_alt_rounded,
                  note: 'To‘lov kutilayotganlar',
                ),
              ],
            ),
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          const _PlansStrip(),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(paymentsProvider),
            onRetry: () => ref.invalidate(paymentsProvider),
            loadingHeight: 240,
            isEmpty: (p) => p.isEmpty,
            emptyMessage: 'Hali to‘lov qayd etilmagan',
            builder: (payments) {
              final shown = filter == null
                  ? payments
                  : payments.where((p) => p.status == filter).toList();

              int countOf(PaymentStatus s) =>
                  payments.where((p) => p.status == s).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _Chip(
                        label: 'Barchasi · ${payments.length}',
                        active: filter == null,
                        onTap: () => ref
                            .read(financeFilterProvider.notifier)
                            .state = null,
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
                            onTap: () => ref
                                .read(financeFilterProvider.notifier)
                                .state = s,
                          ),
                    ],
                  ),
                  const SizedBox(height: HkSpace.gridGapWide),
                  HkTable(
                    showHeader: layout.isExpanded,
                    trailingWidth: 130,
                    columns: const [
                      HkColumn('Talaba', 5),
                      HkColumn('Reja', 3),
                      HkColumn('Summa', 4),
                      HkColumn('Sana', 3),
                      HkColumn('Holat', 3),
                    ],
                    rows: [
                      for (final p in shown)
                        _PaymentRow(
                          payment: p,
                          expanded: layout.isExpanded,
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

class _PlansStrip extends ConsumerWidget {
  const _PlansStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider).value ?? const <PaymentPlan>[];
    if (plans.isEmpty) return const SizedBox.shrink();

    return GlassPanel(
      radius: HkRadius.cardLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tariflar', style: HkType.sectionTitle),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final p in plans)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x0FFFFFFF),
                    borderRadius: BorderRadius.circular(HkRadius.cardSmall),
                    border: Border.all(color: HkGlass.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.name, style: HkType.cardTitle),
                      const SizedBox(height: 4),
                      Text(
                        '${hkSum(p.monthlyAmount)} / oy',
                        style: HkType.monoTime.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends ConsumerStatefulWidget {
  const _PaymentRow({required this.payment, required this.expanded});

  final Payment payment;
  final bool expanded;

  @override
  ConsumerState<_PaymentRow> createState() => _PaymentRowState();
}

class _PaymentRowState extends ConsumerState<_PaymentRow> {
  bool _busy = false;

  Future<void> _confirm() async {
    final p = widget.payment;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HkColors.royalBlue800,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HkRadius.card),
        ),
        title: const Text('To‘lovni tasdiqlash', style: HkType.sectionTitle),
        content: Text(
          '${p.studentName} · ${hkSum(p.amount)}\n\n'
          'To‘lov qabul qilingan deb belgilanadi va bugungi sana '
          'yoziladi.',
          style: HkType.body.copyWith(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Bekor qilish', style: HkType.muted),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: HkColors.success,
            ),
            child: Text('Tasdiqlash', style: HkType.label),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(staffRepositoryProvider).confirmPayment(p.id);
      ref.invalidate(paymentsProvider);
      ref.invalidate(adminKpisProvider);
      ref.invalidate(adminStudentsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget get _action {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: HkColors.lime,
          ),
        ),
      );
    }
    if (widget.payment.status == PaymentStatus.confirmed) {
      return const Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: HkColors.successBright,
      );
    }
    return SizedBox(
      height: 36,
      child: LimeButton(
        label: 'Tasdiqlash',
        height: 36,
        onPressed: _confirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final date = p.paidAt ?? p.dueDate ?? p.period;
    final dateLabel = DateFormat('d-MMMM', 'uz').format(date);

    if (!widget.expanded) {
      return HkTableRow(
        padding: const EdgeInsets.all(14),
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HkPersonCell(
                  name: p.studentName,
                  initials: p.initials,
                  gradient: p.gradient,
                  subtitle: p.planName,
                ),
                const SizedBox(height: 10),
                Text(hkSum(p.amount), style: HkType.monoTime),
                const SizedBox(height: 10),
                Row(
                  children: [
                    HkPill(
                      label: p.status.label,
                      background: p.status.background,
                      foreground: p.status.color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(dateLabel, style: HkType.muted)),
                    _action,
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
            name: p.studentName,
            initials: p.initials,
            gradient: p.gradient,
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            p.planName ?? '—',
            style: HkType.body.copyWith(fontSize: 13),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            hkSum(p.amount),
            style: HkType.monoTime.copyWith(fontSize: 13),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(dateLabel, style: HkType.muted),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: HkPill(
              label: p.status.label,
              background: p.status.background,
              foreground: p.status.color,
            ),
          ),
        ),
        SizedBox(width: 130, child: Align(child: _action)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: active && accent == null ? kLimeGradient : null,
            color: active
                ? accent?.withValues(alpha: 0.22)
                : const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(HkRadius.pill),
            border: Border.all(
              color: active ? (accent ?? Colors.transparent) : HkGlass.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: HkType.family,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? (accent ?? HkColors.ink) : HkColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
