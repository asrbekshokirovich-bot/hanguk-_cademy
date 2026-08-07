import 'package:flutter/material.dart';

import '../layout.dart';
import '../navigation.dart';
import '../tokens.dart';
import 'glass.dart';

/// The floating glass command dock — the design's replacement for a sidebar.
///
/// Centred at the top of the window, above the content, which scrolls
/// underneath it.
class CommandDock extends StatelessWidget {
  const CommandDock({
    super.key,
    required this.destinations,
    required this.current,
    required this.onSelect,
    this.liveActive = false,
  });

  final List<HkDestination> destinations;
  final HkDestination? current;
  final ValueChanged<HkDestination> onSelect;

  /// Shows the pulsing red dot on the live entry when a lesson is
  /// broadcasting.
  final bool liveActive;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: HkRadius.pill,
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in destinations)
            _DockItem(
              destination: d,
              active: d == current,
              showLiveDot: d.route == '/live' && liveActive,
              onTap: () => onSelect(d),
            ),
        ],
      ),
    );
  }
}

class _DockItem extends StatefulWidget {
  const _DockItem({
    required this.destination,
    required this.active,
    required this.onTap,
    required this.showLiveDot,
  });

  final HkDestination destination;
  final bool active;
  final bool showLiveDot;
  final VoidCallback onTap;

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final fg = active ? HkColors.ink : const Color(0xB8FFFFFF);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? kLimeGradient : null,
            color: !active && _hovered ? HkGlass.hoverFill : null,
            borderRadius: BorderRadius.circular(HkRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.destination.icon, size: 17, color: fg),
              const SizedBox(width: 8),
              Text(
                widget.destination.label,
                style: TextStyle(
                  fontFamily: HkType.family,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (widget.showLiveDot) ...[
                const SizedBox(width: 7),
                const PulsingDot(color: HkColors.danger, size: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact-layout equivalent of the dock. A floating pill does not survive a
/// 390pt-wide phone — five labelled items simply do not fit, and overlaying
/// them on the content costs a third of the visible height.
class CompactNavBar extends StatelessWidget {
  const CompactNavBar({
    super.key,
    required this.destinations,
    required this.current,
    required this.onSelect,
    this.liveActive = false,
  });

  final List<HkDestination> destinations;
  final HkDestination? current;
  final ValueChanged<HkDestination> onSelect;
  final bool liveActive;

  @override
  Widget build(BuildContext context) {
    // Four at most. A fifth tab at 390pt truncates every label to an
    // ellipsis, and the staff roles are the ones with five — on a phone the
    // last one is reachable from its screen rather than the bar.
    final shown = destinations.take(4).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF00A0F22),
        border: Border(top: BorderSide(color: HkGlass.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (final d in shown)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(d),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              d.icon,
                              size: 21,
                              color: d == current
                                  ? HkColors.lime
                                  : HkColors.textTertiary,
                            ),
                            if (d.route == '/live' && liveActive)
                              const Positioned(
                                right: -3,
                                top: -2,
                                child: PulsingDot(
                                  color: HkColors.danger,
                                  size: 6,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.label,
                          style: TextStyle(
                            fontFamily: HkType.family,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: d == current
                                ? HkColors.lime
                                : HkColors.textTertiary,
                          ),
                        ),
                      ],
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

/// Frosted pill carrying the Hanguk mark and wordmark, top-left.
class LogoCapsule extends StatelessWidget {
  const LogoCapsule({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: HkRadius.pill,
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image.asset(
              'assets/images/hanguk-mark.png',
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 11),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hanguk Academy',
                style: TextStyle(
                  fontFamily: HkType.family,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: HkColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "Onlayn ta'lim",
                style: TextStyle(
                  fontFamily: HkType.family,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0x80FFFFFF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Search + notifications + the signed-in student, top-right.
class UserCluster extends StatelessWidget {
  const UserCluster({
    super.key,
    required this.name,
    required this.subtitle,
    required this.initials,
    this.hasUnread = false,
    this.onSearch,
    this.onNotifications,
    this.onProfile,
  });

  final String name;
  final String subtitle;
  final String initials;
  final bool hasUnread;
  final VoidCallback? onSearch;
  final VoidCallback? onNotifications;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: HkRadius.pill,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconButton(icon: Icons.search_rounded, onTap: onSearch),
          const SizedBox(width: 4),
          _IconButton(
            icon: Icons.notifications_none_rounded,
            onTap: onNotifications,
            badge: hasUnread,
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onProfile,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HkAvatar(initials: initials, size: 36),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: HkType.family,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: HkColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: HkType.family,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                    ],
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

class _IconButton extends StatefulWidget {
  const _IconButton({required this.icon, this.onTap, this.badge = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered ? HkGlass.hoverFill : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(widget.icon, size: 19, color: const Color(0xCCFFFFFF)),
              if (widget.badge)
                const Positioned(
                  right: 8,
                  top: 8,
                  child: PulsingDot(
                    color: HkColors.danger,
                    size: 6,
                    animate: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big view title that floats over the content at top-left.
class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = HkLayout.of(context).isCompact;
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: compact
                ? HkType.pageTitle.copyWith(fontSize: 21)
                : HkType.pageTitle,
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: HkType.body.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}
