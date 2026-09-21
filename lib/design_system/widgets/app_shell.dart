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
class AppShell extends ConsumerStatefulWidget {
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

  /// The band behind the floating page heading. Named so a test can read how
  /// far it has faded in; there is no other way to see a gradient's alpha.
  static const headingScrimKey = ValueKey('hk-heading-scrim');

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// How far the scrim behind the page heading has faded in, 0 to 1.
  ///
  /// On a desktop the heading floats over the page in a `Stack`, with the
  /// scroller filling the whole of it — so once the reader scrolls, whatever
  /// is in the page travels up through the heading's line and prints behind
  /// it. A phone does not have this: its header is the first row of a column
  /// and pushes the content down.
  ///
  /// A notifier rather than `setState`: this changes on every scrolled pixel
  /// and only the scrim needs to hear about it, not the whole shell.
  final _scrim = ValueNotifier<double>(0);

  /// Over how many scrolled pixels the scrim arrives. Short enough that text
  /// never reaches the heading unshielded, long enough not to flash.
  static const _scrimRamp = 40.0;

  @override
  void dispose() {
    _scrim.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    // Depth 0 is the page's own scroller; a list inside the page has its own
    // offset and must not move the heading's backdrop.
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      _scrim.value =
          (notification.metrics.pixels / _scrimRamp).clamp(0.0, 1.0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final subtitle = widget.subtitle;
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
      child: widget.child,
    );

    final scroller = widget.scrollable
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
                  ),
                  Expanded(child: scroller),
                ],
              )
            : NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: Stack(
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
      // First in the list, so every other piece of chrome paints over it.
      //
      // The heading below floats over the page: the scroller fills the whole
      // stack behind it, so the moment the reader scrolls, paragraphs travel
      // up through the heading's line and print behind its letters. A phone
      // does not have this — its header is the first row of a column and
      // pushes the page down — and the desktop was simply never scrolled
      // while anybody looked at the top of it.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: layout.contentTopPadding,
        child: IgnorePointer(
          child: ValueListenableBuilder<double>(
            valueListenable: _scrim,
            builder: (context, t, _) => DecoratedBox(
              key: AppShell.headingScrimKey,
              // A gradient rather than a flat fill: the canvas behind it is
              // itself a gradient with blurred orbs in it, and a hard edge
              // across the page would read as a seam. Invisible at rest, so
              // the screen as drawn is untouched until something actually
              // scrolls under the heading.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    HkColors.canvasTop.withValues(alpha: 0.94 * t),
                    HkColors.canvasTop.withValues(alpha: 0),
                  ],
                  stops: const [0.62, 1],
                ),
              ),
            ),
          ),
        ),
      ),
      const Positioned(top: 24, left: 28, child: LogoCapsule()),
      // Centred on the window at the design width, where the gutters either
      // side are wide enough for the logo capsule and the user cluster. The
      // superadmin's dock carries nine sections and is half as wide again as
      // the admin's: at full size it printed over the logo on one side and
      // had its last item — "Adminlar" — covered by the user cluster on the
      // other, where it could be neither read nor tapped. It is scaled down
      // rather than scrolled or trimmed: a dock item you have to find is not
      // navigation.
      if (layout.isExpanded)
        Positioned(
          top: 24,
          left: 0,
          right: 0,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 2 * _wideGutter,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: CommandDock(
                  destinations: destinations,
                  current: current,
                  onSelect: go,
                  liveActive: liveActive,
                ),
              ),
            ),
          ),
        )
      // Narrower than that, centring is what breaks it: the window is not
      // wide enough for a gutter the logo fits in, so a centred dock slides
      // straight over it — at 760 "Hanguk Academy" read "Hanguk A". Here the
      // dock is given the band that is left between the logo and the right
      // edge instead, and centred inside that. There is no user cluster at
      // this width, so the band is all its own.
      else
        Positioned(
          top: 24,
          left: _logoBand,
          right: 28,
          child: Align(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CommandDock(
                destinations: destinations,
                current: current,
                onSelect: go,
                liveActive: liveActive,
              ),
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
      // Last, so it sits above the scrim. It keeps its own loose constraints
      // rather than living inside the scrim's box: a heading laid out in a
      // 150pt band lays its two lines out fractionally differently, and the
      // only thing that is supposed to have changed here is what is behind
      // them.
      Positioned(
        top: 92,
        left: 30,
        child: PageHeading(title: widget.title, subtitle: widget.subtitle),
      ),
    ];
  }

  /// The gutter the centred dock leaves itself at the design's width.
  ///
  /// The logo capsule reaches about 244 from the left and the user cluster
  /// about 256 in from the right, so 260 a side is what they occupy plus a
  /// little air. It is symmetric because the dock is centred on the window,
  /// not on the gap: an uneven pair would slide it off centre for every
  /// role, to buy width only one of them needs.
  static const _wideGutter = 260.0;

  /// Where the logo capsule ends: 28 of margin, about 216 of capsule, and
  /// 16 of air. Below `expanded` the dock starts here rather than at the
  /// window's edge, so it cannot reach the logo however few or many sections
  /// the account's role has.
  static const _logoBand = 260.0;
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.title,
    required this.subtitle,
    required this.unread,
  });

  final String title;
  final String subtitle;
  final int unread;

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
              ],
            ),
          ),
        ),
    );
  }
}
