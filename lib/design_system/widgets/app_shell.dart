import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/lessons/data/providers.dart';
import '../../features/lessons/domain/models.dart';
import '../layout.dart';
import '../tokens.dart';
import 'ambient_background.dart';
import 'command_dock.dart';

/// The persistent chrome every screen sits inside: ambient canvas, floating
/// logo capsule, command dock, user cluster and the page heading.
///
/// On [HkLayout.compact] the floating chrome is replaced by a normal app bar
/// plus a bottom navigation bar — see [CompactNavBar] for why.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.destination,
    required this.title,
    required this.subtitle,
    required this.child,
    this.scrollable = true,
  });

  final HkDestination destination;
  final String title;
  final String subtitle;
  final Widget child;

  /// Live room manages its own height and must not scroll.
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final liveActive = ref.watch(liveLessonProvider).value != null;
    final profile = ref.watch(profileProvider).value;

    void go(HkDestination d) {
      if (d.route != GoRouterState.of(context).uri.path) context.go(d.route);
    }

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        layout.contentHorizontalPadding,
        layout.contentTopPadding,
        layout.contentHorizontalPadding,
        36,
      ),
      child: child,
    );

    return Scaffold(
      backgroundColor: HkColors.canvasBottom,
      extendBody: true,
      body: AmbientBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: scrollable
                  ? SingleChildScrollView(
                      primary: true,
                      child: content,
                    )
                  : content,
            ),
            if (layout.isCompact)
              _CompactHeader(title: title, subtitle: subtitle)
            else
              ..._floatingChrome(context, layout, liveActive, profile, go),
          ],
        ),
      ),
      bottomNavigationBar: layout.isCompact
          ? CompactNavBar(
              current: destination,
              onSelect: go,
              liveActive: liveActive,
            )
          : null,
    );
  }

  List<Widget> _floatingChrome(
    BuildContext context,
    HkLayout layout,
    bool liveActive,
    UserProfile? profile,
    ValueChanged<HkDestination> go,
  ) {
    return [
      const Positioned(top: 24, left: 28, child: LogoCapsule()),
      Positioned(
        top: 24,
        left: 0,
        right: 0,
        child: Center(
          child: CommandDock(
            current: destination,
            onSelect: go,
            liveActive: liveActive,
          ),
        ),
      ),
      // The user cluster is the first thing to go when the window narrows —
      // at `medium` the dock and the logo capsule would otherwise overlap it.
      if (layout.isExpanded)
        Positioned(
          top: 24,
          right: 28,
          child: UserCluster(
            name: profile?.fullName ?? '—',
            subtitle: profile?.subtitle ?? '',
            initials: profile?.initials ?? '?',
            hasUnread: true,
          ),
        ),
      Positioned(
        top: 92,
        left: 30,
        child: PageHeading(title: title, subtitle: subtitle),
      ),
    ];
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Sits above the scrolling content with an opaque backing, so titles stay
    // legible as cards pass under them.
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: HkColors.canvasTop.withValues(alpha: 0.92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/hanguk-mark.png',
                    width: 32,
                    height: 32,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PageHeading(title: title, subtitle: subtitle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
