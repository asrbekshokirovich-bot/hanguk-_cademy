import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../tokens.dart';

/// The app's own title bar, in place of the operating system's.
///
/// Windows draws a grey strip above every window, and above this app it looked
/// like a bar of a completely different program bolted to the top of the
/// design — the whole product is dark glass over an ambient gradient, and the
/// system bar is neither. Chrome solves this the same way: hide the system
/// bar, draw your own, keep the three buttons where Windows users expect them.
///
/// What the system still owns, and what has to be re-implemented here:
/// dragging the window (`DragToMoveArea`), double-click to maximise, and the
/// minimise/maximise/close buttons. Snapping (`Win`+arrow, dragging to an
/// edge) keeps working because the window is still a normal window — only its
/// decoration is gone.
///
/// On web and mobile this is nothing: it returns the child untouched.
class HkWindowChrome extends StatefulWidget {
  const HkWindowChrome({super.key, required this.child});

  final Widget child;

  @override
  State<HkWindowChrome> createState() => _HkWindowChromeState();
}

class _HkWindowChromeState extends State<HkWindowChrome> with WindowListener {
  bool _maximized = true;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (!_isDesktop) return;
    windowManager.addListener(this);
    // The window opens maximised, but the user may have restored it before
    // this widget was ever built (a resize during startup), so the initial
    // state is asked for rather than assumed.
    unawaited(_syncMaximized());
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _syncMaximized() async {
    final value = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() => _maximized = value);
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return widget.child;

    return Column(
      children: [
        SizedBox(
          height: _barHeight,
          child: DragToMoveArea(
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(
                  Icons.school_rounded,
                  size: 15,
                  color: HkColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Hanguk Academy',
                  style: HkType.muted.copyWith(fontSize: 12),
                ),
                // The empty middle is the drag handle, and double-clicking it
                // maximises — both are what the system bar did, and losing
                // either is what makes a custom title bar feel broken.
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: _toggleMaximize,
                    child: const SizedBox.expand(),
                  ),
                ),
                _WindowButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Kichraytirish',
                  onPressed: windowManager.minimize,
                ),
                _WindowButton(
                  icon: _maximized
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  // Smaller: `filter_none` is two overlapping squares and
                  // reads heavier than the single square beside it.
                  iconSize: _maximized ? 13 : 15,
                  tooltip: _maximized ? 'Tiklash' : 'Kattalashtirish',
                  onPressed: _toggleMaximize,
                ),
                _WindowButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Yopish',
                  hoverColor: HkColors.danger,
                  onPressed: windowManager.close,
                ),
              ],
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// Windows' own buttons are 46x32 and light up on hover. Matching that is not
/// imitation for its own sake — it is where the pointer expects to find them,
/// and how it expects them to answer.
const double _barHeight = 34;

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor = HkGlass.fillTop,
    this.iconSize = 15,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color hoverColor;
  final double iconSize;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: _barHeight,
            color: _hovering ? widget.hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovering ? HkColors.textPrimary : HkColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
