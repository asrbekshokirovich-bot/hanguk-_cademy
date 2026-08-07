import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/lessons_repository.dart';
import '../data/providers.dart';
import '../domain/models.dart';
import '../../../core/clock.dart';

/// The bell panel. Anchored under the bell on desktop; a full dialog on
/// phones, where a 380pt popover anchored to a 36pt icon has nowhere to go.
Future<void> showHkNotifications(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x80000000),
    builder: (_) => const _NotificationsDialog(),
  );
}

class _NotificationsDialog extends ConsumerWidget {
  const _NotificationsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 760;

    return Dialog(
      backgroundColor: Colors.transparent,
      // Pinned top-right on desktop so it reads as belonging to the bell it
      // came from, centred on phones.
      alignment: isWide ? Alignment.topRight : Alignment.center,
      insetPadding: isWide
          ? const EdgeInsets.only(top: 78, right: 28)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(16),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Bildirishnomalar',
                        style: HkType.sectionTitle),
                  ),
                  const _MarkAllReadButton(),
                  IconButton(
                    tooltip: 'Yopish',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: HkColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const Divider(color: HkGlass.border, height: 20),
              Flexible(
                child: AsyncSection(
                  value: ref.watch(notificationsProvider),
                  onRetry: () => ref.invalidate(notificationsProvider),
                  loadingHeight: 140,
                  isEmpty: (n) => n.isEmpty,
                  emptyMessage: 'Yangi bildirishnoma yo‘q',
                  builder: (items) => ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, i) => _NotificationRow(
                      notification: items[i],
                      onTap: () {
                        final route = items[i].route;
                        Navigator.of(context).pop();
                        if (route != null) context.go(route);
                      },
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

class _MarkAllReadButton extends ConsumerStatefulWidget {
  const _MarkAllReadButton();

  @override
  ConsumerState<_MarkAllReadButton> createState() =>
      _MarkAllReadButtonState();
}

class _MarkAllReadButtonState extends ConsumerState<_MarkAllReadButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider);
    if (unread == 0) return const SizedBox.shrink();

    return TextButton(
      onPressed: _busy
          ? null
          : () async {
              // Resolved before the await: this button lives inside a dialog
              // that the user may dismiss mid-request, and looking the
              // messenger up afterwards would be a lookup on a dead context.
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _busy = true);
              try {
                await ref
                    .read(lessonsRepositoryProvider)
                    .markNotificationsRead();
                ref.invalidate(notificationsProvider);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Saqlanmadi: $e')),
                );
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: Text(
        "O'qildi",
        style: HkType.chip.copyWith(color: HkColors.lime),
      ),
    );
  }
}

class _NotificationRow extends StatefulWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _hovered = false;

  /// "12 daq oldin" / "5 soat oldin" / "3 kun oldin" — absolute timestamps
  /// on a notification list force the reader to do the arithmetic.
  String get _age {
    final d = hkNow().difference(widget.notification.createdAt);
    if (d.inMinutes < 1) return 'hozir';
    if (d.inMinutes < 60) return '${d.inMinutes} daq oldin';
    if (d.inHours < 24) return '${d.inHours} soat oldin';
    if (d.inDays < 7) return '${d.inDays} kun oldin';
    return DateFormat('d-MMMM', 'uz').format(widget.notification.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;

    return MouseRegion(
      cursor: n.route == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? HkGlass.hoverFill
                : (n.isUnread ? const Color(0x0DD4E94C) : Colors.transparent),
            borderRadius: BorderRadius.circular(HkRadius.cardSmall),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(n.icon, size: 16, color: n.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            n.title,
                            style: HkType.cardTitle.copyWith(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (n.isUnread) ...[
                          const SizedBox(width: 8),
                          const PulsingDot(
                            color: HkColors.lime,
                            size: 6,
                            animate: false,
                          ),
                        ],
                      ],
                    ),
                    if (n.body != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        n.body!,
                        style: HkType.body.copyWith(fontSize: 12.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(_age, style: HkType.muted.copyWith(fontSize: 11)),
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
