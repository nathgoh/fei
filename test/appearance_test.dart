import 'package:fei/core/dates.dart';
import 'package:fei/data/database.dart';
import 'package:fei/state/providers.dart';
import 'package:fei/ui/app.dart';
import 'package:fei/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  group('buildColorScheme', () {
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
  });

  Future<(AppDatabase, SharedPreferences)> pumpApp(WidgetTester tester, [Map<String, Object> prefs = const {}]) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    late AppDatabase db;
    await tester.runAsync(() async {
      db = memoryDb();
      await db.allCategories();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), prefsProvider.overrideWithValue(sp)],
        child: const FeiApp(),
      ),
    );
    await settle(tester);
    return (db, sp);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('dashboard offers a way back to the current month', (tester) async {
    await pumpApp(tester);
    final now = today();
    final current = formatMonthYear(now.year, now.month);

    expect(find.text(current), findsOneWidget);
    expect(find.text('Back to $current'), findsNothing);

    await tester.tap(find.byTooltip('Previous'));
    await tester.tap(find.byTooltip('Previous'));
    await settle(tester);
    final twoBack = DateTime(now.year, now.month - 2);
    expect(find.text(formatMonthYear(twoBack.year, twoBack.month)), findsOneWidget);
    expect(find.text('Back to $current'), findsOneWidget);

    await tester.tap(find.text('Back to $current'));
    await settle(tester);
    expect(find.text(current), findsOneWidget);
    expect(find.text('Back to $current'), findsNothing);
    await unmount(tester);
  });

  testWidgets('appearance settings change the theme and persist', (tester) async {
    final (_, prefs) = await pumpApp(tester);
    ThemeData theme() => Theme.of(tester.element(find.byType(Scaffold).first));

    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.tap(find.text('Appearance'));
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Blue accent'));
    await settle(tester);
    expect(prefs.getInt('appearance.accent'), accentPresets['Blue']!.toARGB32());
    expect(theme().colorScheme.primary, buildColorScheme(accent: accentPresets['Blue']!).primary);

    // The custom picker must fit on a phone (layout overflow throws in tests).
    await tester.tap(find.bySemanticsLabel('Custom accent'));
    await settle(tester);
    expect(find.text('Custom colour'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), 'FF7043');
    await tester.tap(find.text('Use colour'));
    await settle(tester);
    expect(prefs.getInt('appearance.accent'), 0xFFFF7043);

    await tester.ensureVisible(find.text('Pure black'));
    await settle(tester);
    await tester.tap(find.text('Pure black'));
    await settle(tester);
    expect(prefs.getString('appearance.background'), 'black');
    expect(theme().scaffoldBackgroundColor, const Color(0xFF000000));

    await tester.tap(find.text('Reset'));
    await settle(tester);
    expect(prefs.getInt('appearance.accent'), isNull);
    expect(theme().colorScheme.primary, buildColorScheme().primary);
    await unmount(tester);
  });

  testWidgets('saved appearance is applied on launch', (tester) async {
    await pumpApp(tester, {
      'appearance.accent': accentPresets['Orange']!.toARGB32(),
      'appearance.background': 'neutral',
    });
    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    final expected = buildColorScheme(accent: accentPresets['Orange']!, background: BackgroundStyle.neutral);
    expect(theme.colorScheme.primary, expected.primary);
    expect(theme.scaffoldBackgroundColor, expected.surface);
    await unmount(tester);
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}
