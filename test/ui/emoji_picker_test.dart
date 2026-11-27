import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' show EmojiCell, EmojiPicker;
// The package's documented hook for clearing its static recent-emoji cache between tests.
// ignore: implementation_imports
import 'package:emoji_picker_flutter/src/emoji_picker_internal_utils.dart' show EmojiPickerInternalUtils;
import 'package:fei/ui/emoji_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/db.dart';

/// Opens the edit dialog for the Travel (✈️) category.
Future<void> editTravel(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await settle(tester);
  await tester.tap(find.text('Categories'));
  await settle(tester);
  await scrollTo(tester, find.text('Travel'));
  await tester.tap(find.text('Travel'));
  await settle(tester);
}

Finder get iconPreview => find.byTooltip('Choose icon');
Finder inPreview(String emoji) => find.descendant(of: iconPreview, matching: find.text(emoji));
Finder inSheet(String emoji) => find.descendant(of: find.byType(EmojiPickerSheet), matching: find.text(emoji));

void main() {
  // pumpFei resets SharedPreferences, but the package also keeps recents in memory.
  setUp(EmojiPickerInternalUtils.resetCaches);

  testWidgets('tapping the icon opens the picker; a searched emoji becomes the icon and is saved', (tester) async {
    final (db, _) = await pumpFei(tester);
    await editTravel(tester);
    expect(inPreview('✈️'), findsOneWidget);

    await tester.tap(iconPreview);
    await settle(tester);
    expect(find.byType(EmojiPicker), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Search emoji'), 'rocket');
    await settle(tester);
    expect(find.byType(EmojiPicker), findsNothing); // results replace the category grid
    await tester.tap(inSheet('🚀').first);
    await settle(tester);

    expect(find.byType(EmojiPickerSheet), findsNothing);
    expect(inPreview('🚀'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect((await dbRun(tester, () => categoryNamed(db, 'Travel'))).emoji, '🚀');
    await unmount(tester);
  });

  testWidgets('picking from a picker category, via the quick-pick row\'s More button', (tester) async {
    final (db, _) = await pumpFei(tester);
    await editTravel(tester);
    await tester.tap(find.byTooltip('More emoji'));
    await settle(tester);
    // With nothing picked before, it opens on smileys rather than an empty Recent tab.
    expect(inSheet('😀'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(EmojiPicker), matching: find.byIcon(Icons.location_city)));
    await settle(tester);
    await tester.tap(inSheet('🌋'));
    await settle(tester);
    expect(inPreview('🌋'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await settle(tester);
    expect((await dbRun(tester, () => categoryNamed(db, 'Travel'))).emoji, '🌋');
    await unmount(tester);
  });

  testWidgets('emoji picked before, from the grid or a search, open the picker on the Recent tab', (tester) async {
    await pumpFei(tester);
    await editTravel(tester);
    await tester.tap(iconPreview);
    await settle(tester);
    await tester.tap(inSheet('😀'));
    await settle(tester);
    await tester.tap(iconPreview);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Search emoji'), 'rocket');
    await settle(tester);
    await tester.tap(inSheet('🚀').first);
    await settle(tester);

    await tester.tap(iconPreview);
    await settle(tester);
    expect(find.text('Emoji you pick show up here'), findsNothing);
    expect(inSheet('😀'), findsOneWidget);
    expect(inSheet('🚀'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a search with no matches says so', (tester) async {
    await pumpFei(tester);
    await editTravel(tester);
    await tester.tap(iconPreview);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Search emoji'), 'qqqzzz');
    await settle(tester);
    expect(find.text('No matching emoji'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('dismissing the picker keeps the current icon', (tester) async {
    final (db, _) = await pumpFei(tester);
    await editTravel(tester);
    await tester.tap(iconPreview);
    await settle(tester);
    await tester.tapAt(const Offset(20, 20)); // the barrier above the sheet
    await settle(tester);

    expect(find.byType(EmojiPickerSheet), findsNothing);
    expect(inPreview('✈️'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect((await dbRun(tester, () => categoryNamed(db, 'Travel'))).emoji, '✈️');
    await unmount(tester);
  });

  testWidgets('the quick-pick row still sets the icon', (tester) async {
    final (db, _) = await pumpFei(tester);
    await editTravel(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('🚗')));
    await settle(tester);
    expect(inPreview('🚗'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect((await dbRun(tester, () => categoryNamed(db, 'Travel'))).emoji, '🚗');
    await unmount(tester);
  });

  testWidgets('the search field, tabs and emoji grid share the same left and right edges', (tester) async {
    await pumpFei(tester);
    await editTravel(tester);
    await tester.tap(iconPreview);
    await settle(tester);

    final sheet = tester.getRect(find.byType(EmojiPickerSheet));
    final field = tester.getRect(find.widgetWithText(TextField, 'Search emoji'));
    // Inset the same as the app's other sheets.
    expect(field.left - sheet.left, 16);
    expect(sheet.right - field.right, 16);
    expectHintCentered(tester, 'Search emoji');

    void expectGridAligned() {
      final cells = find.descendant(of: find.byType(EmojiPickerSheet), matching: find.byType(EmojiCell));
      final rects = [for (var i = 0; i < cells.evaluate().length; i++) tester.getRect(cells.at(i))];
      final firstRow = rects.where((r) => r.top == rects.first.top).toList();
      expect(firstRow.length, greaterThan(1));
      expect(firstRow.first.left, moreOrLessEquals(field.left));
      expect(firstRow.last.right, moreOrLessEquals(field.right));
    }

    final tabs = tester.getRect(find.descendant(of: find.byType(EmojiPicker), matching: find.byType(TabBar)));
    expect(tabs.left, field.left);
    expect(tabs.right, field.right);
    expectGridAligned();

    await tester.enterText(find.widgetWithText(TextField, 'Search emoji'), 'money');
    await settle(tester);
    expectGridAligned();
    await unmount(tester);
  });

  for (final background in ['light', 'neutral']) {
    testWidgets('the picker matches the bottom sheet in the $background theme', (tester) async {
      await pumpFei(tester, prefs: {'appearance.background': background});
      await editTravel(tester);
      await tester.tap(iconPreview);
      await settle(tester);

      final theme = Theme.of(tester.element(find.byType(EmojiPickerSheet)));
      final config = tester.widget<EmojiPicker>(find.byType(EmojiPicker)).config;
      expect(config.emojiViewConfig.backgroundColor, theme.bottomSheetTheme.backgroundColor);
      expect(config.categoryViewConfig.backgroundColor, theme.bottomSheetTheme.backgroundColor);
      expect(config.categoryViewConfig.iconColorSelected, theme.colorScheme.primary);
      await unmount(tester);
    });
  }
}
