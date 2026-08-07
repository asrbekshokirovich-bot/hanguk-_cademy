import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tokens.dart';
import 'glass.dart';

/// Renders an [AsyncValue] with the app's loading / error / empty treatment.
///
/// Errors are shown in Uzbek with a Retry, not swallowed: this app is
/// primarily used on flaky mobile connections in Uzbekistan, and a silently
/// blank panel is indistinguishable from "there are no lessons".
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
    this.loadingHeight = 160,
    this.isEmpty,
    this.emptyMessage = "Hozircha ma'lumot yo'q",
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  final double loadingHeight;
  final bool Function(T data)? isEmpty;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => SizedBox(
        height: loadingHeight,
        child: const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: HkColors.lime,
            ),
          ),
        ),
      ),
      error: (error, _) => GlassPanel(
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: HkColors.dangerBright,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Ma'lumotni yuklab bo'lmadi",
                    style: HkType.cardTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$error',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: HkType.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Qayta urinish',
                style: TextStyle(
                  fontFamily: HkType.family,
                  color: HkColors.lime,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      data: (data) {
        if (isEmpty?.call(data) ?? false) {
          return GlassPanel(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(emptyMessage, style: HkType.body),
              ),
            ),
          );
        }
        return builder(data);
      },
    );
  }
}
