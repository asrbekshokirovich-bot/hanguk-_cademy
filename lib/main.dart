import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'design_system/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every date on screen is Uzbek ("22-iyun", "Du"). Without this the first
  // DateFormat('d-MMMM', 'uz') throws at build time rather than falling back.
  await initializeDateFormatting('uz');

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        // The restore-down size, deliberately smaller than the 1440x920 the
        // design was drawn at. WindowOptions.size is in logical pixels, and
        // a 1920x1080 screen at Windows' 125% scaling is only 1536x864 of
        // those: a 920-tall window does not fit on it. Centred, it hung off
        // both edges, and the title bar ended up above the top of the
        // display — which is why the minimise and maximise buttons were
        // missing and only a stripe carrying the close button showed.
        //
        // 1280x800 fits every laptop the academy is likely to use, 125%
        // scaling included, and the expanded layout still has room.
        size: Size(1280, 800),
        minimumSize: Size(880, 620),
        center: true,
        title: "Hanguk Academy — Onlayn ta'lim platformasi",
        backgroundColor: HkColors.canvasBottom,
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );

    // Outside waitUntilReadyToShow on purpose. Inside that callback the
    // window is mid-way through being presented, and a maximise issued
    // there is silently dropped — twice now.
    await windowManager.maximize();
  }

  if (HkEnv.hasSupabase) {
    await Supabase.initialize(
      url: HkEnv.supabaseUrl,
      publishableKey: HkEnv.supabasePublishableKey,
    );
  }

  runApp(const ProviderScope(child: HangukOnlineApp()));
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
