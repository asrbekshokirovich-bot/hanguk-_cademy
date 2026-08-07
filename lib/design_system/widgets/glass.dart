import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// A frosted translucent panel — the single surface primitive the whole app
/// is built from.
///
/// [blur] can be turned off for panels rendered inside an already-scrolling
/// list. Each `BackdropFilter` forces a save-layer over its bounds, so a
/// 3-column grid of 6 blurring cards is 6 full-viewport-ish save-layers per
/// frame; the ambient orbs behind them are diffuse enough that the tint alone
/// reads as glass.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HkSpace.cardPadding),
    this.radius = HkRadius.card,
    this.blur = true,
    this.tint,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;

  /// Optional colour laid over the standard glass fill — used for the lime
  /// "average attendance" stat card and the live schedule row.
  final Color? tint;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);

    // Two layers, not one BoxDecoration carrying both `color` and `gradient`:
    // when a BoxDecoration has a gradient, Flutter paints the gradient shader
    // and *silently ignores* `color`. Setting both meant `tint` never
    // rendered anywhere — including on a 94%-opaque dialog backing, which
    // showed the page straight through it.
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(color: tint, borderRadius: border),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: HkGlass.gradient,
          borderRadius: border,
          border: Border.all(color: borderColor ?? HkGlass.border),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );

    // The inset top highlight from the handoff. Flutter has no inset shadow,
    // so it's drawn as a 1px gradient hairline clipped to the panel's radius.
    surface = Stack(
      children: [
        surface,
        Positioned(
          left: radius * 0.5,
          right: radius * 0.5,
          top: 0,
          child: IgnorePointer(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x00FFFFFF),
                    HkGlass.edgeHighlight,
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    Widget result = ClipRRect(
      borderRadius: border,
      child: blur
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: HkGlass.blurSigma,
                sigmaY: HkGlass.blurSigma,
              ),
              child: surface,
            )
          : surface,
    );

    if (onTap != null) {
      result = _Hoverable(
        radius: border,
        onTap: onTap!,
        child: result,
      );
    }
    return result;
  }
}

/// Adds the design's "lighten to white-10% on hover" affordance. Desktop is
/// the primary target here, so hover state is not optional polish — without
/// it nothing on the canvas looks clickable under a mouse cursor.
class _Hoverable extends StatefulWidget {
  const _Hoverable({
    required this.child,
    required this.onTap,
    required this.radius,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius radius;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.008 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: Stack(
            children: [
              widget.child,
              if (_hovered)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x0FFFFFFF),
                        borderRadius: widget.radius,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded label — statuses, categories, durations, counts.
class HkPill extends StatelessWidget {
  const HkPill({
    super.key,
    required this.label,
    this.background,
    this.foreground,
    this.icon,
    this.dotColor,
    this.pulsingDot = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final IconData? icon;
  final Color? dotColor;
  final bool pulsingDot;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? HkColors.textSecondary;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(HkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            PulsingDot(color: dotColor!, animate: pulsingDot),
            const SizedBox(width: 7),
          ],
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 6),
          ],
          Text(label, style: HkType.chip.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// The live / recording indicator dot.
class PulsingDot extends StatefulWidget {
  const PulsingDot({
    super.key,
    required this.color,
    this.animate = true,
    this.size = 7,
  });

  final Color color;
  final bool animate;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  // Constructed eagerly in initState rather than with `late final`. A lazy
  // field is never initialised when `animate` is false (the notification
  // badge), and `dispose` then constructs the controller on its way out —
  // which does a TickerMode ancestor lookup on an already-deactivated
  // element and throws.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 1,
    );
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.animate) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: dot,
    );
  }
}

/// Circular initials avatar with the per-person gradient the design uses in
/// place of photographs.
class HkAvatar extends StatelessWidget {
  const HkAvatar({
    super.key,
    required this.initials,
    this.size = 38,
    this.gradient,
    this.ring,
  });

  final String initials;
  final double size;
  final Gradient? gradient;

  /// Speaking ring — drawn as a lime halo around the avatar.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient ??
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6FA0E0), HkColors.royalBlue],
            ),
        border: ring != null ? Border.all(color: ring!, width: 3) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: HkType.family,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// The primary lime CTA ("Darsga qo'shilish", "Testni boshlash").
class LimeButton extends StatelessWidget {
  const LimeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: kLimeGradient,
          borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(HkRadius.cardSmall),
            child: Padding(
              // Tighter on the short variant. 24 is right for a full-width
              // call to action; inside a table row, where the button is
              // sized to its column, it pushes the label out of the box.
              padding: EdgeInsets.symmetric(horizontal: height >= 46 ? 24 : 14),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: HkColors.ink),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: HkType.family,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: HkColors.ink,
                    ),
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

/// Thin progress bar used on recording cards and the mini rows.
class HkProgressBar extends StatelessWidget {
  const HkProgressBar({
    super.key,
    required this.value,
    this.color = HkColors.lime,
    this.height = 4,
  });

  /// 0..1
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(HkRadius.pill),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        backgroundColor: const Color(0x1FFFFFFF),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
