import 'package:flutter/material.dart';

import 'widgets/motion.dart';

/// Engram's design tokens for the app: the same values as frontend/src/styles/tokens.css, light
/// and dark side by side. Screens take colors from here or from the [ColorScheme] built from
/// them, never as literals. One accent, pine; no purple, indigo, violet or cyan.
@immutable
class EngramColors extends ThemeExtension<EngramColors> {
  const EngramColors({
    required this.paperTop,
    required this.paperBottom,
    required this.surface,
    required this.surfaceSunken,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.lineStrong,
    required this.pine,
    required this.onPine,
    required this.pineSoft,
    required this.danger,
    required this.onDanger,
    required this.ratingAgain,
    required this.ratingHard,
    required this.ratingGood,
    required this.ratingEasy,
    required this.chart,
    required this.glowPine,
    required this.glowWarm,
    required this.glassFill,
    required this.glassFillThin,
    required this.glassEdge,
    required this.glassHighlight,
    required this.scrim,
  });

  static const light = EngramColors(
    paperTop: Color(0xFFF4F2EE),
    paperBottom: Color(0xFFEBE8E2),
    surface: Color(0xFFFBFAF8),
    surfaceSunken: Color(0xFFEFEDE8),
    ink: Color(0xFF1C1B19),
    inkMuted: Color(0xFF57544E),
    line: Color(0x1F1C1B19),
    lineStrong: Color(0xFF7B776F),
    pine: Color(0xFF285F45),
    onPine: Color(0xFFFFFFFF),
    pineSoft: Color(0xFFE2EDE6),
    danger: Color(0xFFA3372B),
    onDanger: Color(0xFFFFFFFF),
    ratingAgain: Color(0xFFA3372B),
    ratingHard: Color(0xFF7D5110),
    ratingGood: Color(0xFF285F45),
    ratingEasy: Color(0xFF3A5A78),
    chart: [Color(0xFF8FBC9F), Color(0xFF5F9A78), Color(0xFF3A7656), Color(0xFF1F4D37)],
    glowPine: Color(0x1A285F45),
    glowWarm: Color(0x1FB07A30),
    glassFill: Color(0xD6FBFAF8),
    glassFillThin: Color(0x99FBFAF8),
    glassEdge: Color(0x1A1C1B19),
    glassHighlight: Color(0xB3FFFFFF),
    scrim: Color(0x471C1B19),
  );

  static const dark = EngramColors(
    paperTop: Color(0xFF141517),
    paperBottom: Color(0xFF191A1D),
    surface: Color(0xFF1E1F22),
    surfaceSunken: Color(0xFF18191B),
    ink: Color(0xFFECEAE6),
    inkMuted: Color(0xFFB0ADA6),
    line: Color(0x1FECEAE6),
    lineStrong: Color(0xFF75726C),
    pine: Color(0xFF7DB592),
    onPine: Color(0xFF10140F),
    pineSoft: Color(0xFF243429),
    danger: Color(0xFFE58A7E),
    onDanger: Color(0xFF1A0F0D),
    ratingAgain: Color(0xFFE58A7E),
    ratingHard: Color(0xFFD9A75A),
    ratingGood: Color(0xFF7DB592),
    ratingEasy: Color(0xFF93B3D1),
    chart: [Color(0xFF3D6B50), Color(0xFF5A8F6F), Color(0xFF7DB592), Color(0xFFB0DCBF)],
    glowPine: Color(0x147DB592),
    glowWarm: Color(0x0FD9A75A),
    glassFill: Color(0xE01E1F22),
    glassFillThin: Color(0x991E1F22),
    glassEdge: Color(0x1AECEAE6),
    glassHighlight: Color(0x0FFFFFFF),
    scrim: Color(0x80000000),
  );

  final Color paperTop;
  final Color paperBottom;
  final Color surface;
  final Color surfaceSunken;
  final Color ink;
  final Color inkMuted;
  final Color line;
  final Color lineStrong;
  final Color pine;
  final Color onPine;
  final Color pineSoft;
  final Color danger;
  final Color onDanger;
  final Color ratingAgain;
  final Color ratingHard;
  final Color ratingGood;
  final Color ratingEasy;

  /// One pine ramp, lightest to strongest in light mode: new → learning → young → mature.
  final List<Color> chart;

  /// Ambient light behind everything: pine from the top left, warm sand from the bottom right.
  /// It gives glass something to blur.
  final Color glowPine;
  final Color glowWarm;

  /// Glass, only for what floats above the page: the top bar, menus and sheets, and the review
  /// card. The regular fill is for glass that content scrolls under; the thin fill is for the
  /// review card, which only ever has the page behind it.
  final Color glassFill;
  final Color glassFillThin;
  final Color glassEdge;
  final Color glassHighlight;
  final Color scrim;

  Color rating(int value) => switch (value) {
    1 => ratingAgain,
    2 => ratingHard,
    3 => ratingGood,
    _ => ratingEasy,
  };

  @override
  EngramColors copyWith() => this;

  @override
  EngramColors lerp(EngramColors? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Radii from frontend/src/styles/index.css.
abstract final class Radii {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 14.0;
}

/// Motion tokens: deceleration only, no overshoot.
abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 280);
  static const ease = Cubic(0.2, 0, 0, 1);

  /// [duration], or nothing when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Glass blur, as the web's --glass-blur (a CSS blur radius is a standard deviation).
const glassBlur = 24.0;

const sansFamily = 'IBM Plex Sans';
const monoFamily = 'IBM Plex Mono';

extension EngramTheme on BuildContext {
  EngramColors get colors => Theme.of(this).extension<EngramColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? EngramColors.light : EngramColors.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.pine,
    onPrimary: c.onPine,
    primaryContainer: c.pineSoft,
    onPrimaryContainer: c.ink,
    secondary: c.pine,
    onSecondary: c.onPine,
    secondaryContainer: c.pineSoft,
    onSecondaryContainer: c.ink,
    tertiary: c.ratingEasy,
    onTertiary: c.surface,
    error: c.danger,
    onError: c.onDanger,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.inkMuted,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceSunken,
    surfaceContainerHighest: c.surfaceSunken,
    outline: c.lineStrong,
    outlineVariant: c.line,
    shadow: c.ink,
    scrim: c.ink,
    inverseSurface: c.ink,
    onInverseSurface: c.surface,
    inversePrimary: c.pineSoft,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: sansFamily,
    scaffoldBackgroundColor: Colors.transparent,
    extensions: [c],
  );
  const smallShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(Radii.sm)),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: c.line)),
      titleTextStyle: TextStyle(
        fontFamily: sansFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: smallShape,
        textStyle: const TextStyle(
          fontFamily: sansFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: c.ink,
        backgroundColor: c.surface,
        side: BorderSide(color: c.lineStrong),
        shape: smallShape,
        textStyle: const TextStyle(
          fontFamily: sansFamily,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: smallShape,
        side: BorderSide(color: c.lineStrong),
        selectedBackgroundColor: c.pineSoft,
        selectedForegroundColor: c.ink,
        foregroundColor: c.inkMuted,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.pine, shape: smallShape),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
        borderSide: BorderSide(color: c.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
        borderSide: BorderSide(color: c.pine, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.pineSoft,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(fontFamily: sansFamily, color: c.surface),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.pine),
    // Pages rise in, as on the web: a fade and a few pixels of lift, and nothing slides.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: RiseInPageTransitionsBuilder(),
        TargetPlatform.iOS: RiseInPageTransitionsBuilder(),
      },
    ),
  );
}
