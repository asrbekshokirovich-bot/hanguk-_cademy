import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';

/// A line of explanation with the screen's main action beside it.
///
/// Side by side on a desktop, stacked on a phone with the button spanning the
/// width. Written once because every admin screen has this pair, and every one
/// of them squeezed the button into a sliver on a 390pt screen when it was a
/// plain Row.
///
/// The action deliberately sits here rather than inside the screen's
/// `AsyncSection`: an empty roster must not hide the only way to fill it.
class HkSectionIntro extends StatelessWidget {
  const HkSectionIntro({super.key, required this.text, this.action});

  final String text;

  /// Give it an intrinsic height of 44; it is stretched to full width on
  /// compact and left at its natural width otherwise.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final layout = HkLayout.of(context);
    final label = Text(text, style: HkType.body.copyWith(fontSize: 13));

    if (action == null) return label;

    if (layout.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const SizedBox(height: 14),
          SizedBox(height: 44, child: action),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: label),
        const SizedBox(width: 16),
        SizedBox(height: 44, child: action),
      ],
    );
  }
}
