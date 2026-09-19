import 'package:flutter/material.dart';

import '../../core/file_pick.dart';
import '../tokens.dart';

/// The "attach a file" line, used by both the hand-in and the set-homework
/// dialogs.
///
/// Named and sized once something is chosen, because "fayl tanlandi" tells
/// nobody whether they picked the right one — and a 50 MB limit is only
/// useful if the number is on screen before the send button is pressed.
class HkFileRow extends StatelessWidget {
  const HkFileRow({
    super.key,
    required this.name,
    required this.sizeBytes,
    required this.onPick,
    required this.onClear,
    this.emptyLabel = 'Fayl biriktirilmagan',
    this.pickLabel = 'Fayl biriktirish',
  });

  final String? name;
  final int? sizeBytes;

  /// Null while something is in flight, which disables the row rather than
  /// letting a second file be chosen mid-upload.
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  final String emptyLabel;
  final String pickLabel;

  @override
  Widget build(BuildContext context) {
    final picked = name;
    final size = hkFileSizeLabel(sizeBytes);

    return Row(
      children: [
        Icon(
          picked == null
              ? Icons.attach_file_rounded
              : Icons.insert_drive_file_outlined,
          size: 18,
          color: picked == null ? HkColors.textSecondary : HkColors.lime,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            picked == null
                ? emptyLabel
                : size == null
                    ? picked
                    : '$picked · $size',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HkType.body.copyWith(fontSize: 12.5),
          ),
        ),
        if (picked != null)
          TextButton(
            onPressed: onClear,
            child: const Text(
              'Olib tashlash',
              style: TextStyle(
                fontFamily: HkType.family,
                fontSize: 12.5,
                color: HkColors.textTertiary,
              ),
            ),
          ),
        TextButton(
          onPressed: onPick,
          child: Text(
            picked == null ? pickLabel : 'Almashtirish',
            style: const TextStyle(
              fontFamily: HkType.family,
              fontSize: 12.5,
              color: HkColors.lime,
            ),
          ),
        ),
      ],
    );
  }
}
