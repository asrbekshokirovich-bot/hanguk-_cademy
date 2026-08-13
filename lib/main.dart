import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'design_system/tokens.dart';
import 'design_system/widgets/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every date on screen is Uzbek ("22-iyun", "Du"). Without this the first
  // DateFormat('d-MMMM', 'uz') throws at build time rather than falling back.
  await initializeDateFormatting('uz');

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        // The size the window restores to when un-maximised. The design is
        // drawn at 1440x920; minimumSize is the point below which the
        // expanded layout stops fitting and the medium one takes over.
        size: Size(1440, 920),
        minimumSize: Size(880, 620),
        center: true,
        title: "Hanguk Academy — Onlayn ta'lim platformasi",
        backgroundColor: HkColors.canvasBottom,
        // The app draws its own title bar (HkWindowChrome). Windows' grey
        // strip above a window built entirely of dark glass looked like a
        // piece of another program bolted to the top of the design.
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
        await _fillTheScreen();
        await windowManager.focus();
      },
    );
  }

  if (HkEnv.hasSupabase) {
    await Supabase.initialize(
      url: HkEnv.supabaseUrl,
      publishableKey: HkEnv.supabasePublishableKey,
    );
  }

  runApp(const ProviderScope(child: HangukOnlineApp()));
}

/// Opens the window over the whole work area — the screen minus the taskbar.
///
/// Sized rather than maximised, and that is the entire point. A window that
/// hides the system title bar has no system frame either, and Windows
/// maximises such a window to the monitor rectangle *plus* the invisible
/// resize border it would normally have had. Those few pixels a side hang off
/// every edge of the screen, and what hangs off the right edge is the close
/// button. The app looked correct and could not be closed.
///
/// Asking the display how big it actually is avoids the whole question: the
/// window is an ordinary sized window that happens to cover the desktop, so
/// nothing is off-screen. `visiblePosition` is not always (0,0) — a taskbar
/// docked left or top moves it, as does a second monitor.
///
/// Maximising still works afterwards; it is the user's to do, from the title
/// bar button or `Win`+`Up`.
Future<void> _fillTheScreen() async {
  final display = await screenRetriever.getPrimaryDisplay();
  final origin = display.visiblePosition ?? Offset.zero;
  final size = display.visibleSize ?? display.size;
  await windowManager.setBounds(
    Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height),
  );
}

/// `Platform` is unavailable on web, so the check has to be guarded by
/// [kIsWeb] before it is evaluated.
bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

class HangukOnlineApp extends ConsumerWidget {
  const HangukOnlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: "Hanguk Academy — Onlayn ta'lim",
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(appRouterProvider),
      theme: hangukTheme,
      // Wrapped here rather than inside AppShell: the login and
      // change-password screens do not use the shell, and a window that loses
      // its close button on the one screen you reach before signing in is a
      // window you cannot close. On web and mobile this adds nothing.
      builder: (context, child) => HkWindowChrome(child: child!),
    );
  }
}

/// One dark theme. The product has no light mode: the entire design is built
/// on translucent glass over a dark ambient canvas, and a light variant would
/// be a different design rather than a recoloured one.
final ThemeData hangukTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: HkColors.canvasBottom,
  fontFamily: HkType.family,
  fontFamilyFallback: HkType.fallback,
  colorScheme: const ColorScheme.dark(
    primary: HkColors.lime,
    onPrimary: HkColors.ink,
    secondary: HkColors.royalBlue,
    surface: HkColors.canvasMid,
    error: HkColors.danger,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: HkColors.royalBlue800,
    contentTextStyle: HkType.body.copyWith(color: HkColors.textPrimary),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(HkRadius.control),
    ),
  ),
  tooltipTheme: TooltipThemeData(
    decoration: BoxDecoration(
      color: HkColors.royalBlue800,
      borderRadius: BorderRadius.circular(8),
    ),
    textStyle: HkType.muted.copyWith(color: HkColors.textPrimary),
  ),
  // The dark canvas makes Material's default splash read as a grey smear;
  // the app signals press through hover/scale instead.
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
);
