import 'package:fei/data/database.dart';
import 'package:fei/state/providers.dart';
import 'package:fei/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  testWidgets('navigates every tab and adds a transaction', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    late AppDatabase db;
    await tester.runAsync(() async {
      db = memoryDb();
      await db.allCategories(); // open + seed outside the fake-async zone
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), prefsProvider.overrideWithValue(prefs)],
        child: const FeiApp(),
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
    }

    await settle();
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('No spending this month.'), findsOneWidget);

    // Add an expense through the form.
    await tester.tap(find.byTooltip('Add transaction'));
    await settle();
    await tester.enterText(find.byType(TextField).first, '42.50');
    await tester.tap(find.text('Choose a category'));
    await settle();
    await tester.tap(find.text('Grocery'));
    await settle();
    await tester.tap(find.text('Add transaction').last);
    await settle();

    // Shows up in the summary and the category breakdown.
    expect(find.text(r'$42.50'), findsWidgets);
    expect(find.text('No spending this month.'), findsNothing);

    for (final tab in ['Transactions', 'Cash Flow', 'Recurring', 'Assistant']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(_iconFor(tab))));
      await settle();
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('Connect your Ollama server'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await settle();
    expect(find.text('Import & export'), findsOneWidget);

    // Unmount and let drift's stream-cleanup timers (in the fake-async zone)
    // fire. The in-memory database needs no explicit close.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

IconData _iconFor(String tab) => switch (tab) {
  'Transactions' => Icons.receipt_long_outlined,
  'Cash Flow' => Icons.insights_outlined,
  'Recurring' => Icons.event_repeat_outlined,
  _ => Icons.auto_awesome_outlined,
};
