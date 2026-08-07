import 'package:flutter/widgets.dart';

/// Design tokens lifted verbatim from the "Hanguk Academy Online" handoff
/// (`README.md` § Design Tokens). Nothing here is invented — if a value needs
/// to change, change it in the handoff first so the two stay in step.
abstract final class HkColors {
  // Brand
  static const royalBlue = Color(0xFF1A3A6C);
  static const royalBlue700 = Color(0xFF132A4D);
  static const royalBlue800 = Color(0xFF0F213D);
  static const royalBlue900 = Color(0xFF0A0A1A);

  /// The single accent. Used for the active dock pill, primary CTAs, live
  /// state and progress. Everything else on the canvas is white-on-glass.
  static const lime = Color(0xFFD4E94C);
  static const limeBright = Color(0xFFE2F25C);
  static const lime600 = Color(0xFFC2DA2E);
  static const lime700 = Color(0xFFA8C014);

  /// Text colour that sits on top of a lime fill. Lime is far too light to
  /// carry white text at any weight.
  static const ink = Color(0xFF16203A);

  // Dark canvas
  static const canvasTop = Color(0xFF0B1126);
  static const canvasMid = Color(0xFF0E1733);
  static const canvasBottom = Color(0xFF090D20);
  static const windowNavy = Color(0xFF0F2547);
  static const pageBlack = Color(0xFF05070F);

  // Ambient orbs
  static const orbBlue = Color(0xFF2E5FA8);
  static const orbLime = lime;
  static const orbViolet = Color(0xFF5B3FB0);
  static const orbTeal = Color(0xFF1E8A7A);

  // Text on dark
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0x99FFFFFF); // white 60%
  static const textTertiary = Color(0x73FFFFFF); // white 45%

  // Semantic
  static const success = Color(0xFF15A05A);
  static const successBright = Color(0xFF34C77B);
  static const warning = Color(0xFFE08600);
  static const warningBright = Color(0xFFF0B24A);
  static const danger = Color(0xFFDC2626);
  static const dangerBright = Color(0xFFF2746A);
  static const infoText = Color(0xFF9DC2F5);

  // macOS-style traffic lights on the desktop title bar
  static const trafficRed = Color(0xFFFF5F57);
  static const trafficAmber = Color(0xFFFEBC2E);
  static const trafficGreen = Color(0xFF28C840);
}

/// The glass recipe, reused on every panel. Deliberately shadow-light: the
/// handoff calls for an inset edge highlight, *not* a drop shadow — heavy
/// shadows on a dark canvas read as smudge rather than depth.
abstract final class HkGlass {
  static const fillTop = Color(0x1AFFFFFF); // white 10%
  static const fillBottom = Color(0x09FFFFFF); // white 3.5%
  static const border = Color(0x1FFFFFFF); // white 12%
  static const edgeHighlight = Color(0x29FFFFFF); // white 16%
  static const blurSigma = 22.0;

  static const gradient = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [fillTop, fillBottom],
  );

  /// Hover / pressed fill for dock and icon buttons.
  static const hoverFill = Color(0x1AFFFFFF);
}

abstract final class HkRadius {
  static const pill = 999.0;
  static const card = 22.0;
  static const cardLarge = 26.0;
  static const cardSmall = 16.0;
  static const control = 14.0;
  static const chip = 12.0;
}

abstract final class HkSpace {
  static const base = 4.0;
  static const contentPadding = 30.0;
  static const gridGap = 16.0;
  static const gridGapWide = 18.0;
  static const cardPadding = 22.0;
}

abstract final class HkType {
  static const family = 'Inter';
  static const mono = 'JetBrainsMono';

  /// Korean glyphs are not in the Inter subset; without this they render as
  /// tofu boxes wherever a lesson title carries hangul.
  static const fallback = <String>['NotoSansKR'];

  static const TextStyle display = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    height: 1.15,
    color: HkColors.textPrimary,
  );

  static const TextStyle heroTitle = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.56,
    height: 1.2,
    color: HkColors.textPrimary,
  );

  static const TextStyle pageTitle = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    height: 1.2,
    color: HkColors.textPrimary,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: HkColors.textPrimary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: HkColors.textPrimary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: HkColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
    color: HkColors.textSecondary,
  );

  static const TextStyle muted = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: HkColors.textTertiary,
  );

  static const TextStyle chip = TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: HkColors.textPrimary,
  );

  /// Tabular figures for clock columns and durations, so the schedule's time
  /// column doesn't jitter between rows.
  static const TextStyle monoTime = TextStyle(
    fontFamily: mono,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: HkColors.textPrimary,
  );
}

/// The lime fill used on active dock pills and primary CTAs.
const kLimeGradient = LinearGradient(
  begin: Alignment(-0.5, -1),
  end: Alignment(0.5, 1),
  colors: [Color(0xF2E2F25C), Color(0xD9C2DA2E)],
);
