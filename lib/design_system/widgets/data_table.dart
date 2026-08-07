import 'package:flutter/material.dart';

import '../tokens.dart';
import 'glass.dart';

/// A column in an [HkTable].
class HkColumn {
  const HkColumn(this.label, this.flex);

  final String label;
  final int flex;
}

/// The glass table shared by every roster in the staff panels.
///
/// It is deliberately not Material's `DataTable`: that widget brings its own
/// dividers, hover colours and row heights, all of which would have to be
/// overridden back out to match the design, and it does not collapse to the
/// stacked card layout phones need.
class HkTable extends StatelessWidget {
  const HkTable({
    super.key,
    required this.columns,
    required this.rows,
    this.showHeader = true,
    this.trailingWidth = 0,
  });

  final List<HkColumn> columns;
  final List<Widget> rows;

  /// Off on narrow layouts, where each row becomes a card and column headings
  /// would label nothing.
  final bool showHeader;

  /// Space reserved on the right for a per-row action button.
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: HkRadius.cardLarge,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  for (final c in columns)
                    Expanded(
                      flex: c.flex,
                      child: Text(c.label, style: HkType.muted),
                    ),
                  if (trailingWidth > 0) SizedBox(width: trailingWidth),
                ],
              ),
            ),
          ...rows,
        ],
      ),
    );
  }
}

/// One row, with the design's hover lift.
class HkTableRow extends StatefulWidget {
  const HkTableRow({
    super.key,
    required this.children,
    this.onTap,
    this.tint,
    this.padding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  });

  final List<Widget> children;
  final VoidCallback? onTap;

  /// Used for the live row and anything else the design tints.
  final Color? tint;
  final EdgeInsetsGeometry padding;

  @override
  State<HkTableRow> createState() => _HkTableRowState();
}

class _HkTableRowState extends State<HkTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: 4),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.tint ??
            (_hovered ? HkGlass.hoverFill : Colors.transparent),
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
      ),
      child: Row(children: widget.children),
    );

    if (widget.onTap == null) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: row,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(onTap: widget.onTap, child: row),
    );
  }
}

/// Name + initials avatar, the leading cell of nearly every roster row.
class HkPersonCell extends StatelessWidget {
  const HkPersonCell({
    super.key,
    required this.name,
    required this.initials,
    this.gradient,
    this.subtitle,
    this.size = 34,
  });

  final String name;
  final String initials;
  final Gradient? gradient;
  final String? subtitle;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        HkAvatar(initials: initials, size: size, gradient: gradient),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: HkType.cardTitle.copyWith(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: HkType.muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A percentage with the shared threshold colour and a thin bar under it.
class HkRateCell extends StatelessWidget {
  const HkRateCell({
    super.key,
    required this.value,
    required this.color,
    this.showBar = true,
  });

  final double value;
  final Color color;
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${(value * 100).round()}%',
          style: HkType.label.copyWith(fontSize: 13, color: color),
        ),
        if (showBar) ...[
          const SizedBox(height: 5),
          HkProgressBar(value: value, color: color, height: 3),
        ],
      ],
    );
  }
}
