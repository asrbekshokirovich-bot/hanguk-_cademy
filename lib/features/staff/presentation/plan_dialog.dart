import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens.dart';
import '../../auth/presentation/auth_scaffold.dart';
import '../../../design_system/widgets/glass.dart';
import '../data/staff_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff_models.dart';

/// Adds or edits a tariff.
///
/// Tariffs were readable everywhere and writable nowhere: the payment dialog
/// even told the cashier "Tarif yo'q — super admin qo'shishi kerak", and the
/// super admin had no way to add one short of SQL.
///
/// Super admin only, which is where money lives. RLS on `ol_plans` enforces
/// it; this dialog is only reachable from Moliya, which is already gated.
Future<bool?> showPlanDialog(BuildContext context, {PaymentPlan? plan}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (_) => _PlanDialog(plan: plan),
  );
}

class _PlanDialog extends ConsumerStatefulWidget {
  const _PlanDialog({this.plan});

  final PaymentPlan? plan;

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.plan == null ? '' : '${widget.plan!.monthlyAmount}',
  );

  bool _saving = false;
  String? _error;

  bool get _isNew => widget.plan == null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// A stable key derived from the name, once. Payments reference the code,
  /// so renaming a tariff must not change it.
  String _codeFor(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
        .replaceAll(RegExp(r'(^-|-$)'), '');
    return slug.isEmpty ? 'tarif-${DateTime.now().microsecondsSinceEpoch}' : slug;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = int.tryParse(_amount.text.trim().replaceAll(' ', ''));

    if (name.isEmpty) {
      setState(() => _error = 'Nomini yozing');
      return;
    }
    if (amount == null || amount < 0) {
      setState(() => _error = 'Summani raqam bilan yozing');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(staffRepositoryProvider).savePlan(
            code: widget.plan?.code ?? _codeFor(name),
            name: name,
            monthlyAmount: amount,
          );
      ref.invalidate(plansProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      await ref.read(staffRepositoryProvider).deletePlan(widget.plan!.code);
      ref.invalidate(plansProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(22),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isNew ? 'Yangi tarif' : 'Tarifni tahrirlash',
                      style: HkType.sectionTitle,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yopish',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: HkColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _name,
                label: 'Nomi',
                icon: Icons.sell_outlined,
                helperText: 'Masalan: Standard',
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _amount,
                label: 'Oylik summa (so‘m)',
                icon: Icons.payments_outlined,
                helperText: 'Masalan: 5000000',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: HkType.body.copyWith(
                    fontSize: 12.5,
                    color: HkColors.dangerBright,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  if (!_isNew)
                    TextButton(
                      onPressed: _saving ? null : _delete,
                      style: TextButton.styleFrom(
                        foregroundColor: HkColors.dangerBright,
                      ),
                      child: const Text('O‘chirish'),
                    ),
                  const Spacer(),
                  LimeButton(
                    label: _saving ? 'Saqlanmoqda…' : 'Saqlash',
                    height: 44,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
