import 'package:fei/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pure black and neutral backgrounds are untinted', () {
    final black = buildColorScheme(accent: accentPresets['Purple']!, theme: ThemeStyle.black);
    expect(black.surface, const Color(0xFF000000));
    final neutral = buildColorScheme(accent: accentPresets['Purple']!, theme: ThemeStyle.neutral);
    expect(neutral.surface.r, neutral.surface.g);
    expect(neutral.surfaceContainer.g, neutral.surfaceContainer.b);
  });

  test('tinted background and primary follow the accent', () {
    final blue = buildColorScheme(accent: accentPresets['Blue']!);
    expect(blue.surface.b, greaterThan(blue.surface.r));
    expect(blue.primary.b, greaterThan(blue.primary.r));
    final orange = buildColorScheme(accent: accentPresets['Orange']!);
    expect(orange.primary.r, greaterThan(orange.primary.b));
  });

  test('surfaces step away from the background, from lowest to highest, for every theme', () {
    for (final style in ThemeStyle.values) {
      final s = buildColorScheme(theme: style);
      final tones = [
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
      ].map((c) => c.computeLuminance()).toList();
      // Dark themes raise surfaces by lightening them; the light theme by darkening.
      final light = style == ThemeStyle.light;
      for (var i = 1; i < tones.length; i++) {
        expect(
          tones[i],
          light ? lessThanOrEqualTo(tones[i - 1]) : greaterThanOrEqualTo(tones[i - 1]),
          reason: '$style step $i',
        );
      }
    }
  });

  test('dialogs sit below input fills so text fields stay visible', () {
    for (final style in ThemeStyle.values) {
      final t = buildTheme(theme: style);
      expect(t.brightness, style == ThemeStyle.light ? Brightness.light : Brightness.dark);
      expect(t.scaffoldBackgroundColor, t.colorScheme.surface);
      expect(t.dialogTheme.backgroundColor, isNot(t.inputDecorationTheme.fillColor), reason: '$style');
    }
  });

  test('every preset and theme has a label', () {
    expect(accentPresets, hasLength(10));
    expect(accentPresets.values, contains(defaultAccent));
    expect(ThemeStyle.values.map(themeLabel), ['Tinted', 'Light', 'Dark', 'AMOLED Dark']);
  });
}
