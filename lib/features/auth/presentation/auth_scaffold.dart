import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';

/// Shared chrome for the sign-in and change-password screens.
///
/// The handoff has no design for either — its prototype starts already signed
/// in — so both are assembled from the same primitives as the rest of the app
/// rather than inventing a second visual language for the two screens a user
/// sees first.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = HkLayout.of(context).isCompact;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassPanel(
            radius: HkRadius.cardLarge,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/images/hanguk-mark.png',
                        width: 44,
                        height: 44,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Expanded, not bare: the wordmark is wider than the
                    // panel's inner width once the mark and gap are taken
                    // out, and an unconstrained Column in a Row overflows
                    // rather than wrapping.
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hanguk Academy',
                            style: TextStyle(
                              fontFamily: HkType.family,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: HkColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Onlayn ta'lim platformasi",
                            style: TextStyle(
                              fontFamily: HkType.family,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0x80FFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Text(title, style: HkType.pageTitle.copyWith(fontSize: 21)),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.suffix,
    this.onSubmitted,
    this.autofillHints,
    this.inputFormatters,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(HkRadius.control)),
      borderSide: BorderSide(color: HkGlass.border),
    );

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      style: HkType.body.copyWith(fontSize: 14.5, color: HkColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: HkType.body.copyWith(fontSize: 13.5),
        helperText: helperText,
        helperStyle: HkType.muted.copyWith(fontSize: 11.5),
        helperMaxLines: 2,
        prefixIcon: Icon(icon, size: 18, color: HkColors.textTertiary),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0x0FFFFFFF),
        border: border,
        enabledBorder: border,
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(HkRadius.control)),
          borderSide: BorderSide(color: HkColors.lime),
        ),
        errorStyle: HkType.muted.copyWith(
          fontSize: 11.5,
          color: HkColors.dangerBright,
        ),
      ),
    );
  }
}

class ObscureToggle extends StatelessWidget {
  const ObscureToggle({
    super.key,
    required this.obscured,
    required this.onChanged,
  });

  final bool obscured;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: obscured ? "Ko'rsatish" : 'Yashirish',
      onPressed: () => onChanged(!obscured),
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 18,
        color: HkColors.textTertiary,
      ),
    );
  }
}

class AuthBanner extends StatelessWidget {
  const AuthBanner({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String text;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: HkType.body.copyWith(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: busy
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: HkColors.lime,
                ),
              ),
            )
          : LimeButton(label: label, expand: true, onPressed: onPressed),
    );
  }
}
