import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// The canvas every screen sits on: a deep navy→black gradient with four
/// heavily blurred colour orbs drifting behind it.
///
/// The orbs are drawn with a [RadialGradient] rather than a real blur filter.
/// A `BackdropFilter`/`ImageFiltered` blur of a 90–120px radius over four
/// large shapes, animating continuously, costs more per frame than the rest
/// of the app combined — and on a low-end Windows laptop (the machine most of
/// these students actually have) it drops the whole shell below 60fps. A soft
/// radial falloff is visually indistinguishable at these opacities.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  // (colour, diameter, base alignment, seconds per cycle) — periods are
  // mutually prime-ish so the four orbs never resynchronise into a pulse.
  static const _orbs = <_Orb>[
    _Orb(HkColors.orbBlue, 620, Alignment(-0.75, -0.85), 22, 0.55),
    _Orb(HkColors.orbLime, 460, Alignment(0.85, -0.55), 26, 0.20),
    _Orb(HkColors.orbViolet, 560, Alignment(-0.55, 0.85), 18, 0.32),
    _Orb(HkColors.orbTeal, 500, Alignment(0.75, 0.75), 24, 0.26),
  ];

  @override
  void initState() {
    super.initState();
    // One controller drives all four; each orb reads it at its own rate.
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.8, -1),
          end: Alignment(0.8, 1),
          colors: [
            HkColors.canvasTop,
            HkColors.canvasMid,
            HkColors.canvasBottom,
          ],
          stops: [0.0, 0.46, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final orb in _orbs) _buildOrb(orb),
                  ],
                );
              },
            ),
          ),
          widget.child,
        ],
      ),
    );
  }

  Widget _buildOrb(_Orb orb) {
    // Lissajous-ish wander: different x/y frequencies keep the path from
    // being a visible circle.
    final t = (_drift.value * 60 / orb.periodSeconds) * 2 * math.pi;
    final dx = math.sin(t) * 0.12;
    final dy = math.cos(t * 0.63) * 0.10;

    return Align(
      alignment: Alignment(orb.at.x + dx, orb.at.y + dy),
      child: IgnorePointer(
        child: Container(
          width: orb.size,
          height: orb.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                orb.color.withValues(alpha: orb.opacity),
                orb.color.withValues(alpha: orb.opacity * 0.45),
                orb.color.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

class _Orb {
  const _Orb(this.color, this.size, this.at, this.periodSeconds, this.opacity);

  final Color color;
  final double size;
  final Alignment at;
  final double periodSeconds;
  final double opacity;
}
