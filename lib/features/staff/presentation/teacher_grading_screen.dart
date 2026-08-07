import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 moved StateProvider out of the main barrel; the filter here is
// a single value driven by a tap, which is what it is for.
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/clock.dart';
import '../../../design_system/layout.dart';
import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/app_shell.dart';
import '../../../design_system/widgets/data_table.dart';
import '../../../design_system/widgets/glass.dart';
import '../../../design_system/widgets/states.dart';
import '../data/staff_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff_models.dart';
import 'grade_dialog.dart';

/// Show graded work as well as pending, or only what is waiting.
final gradingShowAllProvider = StateProvider<bool>((ref) => false);

/// "Baholash" — the grading queue.
class TeacherGradingScreen extends ConsumerWidget {
  const TeacherGradingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = HkLayout.of(context);
    final showAll = ref.watch(gradingShowAllProvider);
    final now = hkNow();

    return AppShell(
      title: 'Baholash',
      subtitle: 'Topshirilgan vazifalar',
      child: AsyncSection(
        value: ref.watch(submissionsProvider),
        onRetry: () => ref.invalidate(submissionsProvider),
        loadingHeight: 260,
        isEmpty: (s) => s.isEmpty,
        emptyMessage: 'Hali vazifa topshirilmagan',
        builder: (all) {
          final pending = all.where((s) => !s.isGraded).toList();
          final shown = showAll ? all : pending;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Toggle(
                    label: 'Kutilmoqda · ${pending.length}',
                    active: !showAll,
                    onTap: () =>
                        ref.read(gradingShowAllProvider.notifier).state =
                            false,
                  ),
                  _Toggle(
                    label: 'Barchasi · ${all.length}',
                    active: showAll,
                    onTap: () =>
                        ref.read(gradingShowAllProvider.notifier).state = true,
                  ),
                ],
              ),
              const SizedBox(height: HkSpace.gridGapWide),
              if (shown.isEmpty)
                GlassPanel(
                  radius: HkRadius.cardLarge,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 34,
                            color: HkColors.successBright,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Hammasi tekshirilgan',
                            style: HkType.body.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                HkTable(
                  showHeader: layout.isExpanded,
                  trailingWidth: 110,
                  columns: const [
                    HkColumn('Talaba', 5),
                    HkColumn('Vazifa', 6),
                    HkColumn('Topshirildi', 4),
                    HkColumn('Holat', 3),
                  ],
                  rows: [
                    for (final s in shown)
                      _SubmissionRow(
                        submission: s,
                        expanded: layout.isExpanded,
                        now: now,
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SubmissionRow extends ConsumerStatefulWidget {
  const _SubmissionRow({
    required this.submission,
    required this.expanded,
    required this.now,
  });

  final Submission submission;
  final bool expanded;
  final DateTime now;

  @override
  ConsumerState<_SubmissionRow> createState() => _SubmissionRowState();
}

class _SubmissionRowState extends ConsumerState<_SubmissionRow> {
  bool _busy = false;

  Future<void> _grade() async {
    final result = await showGradeDialog(
      context,
      studentName: widget.submission.studentName,
      assignmentTitle: widget.submission.assignmentTitle,
      initialGrade: widget.submission.grade,
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(staffRepositoryProvider).gradeSubmission(
            assignmentId: widget.submission.assignmentId,
            studentId: widget.submission.studentId,
            grade: result.grade,
            feedback: result.feedback,
          );
      ref.invalidate(submissionsProvider);
      ref.invalidate(teacherStatsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget get _action {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: HkColors.lime,
          ),
        ),
      );
    }
    final graded = widget.submission.isGraded;
    return SizedBox(
      height: 36,
      child: graded
          ? OutlinedButton(
              onPressed: _grade,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: HkGlass.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HkRadius.control),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(
                '${widget.submission.grade}',
                style: HkType.label.copyWith(fontSize: 13),
              ),
            )
          : LimeButton(label: 'Baholash', height: 36, onPressed: _grade),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.submission;

    if (!widget.expanded) {
      return HkTableRow(
        padding: const EdgeInsets.all(14),
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HkPersonCell(
                  name: s.studentName,
                  initials: s.initials,
                  gradient: s.gradient,
                  subtitle: s.assignmentTitle,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    HkPill(
                      label: s.statusLabel,
                      background: s.statusBackground,
                      foreground: s.statusColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hkRelative(s.submittedAt, now: widget.now),
                        style: HkType.muted,
                      ),
                    ),
                    _action,
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return HkTableRow(
      children: [
        Expanded(
          flex: 5,
          child: HkPersonCell(
            name: s.studentName,
            initials: s.initials,
            gradient: s.gradient,
          ),
        ),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.assignmentTitle,
                style: HkType.cardTitle.copyWith(fontSize: 13.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (s.lessonTitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  s.lessonTitle!,
                  style: HkType.muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            hkRelative(s.submittedAt, now: widget.now),
            style: HkType.muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: HkPill(
              label: s.statusLabel,
              background: s.statusBackground,
              foreground: s.statusColor,
            ),
          ),
        ),
        SizedBox(width: 110, child: Align(child: _action)),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? kLimeGradient : null,
            color: active ? null : const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(HkRadius.pill),
            border: Border.all(
              color: active ? Colors.transparent : HkGlass.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: HkType.family,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? HkColors.ink : HkColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
