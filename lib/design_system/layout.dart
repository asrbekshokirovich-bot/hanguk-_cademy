import 'package:flutter/widgets.dart';

/// The design is authored for a 1440×920 desktop window, but the same code
/// ships to Android and iOS phones. Rather than sprinkle width checks
/// everywhere, screens ask for a [HkLayout] and branch on it once.
enum HkLayout {
  /// Phones. Single column, bottom navigation, no floating chrome.
  compact,

  /// Small laptops / tablets / a resized desktop window. Floating dock, but
  /// multi-column grids collapse to two.
  medium,

  /// The design's native size and up. Everything as drawn.
  expanded;

  bool get isCompact => this == HkLayout.compact;
  bool get isExpanded => this == HkLayout.expanded;

  static HkLayout of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 760) return HkLayout.compact;
    if (width < 1180) return HkLayout.medium;
    return HkLayout.expanded;
  }

  /// Columns for the recordings grid and the dashboard stat row.
  int get gridColumns => switch (this) {
        HkLayout.compact => 1,
        HkLayout.medium => 2,
        HkLayout.expanded => 3,
      };

  int get statColumns => switch (this) {
        HkLayout.compact => 2,
        HkLayout.medium => 2,
        HkLayout.expanded => 4,
      };

  /// Top padding that clears the floating chrome. On compact there is no
  /// floating chrome, so content starts right below a normal app bar.
  double get contentTopPadding => isCompact ? 16 : 150;

  double get contentHorizontalPadding => isCompact ? 16 : 30;
}
