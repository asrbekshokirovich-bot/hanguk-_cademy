import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show DesktopCapturerSource, SourceType;

import '../../../design_system/tokens.dart';
import '../../../design_system/widgets/glass.dart';

/// Which window or display to share.
///
/// Windows, macOS and Linux have no chooser of their own — the platform is
/// handed a source id or it refuses with "source not found". The browser and
/// Android do have one, so this is never shown there.
///
/// Returns the chosen source id, or null if the teacher changed their mind.
Future<String?> showScreenSharePicker(
  BuildContext context,
  List<DesktopCapturerSource> sources,
) {
  return showDialog<String>(
    context: context,
    barrierColor: const Color(0xB3000000),
    builder: (_) => _Picker(sources: sources),
  );
}

class _Picker extends StatelessWidget {
  const _Picker({required this.sources});

  final List<DesktopCapturerSource> sources;

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
                'Talabalar faqat shu tanlangan oynani ko‘radi.',
                style: HkType.muted,
              ),
              const SizedBox(height: 18),
              if (sources.isEmpty)
                Text(
                  'Ulashish uchun oyna topilmadi.',
                  style: HkType.body.copyWith(fontSize: 13),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
        onTap: () => Navigator.of(context).pop(source.id),
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
