import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/lessons/data/providers.dart';
import '../../features/lessons/domain/models.dart';
import '../../features/lessons/presentation/notifications_panel.dart';
import '../../features/lessons/presentation/profile_menu.dart';
import '../../features/lessons/presentation/search_sheet.dart';
import '../layout.dart';
import '../navigation.dart';
import '../tokens.dart';
import 'ambient_background.dart';
import 'command_dock.dart';
import 'glass.dart';

/// The persistent chrome every screen sits inside: ambient canvas, floating
/// logo capsule, command dock, user cluster and the page heading.
///
/// On [HkLayout.compact] the floating chrome is replaced by a normal app bar
/// plus a bottom navigation bar — see [CompactNavBar] for why.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.scrollable = true,
  });

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
    final unread = ref.watch(unreadCountProvider);

    // Navigation follows the account's role, so a teacher's dock is not a
    // student's dock with items removed.
    final destinations = HkNav.forRole(profile?.role);
    final location = GoRouterState.of(context).uri.path;
    // Derived from the location rather than declared by each screen: the
    // same route is a different dock item depending on who is looking at it
    // ("Jonli" for a student, "Darsim" for the teacher running it).
    final current = HkNav.currentFor(profile?.role, location);

    void go(HkDestination d) {
      if (d.route != location) context.go(d.route);
    }

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        layout.contentHorizontalPadding,
        layout.contentTopPadding,
        layout.contentHorizontalPadding,
        // The body extends behind the bottom bar (extendBody), so the last
        // row of every list would come to rest underneath it. 62 is the bar,
        // the view padding is the phone's home indicator.
        layout.isCompact
            ? 36 + 62 + MediaQuery.viewPaddingOf(context).bottom
            : 36,
      ),
      child: child,
    );

    final scroller = scrollable
        ? SingleChildScrollView(primary: true, child: content)
        : content;

    return Scaffold(
      backgroundColor: HkColors.canvasBottom,
      extendBody: true,
      body: AmbientBackground(
        // A column on compact, not a stack. The header's height depends on
        // the phone's notch and on whether the subtitle wraps to a second
        // line, so any padding guessed for the content below it is wrong on
        // some device — and wrong here meant the heading printed on top of
        // the first paragraph. A column cannot be wrong: the header takes
        // what it needs and the content starts after it.
        child: layout.isCompact
            ? Column(
                children: [
                  _CompactHeader(
                    title: title,
                    subtitle: subtitle,
                    unread: unread,
                    initials: profile?.initials ?? '?',
                  ),
                  Expanded(child: scroller),
                ],
              )
            : Stack(
                children: [
                  Positioned.fill(child: scroller),
                  ..._floatingChrome(
                    context,
                    layout,
                    destinations,
                    current,
                    liveActive,
                    profile,
                    unread,
                    go,
                  ),
                ],
              ),
      ),
      bottomNavigationBar: layout.isCompact
          ? CompactNavBar(
              destinations: destinations,
              current: current,
              onSelect: go,
              liveActive: liveActive,
            )
          : null,
    );
  }

  List<Widget> _floatingChrome(
    BuildContext context,
    HkLayout layout,
    List<HkDestination> destinations,
    HkDestination? current,
    bool liveActive,
    UserProfile? profile,
    int unread,
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
            destinations: destinations,
            current: current,
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
            hasUnread: unread > 0,
            onSearch: () => showHkSearch(context),
            onNotifications: () => showHkNotifications(context),
            onProfile: () => showHkProfileMenu(context),
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
  const _CompactHeader({
    required this.title,
    required this.subtitle,
    required this.unread,
    required this.initials,
  });

  final String title;
  final String subtitle;
  final int unread;

  /// The avatar doubles as the way into the profile menu, which is the only
  /// way to sign out. On desktop that lives in [UserCluster]; when the
  /// compact header was rewritten it was left out, and a phone user had no
  /// way out of their account at all.
  final String initials;

  @override
  Widget build(BuildContext context) {
    // Opaque, and sized by its content. It is the first row of a column now,
    // not an overlay, so it pushes the page down instead of covering it.
    return ColoredBox(
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
                IconButton(
                  tooltip: 'Qidiruv',
                  onPressed: () => showHkSearch(context),
                  icon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: HkColors.textSecondary,
                  ),
                ),
                IconButton(
                  tooltip: 'Bildirishnomalar',
                  onPressed: () => showHkNotifications(context),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        size: 20,
                        color: HkColors.textSecondary,
                      ),
                      if (unread > 0)
                        const Positioned(
                          right: -1,
                          top: -1,
                          child: PulsingDot(
                            color: HkColors.danger,
                            size: 6,
                            animate: false,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Profil',
                  onPressed: () => showHkProfileMenu(context),
                  icon: HkAvatar(initials: initials, size: 30),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
