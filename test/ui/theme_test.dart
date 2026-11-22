import 'package:fei/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pure black and neutral backgrounds are untinted', () {
    final black = buildColorScheme(accent: accentPresets['Purple']!, background: BackgroundStyle.black);
    expect(black.surface, const Color(0xFF000000));
    final neutral = buildColorScheme(accent: accentPresets['Purple']!, background: BackgroundStyle.neutral);
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

  test('surfaces get lighter from lowest to highest for every style', () {
    for (final style in BackgroundStyle.values) {
      final s = buildColorScheme(background: style);
      final tones = [
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
      ].map((c) => c.computeLuminance()).toList();
      for (var i = 1; i < tones.length; i++) {
        expect(tones[i], greaterThanOrEqualTo(tones[i - 1]), reason: '$style step $i');
      }
    }
  });

  test('dark theme: dialogs sit below input fills so text fields stay visible', () {
    for (final style in BackgroundStyle.values) {
      final t = buildDarkTheme(background: style);
      expect(t.brightness, Brightness.dark);
      expect(t.scaffoldBackgroundColor, t.colorScheme.surface);
      expect(t.dialogTheme.backgroundColor, isNot(t.inputDecorationTheme.fillColor), reason: '$style');
    }
  });

  test('every preset and background has a label', () {
    expect(accentPresets, hasLength(10));
    expect(accentPresets.values, contains(defaultAccent));
    expect(BackgroundStyle.values.map(backgroundLabel), ['Tinted', 'Neutral', 'Pure black']);
  });
}
