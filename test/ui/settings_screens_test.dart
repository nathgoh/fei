import 'package:fei/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/db.dart';

Future<void> openSettingsPage(WidgetTester tester, String tile) async {
  await tester.tap(find.byTooltip('Settings'));
  await settle(tester);
  await tester.tap(find.text(tile));
  await settle(tester);
}

void main() {
  ThemeData theme(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first));

  group('appearance', () {
    testWidgets('accent, custom colour and background are applied and saved; reset restores defaults', (tester) async {
      final (_, prefs) = await pumpFei(tester);
      await openSettingsPage(tester, 'Appearance');

      await tester.tap(find.bySemanticsLabel('Blue accent'));
      await settle(tester);
      expect(prefs.getInt('appearance.accent'), accentPresets['Blue']!.toARGB32());
      expect(theme(tester).colorScheme.primary, buildColorScheme(accent: accentPresets['Blue']!).primary);

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
      expect(theme(tester).scaffoldBackgroundColor, const Color(0xFF000000));

      await tester.tap(find.text('Reset'));
      await settle(tester);
      expect(prefs.getInt('appearance.accent'), isNull);
      expect(prefs.getString('appearance.background'), isNull);
      expect(theme(tester).colorScheme.primary, buildColorScheme().primary);
      await unmount(tester);
    });

    testWidgets('cancelling the custom picker changes nothing', (tester) async {
      final (_, prefs) = await pumpFei(tester);
      await openSettingsPage(tester, 'Appearance');
      await tester.tap(find.bySemanticsLabel('Custom accent'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Hex'), '00FF00');
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(prefs.getInt('appearance.accent'), isNull);
      await unmount(tester);
    });

    testWidgets('a saved appearance is applied on launch', (tester) async {
      await pumpFei(
        tester,
        prefs: {'appearance.accent': accentPresets['Orange']!.toARGB32(), 'appearance.background': 'neutral'},
      );
      final expected = buildColorScheme(accent: accentPresets['Orange']!, background: BackgroundStyle.neutral);
      expect(theme(tester).colorScheme.primary, expected.primary);
      expect(theme(tester).scaffoldBackgroundColor, expected.surface);
      await unmount(tester);
    });
  });

  group('categories', () {
    testWidgets('flagging a category as a fixed cost', (tester) async {
      final (db, _) = await pumpFei(tester);
      await openSettingsPage(tester, 'Categories');
      expect(find.text('Fixed · excluded from flexible averages'), findsOneWidget); // Rent

      await scrollTo(tester, find.text('Utility'));
      await tester.tap(find.text('Utility'));
      await settle(tester);
      await tester.ensureVisible(find.text('Fixed cost'));
      await tester.tap(find.text('Fixed cost'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect((await dbRun(tester, () => categoryNamed(db, 'Utility'))).isFixed, isTrue);
      expect(find.text('Fixed · excluded from flexible averages'), findsNWidgets(2));
      await unmount(tester);
    });

    testWidgets('renaming a category', (tester) async {
      final (db, _) = await pumpFei(tester);
      await openSettingsPage(tester, 'Categories');
      await scrollTo(tester, find.text('Travel'));
      await tester.tap(find.text('Travel'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Trips');
      await tester.tap(find.text('Save'));
      await settle(tester);

      final names = (await dbRun(tester, db.allCategories)).map((c) => c.name);
      expect(names, contains('Trips'));
      expect(names, isNot(contains('Travel')));
      await unmount(tester);
    });
  });
}
