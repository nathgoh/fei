import 'package:flutter/material.dart';

/// Income is green; expenses use the normal text colour, as in Monarch.
const incomeGreen = Color(0xFF66BB6A);
const negativeRed = Color(0xFFEF5350);

/// Expense bars in charts, distinct from the income green.
const expenseOrange = Color(0xFFFF8A65);

/// Accent presets offered in Settings → Appearance.
const accentPresets = <String, Color>{
  'Teal': Color(0xFF26A69A),
  'Blue': Color(0xFF2979FF),
  'Indigo': Color(0xFF5C6BC0),
  'Purple': Color(0xFF8E24AA),
  'Pink': Color(0xFFEC407A),
  'Red': Color(0xFFE53935),
  'Orange': Color(0xFFFF7043),
  'Amber': Color(0xFFFFB300),
  'Green': Color(0xFF43A047),
  'Slate': Color(0xFF607D8B),
};

const defaultAccent = Color(0xFF26A69A);

enum BackgroundStyle {
  /// Dark surfaces tinted towards the accent colour.
  tinted,

  /// Neutral greys with no tint.
  neutral,

  /// True black, which saves power on OLED screens.
  black,
}

String backgroundLabel(BackgroundStyle b) => switch (b) {
  BackgroundStyle.tinted => 'Tinted',
  BackgroundStyle.neutral => 'Neutral',
  BackgroundStyle.black => 'Pure black',
};

/// Surface tones (surface, lowest, low, container, high, highest) for the
/// untinted styles.
const _neutralSurfaces = [0xFF121212, 0xFF0D0D0D, 0xFF1A1A1A, 0xFF1F1F1F, 0xFF292929, 0xFF333333];
const _blackSurfaces = [0xFF000000, 0xFF000000, 0xFF0B0B0B, 0xFF131313, 0xFF1D1D1D, 0xFF272727];

ColorScheme buildColorScheme({Color accent = defaultAccent, BackgroundStyle background = BackgroundStyle.tinted}) {
  // "fidelity" keeps the generated primary close to the chosen colour, so a
  // swatch looks like what you get.
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final tones = switch (background) {
    BackgroundStyle.tinted => null,
    BackgroundStyle.neutral => _neutralSurfaces,
    BackgroundStyle.black => _blackSurfaces,
  };
  if (tones == null) return scheme;
  return scheme.copyWith(
    surface: Color(tones[0]),
    surfaceContainerLowest: Color(tones[1]),
    surfaceContainerLow: Color(tones[2]),
    surfaceContainer: Color(tones[3]),
    surfaceContainerHigh: Color(tones[4]),
    surfaceContainerHighest: Color(tones[5]),
    surfaceDim: Color(tones[0]),
    surfaceBright: Color(tones[5]),
  );
}

ThemeData buildDarkTheme({Color accent = defaultAccent, BackgroundStyle background = BackgroundStyle.tinted}) {
  final scheme = buildColorScheme(accent: accent, background: background);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: scheme.surface),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surfaceContainerLow),
    // One step below input fills (surfaceContainerHigh) so text fields stay visible in dialogs.
    dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainer),
  );
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isWide => MediaQuery.sizeOf(this).width >= 840;
}
