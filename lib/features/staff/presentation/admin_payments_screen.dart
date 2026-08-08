import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 moved StateProvider out of the main barrel; the month here is a
// single value driven by two arrows, which is what it is for.
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';

import '../../../core/clock.dart';
import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/data_table.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/staff_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff_models.dart';
import 'payment_dialog.dart';

/// The month the screen is showing. Payments are monthly, so the month is the
/// unit of work — not a date range nobody would think in.
final paymentMonthProvider = StateProvider<DateTime>((ref) {
  final now = hkNow();
  return DateTime(now.year, now.month);
});

/// "To'lovlar" — the front desk's receipt book.
///
/// Every student for the chosen month, and whether their fee has come in. The
/// admin records what a student hands over; they do not see what the academy
/// took in altogether. That total is the owner's, and it lives in Moliya —
/// `ol_admin_kpis` returns zero for it below the top tier, so the separation
/// is not just this screen declining to add the column up.
class AdminPaymentsScreen extends ConsumerWidget {
  const AdminPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final month = ref.watch(paymentMonthProvider);

    return AppShell(
      title: 'To‘lovlar',
      subtitle: 'Oylik to‘lovlarni qabul qilish',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MonthHeader(month: month),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(adminStudentsProvider),
            onRetry: () => ref.invalidate(adminStudentsProvider),
            loadingHeight: 280,
            isEmpty: (s) => s.isEmpty,
            emptyMessage: 'Hali talaba yo‘q',
            builder: (students) {
              final payments =
                  ref.watch(paymentsProvider).value ?? const <Payment>[];

              // Keyed by student, not searched per row: a hundred students
              // against a hundred payments is ten thousand comparisons for
              // something the map does once.
              final forMonth = {
                for (final p in payments)
                  if (p.period.year == month.year && p.period.month == month.month)
                    p.studentId: p,
              };

              return HkTable(
                showHeader: layout.isExpanded,
                columns: const [
                  HkColumn('Talaba', 5),
                  HkColumn('Guruh', 4),
                  HkColumn('Tarif', 3),
                  HkColumn('Summa', 3),
                  HkColumn('Holat', 3),
                  HkColumn('', 3),
                ],
                rows: [
                  for (final s in students)
                    _PaymentRow(
                      student: s,
                      payment: forMonth[s.studentId],
                      month: month,
                      expanded: layout.isExpanded,
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

class _MonthHeader extends ConsumerWidget {
  const _MonthHeader({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void step(int months) {
      ref.read(paymentMonthProvider.notifier).state =
          DateTime(month.year, month.month + months);
    }

    final now = hkNow();
    final isThisMonth = month.year == now.year && month.month == now.month;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GlassPanel(
          radius: HkRadius.pill,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => step(-1),
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                color: HkColors.textSecondary,
                tooltip: 'Oldingi oy',
              ),
              Text(
                DateFormat('LLLL y', 'uz').format(month),
                style: HkType.label,
              ),
              IconButton(
                onPressed: () => step(1),
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                color: HkColors.textSecondary,
                tooltip: 'Keyingi oy',
              ),
            ],
          ),
        ),
        if (!isThisMonth)
          TextButton(
            onPressed: () => ref.read(paymentMonthProvider.notifier).state =
                DateTime(now.year, now.month),
            style: TextButton.styleFrom(foregroundColor: HkColors.lime),
            child: const Text('Shu oyga qaytish'),
          ),
        Text(
          'To‘lovni qabul qilganingizda shu yerga yoziladi. Umumiy tushum '
          'hisoboti super adminda.',
          style: HkType.muted,
        ),
      ],
    );
  }
}

class _PaymentRow extends ConsumerStatefulWidget {
  const _PaymentRow({
    required this.student,
    required this.payment,
    required this.month,
    required this.expanded,
  });

  final AdminStudent student;
  final Payment? payment;
  final DateTime month;
  final bool expanded;

  @override
  ConsumerState<_PaymentRow> createState() => _PaymentRowState();
}

class _PaymentRowState extends ConsumerState<_PaymentRow> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(paymentsProvider);
    ref.invalidate(adminStudentsProvider);
  }

  Future<void> _record() async {
    final saved = await showPaymentDialog(
      context,
      studentId: widget.student.studentId,
      studentName: widget.student.fullName,
      period: widget.month,
      existing: widget.payment,
    );
    if (saved == true) _refresh();
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(staffRepositoryProvider)
          .confirmPayment(widget.payment!.id);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final p = widget.payment;
    final paid = p?.status == PaymentStatus.confirmed;

    final statusPill = p == null
        ? const HkPill(
            label: 'To‘lanmagan',
            background: Color(0x14FFFFFF),
            foreground: HkColors.textSecondary,
          )
        : HkPill(
            label: p.status.label,
            background: p.status.background,
            foreground: p.status.color,
          );

    final action = _busy
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : paid
            // Paid is not the end of it — an amount typed wrongly has to be
            // fixable, and fixing it is an edit, which leaves the row behind.
            ? TextButton.icon(
                onPressed: _record,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('To‘g‘rilash'),
                style: TextButton.styleFrom(
                  foregroundColor: HkColors.textTertiary,
                ),
              )
            : p == null
                ? SizedBox(
                    height: 38,
                    child: FilledButton(
                      onPressed: _record,
                      style: FilledButton.styleFrom(
                        backgroundColor: HkColors.royalBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(HkRadius.control),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text(
                        'Qabul qilish',
                        style: TextStyle(
                          fontFamily: HkType.family,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  )
                : LimeButton(
                    label: 'Tasdiqlash',
                    height: 38,
                    onPressed: _confirm,
                  );

    final amount = p == null
        ? Text('—', style: HkType.muted)
        : Text(
            hkSum(p.amount),
            style: HkType.label.copyWith(
              fontSize: 12.5,
              color: paid ? HkColors.successBright : HkColors.textPrimary,
            ),
          );

    if (!widget.expanded) {
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
                  subtitle: s.groupName ?? 'Guruhsiz',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    statusPill,
                    const SizedBox(width: 10),
                    amount,
                    const Spacer(),
                    action,
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
          child: Text(
            p?.planName ?? '—',
            style: HkType.body.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(flex: 3, child: amount),
        Expanded(
          flex: 3,
          child: Align(alignment: Alignment.centerLeft, child: statusPill),
        ),
        Expanded(
          flex: 3,
          child: Align(alignment: Alignment.centerRight, child: action),
        ),
      ],
    );
  }
}
