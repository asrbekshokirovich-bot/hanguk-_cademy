import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/providers.dart';
import '../domain/models.dart';

/// Search across lessons and recordings, opened from the magnifier in the
/// user cluster (and from the compact header on phones).
Future<void> showHkSearch(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => const _SearchSheet(),
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // The query survives in a provider so reopening the sheet keeps the last
    // search; seed the field from it.
    _controller.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // 300ms: two Supabase round trips per keystroke on a phone connection is
    // both slow and pointless, since the query changes again before the first
    // one lands.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 560),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(18),
          // The dialog sits over a dimmed barrier, not over the ambient orbs,
          // so a backdrop blur here would blur nothing and still cost a
          // save-layer.
          blur: false,
          tint: const Color(0xF00C1430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: HkColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onChanged,
                      style: HkType.body.copyWith(
                        fontSize: 15,
                        color: HkColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: "Dars, yozuv yoki o'qituvchi nomi…",
                        hintStyle: HkType.body.copyWith(fontSize: 15),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yopish',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 19,
                      color: HkColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const Divider(color: HkGlass.border, height: 24),
              Flexible(
                child: query.trim().length < 2
                    ? const _SearchHint()
                    : _SearchResultsView(
                        onOpen: (route) {
                          Navigator.of(context).pop();
                          context.go(route);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          "Qidirish uchun kamida 2 ta harf yozing.",
          style: HkType.body.copyWith(fontSize: 13),
        ),
      ),
    );
  }
}

class _SearchResultsView extends ConsumerWidget {
  const _SearchResultsView({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncSection(
      value: ref.watch(searchResultsProvider),
      onRetry: () => ref.invalidate(searchResultsProvider),
      loadingHeight: 140,
      isEmpty: (r) => r.isEmpty,
      emptyMessage: 'Hech narsa topilmadi',
      builder: (results) => ListView(
        shrinkWrap: true,
        children: [
          if (results.lessons.isNotEmpty) ...[
            const _SectionLabel('Darslar'),
            for (final lesson in results.lessons)
              _ResultRow(
                icon: Icons.event_note_rounded,
                accent: lesson.accent,
                title: lesson.title,
                subtitle: '${lesson.teacher?.fullName ?? '—'} · '
                    '${DateFormat('d-MMMM, HH:mm', 'uz').format(lesson.startsAt)}',
                trailing: HkPill(
                  label: lesson.status.label,
                  background: lesson.status.pillBackground,
                  foreground: lesson.status.pillForeground,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                ),
                onTap: () => onOpen(
                  lesson.status == LessonStatus.live ? '/live' : '/schedule',
                ),
              ),
          ],
          if (results.recordings.isNotEmpty) ...[
            const _SectionLabel('Yozuvlar'),
            for (final r in results.recordings)
              _ResultRow(
                icon: Icons.play_circle_outline_rounded,
                accent: HkColors.lime,
                title: r.title,
                subtitle: '${r.teacher?.fullName ?? '—'} · '
                    '${DateFormat('d-MMMM y', 'uz').format(r.recordedAt)}',
                trailing: Text(r.durationLabel, style: HkType.muted),
                onTap: () => onOpen('/recordings/${r.id}'),
              ),
          ],
          // Staff only in practice: RLS returns no students and no groups to
          // anyone else, so these two sections simply do not appear for a
          // student rather than being hidden by a role check here.
          if (results.students.isNotEmpty) ...[
            const _SectionLabel('Talabalar'),
            for (final p in results.students)
              _ResultRow(
                icon: Icons.person_outline_rounded,
                accent: HkColors.royalBlue,
                title: p.name,
                subtitle: p.subtitle ?? 'Guruhsiz',
                onTap: () => onOpen('/admin/students'),
              ),
          ],
          if (results.groups.isNotEmpty) ...[
            const _SectionLabel('Guruhlar'),
            for (final g in results.groups)
              _ResultRow(
                icon: Icons.groups_outlined,
                accent: HkColors.lime,
                title: g.name,
                subtitle: 'Guruh',
                onTap: () => onOpen('/admin/groups'),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: HkType.muted.copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

class _ResultRow extends StatefulWidget {
  const _ResultRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
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
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered ? HkGlass.hoverFill : Colors.transparent,
            borderRadius: BorderRadius.circular(HkRadius.cardSmall),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: widget.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: HkType.cardTitle.copyWith(fontSize: 13.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: HkType.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 12),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
