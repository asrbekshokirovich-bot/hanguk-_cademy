import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import 'glass.dart';

/// The stat card used on all three dashboards.
///
/// Extracted when the teacher and admin panels arrived: three near-identical
/// copies had already started to drift apart in padding and type size, which
/// is exactly the thing a design system exists to prevent.
class HkStatCard extends StatelessWidget {
  const HkStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.note,
    this.highlight = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? note;

  /// Lime tint and border. Reserved for the one number on a screen that the
  /// reader is meant to land on first; two highlighted cards highlight
  /// nothing.
  final bool highlight;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      tint: highlight ? const Color(0x1AD4E94C) : null,
      borderColor: highlight ? const Color(0x3DD4E94C) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: HkType.body.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: highlight
                      ? const Color(0x33D4E94C)
                      : const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: highlight ? HkColors.lime : HkColors.textSecondary,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: HkType.display.copyWith(
                color: valueColor ??
                    (highlight ? HkColors.lime : HkColors.textPrimary),
              ),
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: HkType.muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// A row of stat cards that reflows with the window.
class HkStatRow extends StatelessWidget {
  const HkStatRow({super.key, required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final layout = HkLayout.of(context);
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // A fixed height on compact rather than a ratio. A ratio ties the tile's
      // height to the phone's width, and the tile's contents — a label, a
      // number in the display face, a note — do not get shorter on a narrower
      // phone. At 1.45 a 390pt screen gave them 118pt for 135pt of text.
      gridDelegate: layout.isCompact
          ? const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: HkSpace.gridGap,
              crossAxisSpacing: HkSpace.gridGap,
              mainAxisExtent: 140,
            )
          : SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.statColumns,
              mainAxisSpacing: HkSpace.gridGap,
              crossAxisSpacing: HkSpace.gridGap,
              childAspectRatio: 1.75,
            ),
      children: cards,
    );
  }
}

/// A simple vertical bar chart — the "Haftalik yuklama" and "So'nggi 8 hafta"
/// panels. Values are 0..1.
class HkBarChart extends StatelessWidget {
  const HkBarChart({
    super.key,
    required this.bars,
    this.height = 150,
    this.highlightLast = 2,
  });

  final List<({String label, double value})> bars;
  final double height;

  /// How many trailing bars take the accent. The design uses it to draw the
  /// eye to the current period without a legend.
  final int highlightLast;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text("Ma'lumot yo'q", style: HkType.muted),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: bars[i].value.clamp(0.02, 1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: i >= bars.length - highlightLast
                                ? (i == bars.length - 1
                                    ? HkColors.lime
                                    : HkColors.lime600)
                                : const Color(0x806FA0E0),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bars[i].label,
                      style: HkType.muted.copyWith(fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
