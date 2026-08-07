import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/providers.dart';
import '../domain/models.dart';

/// Categories offered as filter chips. Kept as a constant rather than derived
/// from the data so the row doesn't reshuffle as the archive grows.
const kRecordingCategories = <String?>[
  null, // Barchasi
  'Koreys tili',
  'TOPIK',
  'Grammatika',
  'Tinglash',
];

class RecordingsScreen extends ConsumerWidget {
  const RecordingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final active = ref.watch(recordingsFilterProvider);

    return AppShell(
      title: 'Yozuvlar',
      subtitle: 'Yozib olingan darslar arxivi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final category in kRecordingCategories) ...[
                  _FilterChip(
                    label: category ?? 'Barchasi',
                    active: category == active,
                    onTap: () => ref
                        .read(recordingsFilterProvider.notifier)
                        .state = category,
                  ),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: HkSpace.gridGapWide),
          AsyncSection(
            value: ref.watch(recordingsProvider),
            onRetry: () => ref.invalidate(recordingsProvider),
            loadingHeight: 280,
            isEmpty: (r) => r.isEmpty,
            emptyMessage: 'Bu bo‘limda hali yozuv yo‘q',
            builder: (recordings) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recordings.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: layout.gridColumns,
                mainAxisSpacing: HkSpace.gridGapWide,
                crossAxisSpacing: HkSpace.gridGapWide,
                // Thumbnail (150) + 14 + two title lines (40) + meta + the
                // progress row + padding. Measured rather than guessed —
                // any slack shows as dead space under the progress bar.
                mainAxisExtent: layout.isCompact ? 286 : 276,
              ),
              itemBuilder: (context, i) =>
                  RecordingCard(recording: recordings[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: widget.active ? kLimeGradient : null,
            color: widget.active
                ? null
                : (_hovered ? HkGlass.hoverFill : const Color(0x0FFFFFFF)),
            borderRadius: BorderRadius.circular(HkRadius.pill),
            border: Border.all(
              color: widget.active ? Colors.transparent : HkGlass.border,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: HkType.family,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: widget.active ? HkColors.ink : HkColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class RecordingCard extends StatelessWidget {
  const RecordingCard({super.key, required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: HkRadius.card,
      padding: EdgeInsets.zero,
      // Blur is off inside the grid — six backdrop filters on one screen is
      // the single most expensive thing this app could do per frame, and the
      // orbs behind are diffuse enough that the tint alone reads as glass.
      blur: false,
      onTap: () => context.go('/recordings/${recording.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(recording: recording),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 40,
                  child: Text(
                    recording.title,
                    style: HkType.cardTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${recording.teacher?.fullName ?? '—'} · '
                  '${DateFormat('d-MMMM', 'uz').format(recording.recordedAt)}',
                  style: HkType.muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: HkProgressBar(
                        value: recording.progress,
                        color: recording.progressColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      recording.progressLabel,
                      style: HkType.chip.copyWith(
                        color: recording.isUnstarted
                            ? HkColors.textTertiary
                            : recording.progressColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.recording});

  final Recording recording;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        gradient: recording.thumbnailGradient,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HkRadius.card),
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: HkColors.lime,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 28,
                color: HkColors.ink,
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: HkPill(
              label: recording.category,
              background: const Color(0x66000000),
              foreground: HkColors.textPrimary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: HkPill(
              label: recording.durationLabel,
              background: const Color(0x8C000000),
              foreground: HkColors.textPrimary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            ),
          ),
        ],
      ),
    );
  }
}
