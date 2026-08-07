import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';

/// Shows a freshly issued login and password.
///
/// This is the only moment the password is ever readable — nothing stores it
/// in a recoverable form — so the dialog is deliberately awkward to dismiss by
/// accident: no barrier dismiss, no back button, one explicit button that
/// says the admin has written it down.
Future<void> showPasswordResultDialog(
  BuildContext context, {
  required String title,
  required String username,
  required String fullName,
  required String password,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xCC000000),
    builder: (_) => PopScope(
      canPop: false,
      child: _PasswordResultDialog(
        title: title,
        username: username,
        fullName: fullName,
        password: password,
      ),
    ),
  );
}

class _PasswordResultDialog extends StatefulWidget {
  const _PasswordResultDialog({
    required this.title,
    required this.username,
    required this.fullName,
    required this.password,
  });

  final String title;
  final String username;
  final String fullName;
  final String password;

  @override
  State<_PasswordResultDialog> createState() => _PasswordResultDialogState();
}

class _PasswordResultDialogState extends State<_PasswordResultDialog> {
  bool _copied = false;

  /// One block covering both fields. An admin passing these on by phone or
  /// messenger wants them together, and copying twice loses the pairing.
  String get _shareText =>
      '${widget.fullName}\nLogin: ${widget.username}\nParol: ${widget.password}';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(24),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0x26D4E94C),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.vpn_key_rounded,
                      size: 18,
                      color: HkColors.lime,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: HkType.pageTitle.copyWith(fontSize: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(widget.fullName, style: HkType.cardTitle),
              const SizedBox(height: 14),
              _Credential(label: 'Login', value: widget.username),
              const SizedBox(height: 10),
              _Credential(label: 'Parol', value: widget.password, mono: true),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0x1AE08600),
                  borderRadius: BorderRadius.circular(HkRadius.cardSmall),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 17,
                      color: HkColors.warningBright,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bu parol boshqa ko‘rsatilmaydi. Hozir nusxalab '
                        'oling. Talaba birinchi kirganda o‘z parolini '
                        'qo‘yishi so‘raladi.',
                        style: HkType.body.copyWith(
                          fontSize: 12.5,
                          color: HkColors.warningBright,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _shareText));
                    if (!mounted) return;
                    setState(() => _copied = true);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: HkGlass.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HkRadius.control),
                    ),
                  ),
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 17,
                    color: _copied ? HkColors.lime : HkColors.textPrimary,
                  ),
                  label: Text(
                    _copied ? 'Nusxalandi' : 'Login va parolni nusxalash',
                    style: TextStyle(
                      fontFamily: HkType.family,
                      fontWeight: FontWeight.w600,
                      color: _copied ? HkColors.lime : HkColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              LimeButton(
                label: 'Yozib oldim',
                expand: true,
                height: 46,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Credential extends StatelessWidget {
  const _Credential({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        border: Border.all(color: HkGlass.border),
      ),
      child: Row(
        children: [
          SizedBox(width: 58, child: Text(label, style: HkType.muted)),
          Expanded(
            child: SelectableText(
              value,
              style: mono
                  ? HkType.monoTime.copyWith(fontSize: 16)
                  : HkType.cardTitle.copyWith(fontSize: 15),
            ),
          ),
          IconButton(
            tooltip: 'Nusxalash',
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            icon: const Icon(
              Icons.copy_rounded,
              size: 16,
              color: HkColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
