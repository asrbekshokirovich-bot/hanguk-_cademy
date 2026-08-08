import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/dropdown_field.dart';
import '../../../design_system/widgets/glass.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../data/staff_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff_models.dart';

/// Records one student's fee for one month.
///
/// Nothing here moves money — it is a receipt book. Cash or a bank transfer
/// arrives, and whoever took it writes down what came in and when. That is
/// also why "Tasdiqlandi" and the date are one switch and not two fields: a
/// confirmation with no date cannot be reconciled against a statement later,
/// so the date is written for you.
Future<bool?> showPaymentDialog(
  BuildContext context, {
  required String studentId,
  required String studentName,
  required DateTime period,
  Payment? existing,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _PaymentDialog(
      studentId: studentId,
      studentName: studentName,
      period: period,
      existing: existing,
    ),
  );
}

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog({
    required this.studentId,
    required this.studentName,
    required this.period,
    this.existing,
  });

  final String studentId;
  final String studentName;
  final DateTime period;
  final Payment? existing;

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.amount}',
  );

  late String? _planCode = widget.existing?.planCode;
  late bool _confirmed =
      widget.existing?.status == PaymentStatus.confirmed || widget.existing == null;
  bool _busy = false;
  String? _error;

  /// True once the cashier types over the tariff's figure. A student paying
  /// half now and half later is ordinary here, so the plan proposes an amount
  /// rather than dictating one — but it must stop proposing after that.
  bool _amountEdited = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _selectPlan(String? code, List<PaymentPlan> plans) {
    setState(() => _planCode = code);
    if (_amountEdited) return;
    final plan = plans.where((p) => p.code == code).firstOrNull;
    if (plan == null) return;
    _amount.text = '${plan.monthlyAmount}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(staffRepositoryProvider).recordPayment(
            studentId: widget.studentId,
            planCode: _planCode!,
            amount: int.parse(_amount.text.replaceAll(' ', '')),
            period: widget.period,
            confirmed: _confirmed,
          );
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
    final plans = ref.watch(plansProvider).value ?? const <PaymentPlan>[];
    final month = DateFormat('LLLL y', 'uz').format(widget.period);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(24),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'To‘lovni qabul qilish',
                          style: HkType.pageTitle,
                        ),
                      ),
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
                  const SizedBox(height: 6),
                  Text(widget.studentName, style: HkType.cardTitle),
                  const SizedBox(height: 2),
                  Text('$month uchun', style: HkType.muted),
                  const SizedBox(height: 20),
                  HkDropdownField<String?>(
                    value:
                        plans.any((p) => p.code == _planCode) ? _planCode : null,
                    label: 'Tarif',
                    icon: Icons.sell_outlined,
                    helperText: plans.isEmpty
                        ? 'Tarif yo‘q — super admin qo‘shishi kerak'
                        : null,
                    items: [
                      for (final p in plans)
                        DropdownMenuItem(
                          value: p.code,
                          child: Text('${p.name} · ${hkSum(p.monthlyAmount)}'),
                        ),
                    ],
                    onChanged: (v) => _selectPlan(v, plans),
                    validator: (v) => v == null ? 'Tarifni tanlang' : null,
                  ),
                  const SizedBox(height: 14),
                  AuthField(
                    controller: _amount,
                    label: 'Qabul qilingan summa (so‘m)',
                    icon: Icons.payments_outlined,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    helperText: 'Tarifdan farq qilsa, o‘zgartiring',
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                      TextInputFormatter.withFunction((prev, next) {
                        if (next.text != prev.text) _amountEdited = true;
                        return next;
                      }),
                    ],
                    onSubmitted: (_) => _save(),
                    validator: (v) {
                      final value = int.tryParse((v ?? '').trim());
                      if (value == null) return 'Summani kiriting';
                      if (value <= 0) return 'Summa noldan katta bo‘lsin';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pul qo‘lga tegdi',
                                style: HkType.label),
                            const SizedBox(height: 2),
                            Text(
                              _confirmed
                                  ? 'Tasdiqlangan deb yoziladi, sana bilan'
                                  : 'Kutilmoqda deb qoladi',
                              style: HkType.muted,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _confirmed,
                        onChanged: (v) => setState(() => _confirmed = v),
                        activeThumbColor: HkColors.ink,
                        activeTrackColor: HkColors.lime,
                        inactiveThumbColor: HkColors.textTertiary,
                        inactiveTrackColor: const Color(0x14FFFFFF),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style:
                          HkType.muted.copyWith(color: HkColors.dangerBright),
                    ),
                  ],
                  const SizedBox(height: 20),
                  LimeButton(
                    label: _busy ? 'Saqlanmoqda…' : 'Saqlash',
                    expand: true,
                    onPressed: _busy ? null : _save,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Bir oy uchun bitta yozuv saqlanadi — takror kiritilsa, '
                    'avvalgisi yangilanadi.',
                    style: HkType.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
