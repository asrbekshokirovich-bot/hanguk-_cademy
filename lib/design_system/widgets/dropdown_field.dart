import 'package:flutter/material.dart';

import '../tokens.dart';

/// A select styled like [AuthField], so a form can mix typed and chosen values
/// without the two looking like they came from different apps.
///
/// The menu itself is opaque on purpose: a translucent popup over the ambient
/// orb background is unreadable, which the glass panels get away with only
/// because they are large.
class HkDropdownField<T> extends StatelessWidget {
  const HkDropdownField({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
    this.validator,
    this.helperText,
  });

  final T? value;
  final String label;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(HkRadius.control)),
      borderSide: BorderSide(color: HkGlass.border),
    );

    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      dropdownColor: const Color(0xFF101A33),
      borderRadius: BorderRadius.circular(HkRadius.cardSmall),
      icon: const Icon(
        Icons.expand_more_rounded,
        size: 20,
        color: HkColors.textTertiary,
      ),
      style: HkType.body.copyWith(fontSize: 14.5, color: HkColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: HkType.body.copyWith(fontSize: 13.5),
        helperText: helperText,
        helperStyle: HkType.muted.copyWith(fontSize: 11.5),
        helperMaxLines: 2,
        prefixIcon: Icon(icon, size: 18, color: HkColors.textTertiary),
        filled: true,
        fillColor: const Color(0x0FFFFFFF),
        border: border,
        enabledBorder: border,
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(HkRadius.control)),
          borderSide: BorderSide(color: HkColors.lime, width: 1.4),
        ),
        errorStyle: HkType.muted.copyWith(
          fontSize: 11.5,
          color: HkColors.dangerBright,
        ),
      ),
    );
  }
}
