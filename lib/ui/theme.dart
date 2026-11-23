import 'package:flutter/material.dart';

/// Income is green; expenses use the normal text color, as in Monarch.
/// These suit dark backgrounds; read them through [ThemeX] so the light theme
/// gets darker shades that stay legible on white.
const incomeGreen = Color(0xFF66BB6A);
const negativeRed = Color(0xFFEF5350);

/// Expense bars in charts, distinct from the income green.
const expenseOrange = Color(0xFFFF8A65);

const _incomeGreenLight = Color(0xFF2E7D32);
const _negativeRedLight = Color(0xFFC62828);
const _expenseOrangeLight = Color(0xFFE64A19);
const _savingsBlue = Color(0xFF64B5F6);
const _savingsBlueLight = Color(0xFF1976D2);

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

/// The app theme. Value names are what gets saved, so `neutral` and `black`
/// keep their original names.
enum ThemeStyle {
  /// Dark surfaces tinted towards the accent color.
  tinted,

  /// Light neutral greys.
  light,

  /// Dark neutral greys with no tint.
  neutral,

  /// True black, which saves power on OLED screens.
  black,
}

String themeLabel(ThemeStyle t) => switch (t) {
  ThemeStyle.tinted => 'Tinted',
  ThemeStyle.light => 'Light',
  ThemeStyle.neutral => 'Dark',
  ThemeStyle.black => 'AMOLED Dark',
};

/// Surface tones (surface, lowest, low, container, high, highest) for the
/// untinted styles.
const _lightSurfaces = [0xFFF7F7F7, 0xFFFFFFFF, 0xFFF1F1F1, 0xFFEBEBEB, 0xFFE3E3E3, 0xFFDCDCDC];
const _neutralSurfaces = [0xFF121212, 0xFF0D0D0D, 0xFF1A1A1A, 0xFF1F1F1F, 0xFF292929, 0xFF333333];
const _blackSurfaces = [0xFF000000, 0xFF000000, 0xFF0B0B0B, 0xFF131313, 0xFF1D1D1D, 0xFF272727];

ColorScheme buildColorScheme({Color accent = defaultAccent, ThemeStyle theme = ThemeStyle.tinted}) {
  // "fidelity" keeps the generated primary close to the chosen color, so a
  // swatch looks like what you get.
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: theme == ThemeStyle.light ? Brightness.light : Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final tones = switch (theme) {
    ThemeStyle.tinted => null,
    ThemeStyle.light => _lightSurfaces,
    ThemeStyle.neutral => _neutralSurfaces,
    ThemeStyle.black => _blackSurfaces,
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

ThemeData buildTheme({Color accent = defaultAccent, ThemeStyle theme = ThemeStyle.tinted}) {
  final scheme = buildColorScheme(accent: accent, theme: theme);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: scheme.brightness);
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
      border: UnderlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isWide => MediaQuery.sizeOf(this).width >= 840;

  bool get _isLight => Theme.of(this).brightness == Brightness.light;
  Color get incomeColor => _isLight ? _incomeGreenLight : incomeGreen;
  Color get negativeColor => _isLight ? _negativeRedLight : negativeRed;
  Color get expenseColor => _isLight ? _expenseOrangeLight : expenseOrange;
  Color get savingsColor => _isLight ? _savingsBlueLight : _savingsBlue;
}
