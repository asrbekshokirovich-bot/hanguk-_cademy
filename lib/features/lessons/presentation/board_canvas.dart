import 'package:flutter/material.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../domain/models.dart';

/// The board's own space is 16:9 and 0..1 on both axes.
///
/// Everything drawn on it is stored as a fraction of that box rather than in
/// pixels, so the teacher writing in a 1440pt window and the student reading
/// in a 390pt one see the same letter in the same place. The aspect ratio is
/// fixed for the same reason: stretch the box and the writing stretches with
/// it.
const kBoardAspect = 16 / 9;

const kBoardBackground = Color(0xFF111A35);

/// Five pens. A chalkboard needs a default that reads on dark, one accent for
/// what matters, and enough others to mark a correction apart from a note.
const kBoardPens = <Color>[
  Color(0xFFF2F5FF),
  HkColors.lime,
  Color(0xFF6FA0E0),
  Color(0xFFF0B24A),
  Color(0xFFE06A6A),
];

/// Thicknesses, as fractions of the board's width — 2.5, 5 and 10 pixels on a
/// thousand-pixel board.
const kBoardWidths = <double>[0.0025, 0.005, 0.010];

/// Wide enough to rub out a Hangul syllable in one pass.
const kBoardEraserWidth = 0.035;

/// The board, drawn. No gestures: this is what a student sees, and what the
/// lesson's page shows afterwards.
class HkBoardView extends StatelessWidget {
  const HkBoardView({
    super.key,
    required this.strokes,
    this.pending = const [],
    this.emptyMessage,
  });

  final List<BoardStroke> strokes;

  /// Strokes drawn on this device that the server has not sent back yet.
  final List<BoardStroke> pending;

  /// Shown when there is nothing on the board. Null for the live room, where
  /// an empty board is simply an empty board.
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final all = [...strokes, ...pending];
    return AspectRatio(
      aspectRatio: kBoardAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        child: ColoredBox(
          color: kBoardBackground,
          child: all.isEmpty && emptyMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      emptyMessage!,
                      textAlign: TextAlign.center,
                      style: HkType.muted,
                    ),
                  ),
                )
              : CustomPaint(
                  painter: _BoardPainter(all),
                  size: Size.infinite,
                ),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.strokes);

  final List<BoardStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (!stroke.isInk || stroke.points.isEmpty) continue;

      final colour = Color(stroke.color ?? 0xFFF2F5FF);
      // Thickness scales with the board, like the coordinates do. A stroke
      // stored in pixels would be a hairline on a desktop and a smear on a
      // phone.
      final thickness = (stroke.width ?? kBoardWidths[1]) * size.width;

      // A tap is a dot. Without this a single-point stroke drew nothing at
      // all, which is the mark somebody makes to point at something.
      if (stroke.points.length == 1) {
        final p = stroke.points.first;
        canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height),
          thickness / 2,
          Paint()..color = colour,
        );
        continue;
      }

      final path = Path();
      for (var i = 0; i < stroke.points.length; i++) {
        final p = stroke.points[i];
        final at = Offset(p.dx * size.width, p.dy * size.height);
        if (i == 0) {
          path.moveTo(at.dx, at.dy);
        } else {
          path.lineTo(at.dx, at.dy);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  // The live stroke changes on every pointer move, and the list is rebuilt on
  // every stream event, so there is nothing cheap left to compare.
  @override
  bool shouldRepaint(_BoardPainter oldDelegate) => true;
}

/// The board with a pen in its hand.
///
/// Only the teacher is given one — the surface simply is not built for anyone
/// else, so there is no button to press and nothing for the policy to refuse.
class HkBoardEditor extends StatefulWidget {
  const HkBoardEditor({
    super.key,
    required this.strokes,
    required this.onStroke,
    required this.onUndo,
    required this.onClear,
    required this.onError,
  });

  final List<BoardStroke> strokes;

  /// Files a finished stroke and answers with the row's id, so the surface
  /// knows when its own copy can stop being drawn.
  final Future<String> Function(int color, double width, List<Offset> points)
      onStroke;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  /// A stroke failed to save — most often a dropped connection. The surface
  /// has already taken the mark back off itself by the time this fires.
  final void Function(Object error) onError;

  @override
  State<HkBoardEditor> createState() => _HkBoardEditorState();
}

class _HkBoardEditorState extends State<HkBoardEditor> {
  Color _pen = kBoardPens.first;
  double _width = kBoardWidths[1];
  bool _erasing = false;

  /// The stroke under the pen right now.
  final List<Offset> _live = [];

  /// Strokes this device has filed but not yet seen come back. Held so the
  /// line does not blink out from under the hand that drew it while the round
  /// trip happens.
  final List<_Pending> _pending = [];

  /// The box being drawn on, read fresh on every pointer event rather than
  /// trusted from the event itself.
  ///
  /// A raw `PointerEvent.localPosition` is computed once, against the
  /// transform in effect the moment the pointer went *down*, and Flutter
  /// keeps using that same transform for every `move` that follows — it does
  /// not re-hit-test mid-gesture. The room sits a stack of banners above the
  /// board (a mic warning, an audio-blocked notice, a device error) that
  /// come and go on their own timers, and each one that appears or
  /// disappears while somebody is mid-stroke pushes the board up or down by
  /// its height. The pointer's cached position does not move with it, so the
  /// ink drifts away from the actual pen the longer the stroke runs — which
  /// is "uchib ketadi": it looks like the letter takes off from under the
  /// hand writing it. Converting from the event's *global* position against
  /// this box's *current* transform, on every single event, is the fix used
  /// for exactly this in every drawing surface built on `Listener`: it cannot
  /// go stale because nothing is cached across events.
  final _boardKey = GlobalKey();

  Color get _colour => _erasing ? kBoardBackground : _pen;
  double get _thickness => _erasing ? kBoardEraserWidth : _width;

  @override
  void didUpdateWidget(HkBoardEditor old) {
    super.didUpdateWidget(old);
    // Anything the server has now sent us is ours to stop drawing.
    final known = {for (final s in widget.strokes) s.id};
    _pending.removeWhere((p) => p.id != null && known.contains(p.id));
  }

  /// The board-space fraction under a global (screen) point, or null while
  /// the box has not been laid out yet.
  Offset? _fractionAt(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    return Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
  }

  void _start(Offset global) {
    final at = _fractionAt(global);
    if (at == null) return;
    setState(() => _live
      ..clear()
      ..add(at));
  }

  void _extend(Offset global) {
    if (_live.isEmpty) return;
    final at = _fractionAt(global);
    if (at == null) return;
    // Points closer together than this add nothing a reader can see, and a
    // minute of writing would otherwise be tens of thousands of coordinates
    // on the wire.
    if ((at - _live.last).distance < 0.002) return;
    setState(() => _live.add(at));
  }

  Future<void> _finish() async {
    if (_live.isEmpty) return;
    final points = List<Offset>.from(_live);
    final colour = _colour;
    final thickness = _thickness;
    final pending = _Pending(
      stroke: BoardStroke(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        kind: 'stroke',
        seq: 1 << 30,
        color: colour.toARGB32(),
        width: thickness,
        points: points,
      ),
    );
    setState(() {
      _live.clear();
      _pending.add(pending);
    });

    try {
      final id = await widget.onStroke(colour.toARGB32(), thickness, points);
      if (!mounted) return;
      setState(() => pending.id = id);
    } catch (e) {
      // The stroke never landed, so it must not keep pretending it did — and
      // silently dropping it is its own bug: the mark the teacher just made
      // would appear to vanish with no explanation the moment the pen lifts.
      if (!mounted) return;
      setState(() => _pending.remove(pending));
      widget.onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawn = [
      ...widget.strokes,
      for (final p in _pending) p.stroke,
      if (_live.isNotEmpty)
        BoardStroke(
          id: 'live',
          kind: 'stroke',
          seq: 1 << 30,
          color: _colour.toARGB32(),
          width: _thickness,
          points: _live,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible, because the room gives this a fixed height on a phone and
        // whatever is left of the window on a desktop. Unbounded, the board
        // took the width it wanted and pushed its own tools off the bottom.
        Flexible(
          child: AspectRatio(
            aspectRatio: kBoardAspect,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // `Listener` rather than a gesture recogniser: a board has to
                // take a mouse, a trackpad and a finger the same way, and the
                // raw pointer stream is the one place all three arrive alike.
                return Listener(
                  onPointerDown: (e) => _start(e.position),
                  onPointerMove: (e) => _extend(e.position),
                  onPointerUp: (_) => _finish(),
                  onPointerCancel: (_) => setState(_live.clear),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.precise,
                    child: KeyedSubtree(
                      key: _boardKey,
                      child: HkBoardView(strokes: drawn),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        _Tools(
          pen: _pen,
          width: _width,
          erasing: _erasing,
          onPen: (c) => setState(() {
            _pen = c;
            _erasing = false;
          }),
          onWidth: (w) => setState(() {
            _width = w;
            _erasing = false;
          }),
          onErase: () => setState(() => _erasing = !_erasing),
          onUndo: widget.onUndo,
          onClear: widget.onClear,
        ),
      ],
    );
  }
}

class _Pending {
  _Pending({required this.stroke});

  final BoardStroke stroke;
  String? id;
}

class _Tools extends StatelessWidget {
  const _Tools({
    required this.pen,
    required this.width,
    required this.erasing,
    required this.onPen,
    required this.onWidth,
    required this.onErase,
    required this.onUndo,
    required this.onClear,
  });

  final Color pen;
  final double width;
  final bool erasing;
  final ValueChanged<Color> onPen;
  final ValueChanged<double> onWidth;
  final VoidCallback onErase;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: HkRadius.pill,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final colour in kBoardPens)
            _Swatch(
              colour: colour,
              chosen: !erasing && colour == pen,
              onTap: () => onPen(colour),
            ),
          const _Divider(),
          for (final w in kBoardWidths)
            _WidthDot(
              width: w,
              chosen: !erasing && w == width,
              onTap: () => onWidth(w),
            ),
          const _Divider(),
          _ToolButton(
            icon: Icons.cleaning_services_outlined,
            tooltip: 'O‘chirg‘ich',
            active: erasing,
            onTap: onErase,
          ),
          _ToolButton(
            icon: Icons.undo_rounded,
            tooltip: 'Orqaga',
            onTap: onUndo,
          ),
          _ToolButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Doskani tozalash',
            onTap: onClear,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 22,
        color: HkGlass.border,
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    required this.chosen,
    required this.onTap,
  });

  final Color colour;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Rang',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(
              color: chosen ? HkColors.textPrimary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidthDot extends StatelessWidget {
  const _WidthDot({
    required this.width,
    required this.chosen,
    required this.onTap,
  });

  final double width;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Qalam yo‘g‘onligi',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: chosen ? const Color(0x1FFFFFFF) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Container(
            // The same fractions the board draws with, shown against a 28pt
            // button rather than a whole board.
            width: width * 900,
            height: width * 900,
            decoration: const BoxDecoration(
              color: HkColors.textPrimary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0x33D4E94C) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? HkColors.lime : HkColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
