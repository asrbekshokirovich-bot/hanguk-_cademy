import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show DesktopCapturerSource, SourceType;

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';

/// What "Ulashish" put on the room's stage.
///
/// One button now covers two different things a teacher can put in front of
/// the class — a window or display, and the whiteboard — because to a
/// student watching, both are the same event: the camera is gone and
/// something else is on screen instead. A second button next to the first
/// was two controls for one idea, and it was the idea this screen used to
/// get wrong: "Doska" lived as its own toggle, so the room could show a
/// shared window *and* believe the board was still the thing on stage,
/// which it plainly was not.
class ShareChoice {
  const ShareChoice.board()
      : sourceId = null,
        isBoard = true;

  /// [id] is null on the browser and Android: there is no specific window to
  /// name, only "start the operating system's own chooser".
  const ShareChoice.source([this.sourceId])
      : isBoard = false;

  final String? sourceId;
  final bool isBoard;
}

/// What to share: a window, a display, or the board.
///
/// Windows, macOS and Linux have no chooser of their own for a window or
/// display — the platform is handed a source id or it refuses with "source
/// not found" — so [sources] carries the machine's own list there. The
/// browser and Android pick the window themselves once sharing starts, so
/// [sources] arrives empty and this dialog offers only the board, or nothing
/// at all when [canDrawBoard] is also false.
///
/// Returns the choice made, or null if the teacher changed their mind.
Future<ShareChoice?> showSharePicker(
  BuildContext context, {
  required List<DesktopCapturerSource> sources,
  required bool canDrawBoard,
  required bool canPickSource,
}) {
  return showDialog<ShareChoice>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _Picker(
      sources: sources,
      canDrawBoard: canDrawBoard,
      canPickSource: canPickSource,
    ),
  );
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.sources,
    required this.canDrawBoard,
    required this.canPickSource,
  });

  final List<DesktopCapturerSource> sources;
  final bool canDrawBoard;

  /// False on the browser and Android: there the operating system's own
  /// chooser runs instead of this grid, so choosing "the screen" here means
  /// only "start that native chooser", not a specific window.
  final bool canPickSource;

  @override
  Widget build(BuildContext context) {
    final screens =
        sources.where((s) => s.type == SourceType.Screen).toList();
    final windows =
        sources.where((s) => s.type == SourceType.Window).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: GlassPanel(
          radius: HkRadius.cardLarge,
          padding: const EdgeInsets.all(24),
          blur: false,
          tint: const Color(0xF00C1430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Nimani ulashamiz?', style: HkType.pageTitle),
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
              const SizedBox(height: 4),
              Text(
                'Talabalar faqat shu tanlangan narsani ko‘radi.',
                style: HkType.muted,
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (canDrawBoard) ...[
                        Text('Doska', style: HkType.label),
                        const SizedBox(height: 10),
                        _BoardCard(
                          onTap: () => Navigator.of(context)
                              .pop(const ShareChoice.board()),
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (canPickSource) ...[
                        if (sources.isEmpty)
                          Text(
                            'Ulashish uchun oyna topilmadi.',
                            style: HkType.body.copyWith(fontSize: 13),
                          )
                        else ...[
                          if (screens.isNotEmpty) ...[
                            Text('Ekran', style: HkType.label),
                            const SizedBox(height: 10),
                            _Grid(sources: screens),
                            const SizedBox(height: 18),
                          ],
                          if (windows.isNotEmpty) ...[
                            Text('Oynalar', style: HkType.label),
                            const SizedBox(height: 10),
                            _Grid(sources: windows),
                          ],
                        ],
                      ] else
                        // The browser/Android path: there is nothing here to
                        // pick from, only a door into the OS's own chooser.
                        _BrowserShareCard(
                          onTap: () => Navigator.of(context)
                              .pop(const ShareChoice.source()),
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

/// The tile that puts the board on stage instead of a window.
class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x1AD4E94C),
                borderRadius: BorderRadius.circular(HkRadius.cardSmall),
                border: Border.all(color: const Color(0x33D4E94C)),
              ),
              child: const Icon(
                Icons.draw_outlined,
                size: 26,
                color: HkColors.lime,
              ),
            ),
            const SizedBox(height: 6),
            // No caption: the section header just above already says
            // "Doska", and a lone tile repeating its own section's name is
            // the word doubled for nothing — which is also, verbatim, what
            // tripped up the first widget test written against this screen.
            Text(
              'Yozib ko‘rsatish uchun',
              style: HkType.muted.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one tile shown where the platform picks the window itself.
class _BrowserShareCard extends StatelessWidget {
  const _BrowserShareCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(HkRadius.cardSmall),
                border: Border.all(color: HkGlass.border),
              ),
              child: const Icon(
                Icons.screen_share_outlined,
                size: 24,
                color: HkColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text('Ekran', style: HkType.body.copyWith(fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.sources});

  final List<DesktopCapturerSource> sources;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final s in sources) _SourceCard(source: s)],
    );
  }
}

/// One candidate, with its picture.
///
/// The thumbnail is the whole point: three windows called "Hanguk Academy"
/// are indistinguishable by title, and sharing the wrong one in front of a
/// class is not a mistake you get to take back.
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final DesktopCapturerSource source;

  @override
  Widget build(BuildContext context) {
    final thumbnail = source.thumbnail;

    return SizedBox(
      width: 200,
      child: InkWell(
        borderRadius: BorderRadius.circular(HkRadius.cardSmall),
        onTap: () =>
            Navigator.of(context).pop(ShareChoice.source(source.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 112,
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(HkRadius.cardSmall),
                border: Border.all(color: HkGlass.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: thumbnail == null
                  ? const Center(
                      child: Icon(
                        Icons.desktop_windows_outlined,
                        size: 22,
                        color: HkColors.textTertiary,
                      ),
                    )
                  : Image.memory(thumbnail, fit: BoxFit.cover),
            ),
            const SizedBox(height: 6),
            Text(
              source.name.isEmpty ? 'Nomsiz oyna' : source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HkType.body.copyWith(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
