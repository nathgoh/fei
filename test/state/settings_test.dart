import 'package:fei/state/appearance.dart';
import 'package:fei/state/providers.dart';
import 'package:fei/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProviderContainer, SharedPreferences)> container([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(sp)]);
  addTearDown(c.dispose);
  return (c, sp);
}

void main() {
  test('yearRange and monthRange are inclusive YYYY-MM-DD bounds', () {
    expect(yearRange(2026), (from: '2026-01-01', to: '2026-12-31'));
    expect(monthRange(2026, 2), (from: '2026-02-01', to: '2026-02-28'));
    expect(monthRange(2028, 2).to, '2028-02-29');
  });

  group('appearance', () {
    test('defaults to the teal accent on a tinted background', () async {
      final (c, _) = await container();
      final a = c.read(appearanceProvider);
      expect(a.accent, defaultAccent);
      expect(a.theme, ThemeStyle.tinted);
    });

    test('changes are saved and survive a restart', () async {
      final (c, sp) = await container();
      await c.read(appearanceProvider.notifier).setAccent(accentPresets['Purple']!);
      await c.read(appearanceProvider.notifier).setTheme(ThemeStyle.black);
      expect(sp.getInt('appearance.accent'), accentPresets['Purple']!.toARGB32());
      expect(sp.getString('appearance.background'), 'black');

      final (restarted, _) = await container({
        'appearance.accent': sp.getInt('appearance.accent')!,
        'appearance.background': sp.getString('appearance.background')!,
      });
      expect(restarted.read(appearanceProvider).accent, accentPresets['Purple']);
      expect(restarted.read(appearanceProvider).theme, ThemeStyle.black);
    });

    test('reset clears saved values; unknown saved values fall back to defaults', () async {
      final (c, sp) = await container({'appearance.accent': 0xFF123456, 'appearance.background': 'plaid'});
      expect(c.read(appearanceProvider).accent, const Color(0xFF123456));
      expect(c.read(appearanceProvider).theme, ThemeStyle.tinted);

      await c.read(appearanceProvider.notifier).reset();
      expect(c.read(appearanceProvider).accent, defaultAccent);
      expect(sp.getInt('appearance.accent'), isNull);
      expect(sp.getString('appearance.background'), isNull);
    });
  });
}
