import 'package:fei/data/database.dart';
import 'package:fei/state/providers.dart';
import 'package:fei/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';

/// Pumps the whole app on a phone-sized screen (Pixel 9) with an in-memory
/// database. [seed] runs before the first frame, so the screens start with
/// that data.
///
/// Drift does real I/O, which the widget tester's fake-async zone can't
/// advance, so database work goes through `runAsync` and [settle].
Future<(AppDatabase, SharedPreferences)> pumpFei(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  Future<void> Function(AppDatabase db)? seed,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  late AppDatabase db;
  await tester.runAsync(() async {
    db = memoryDb();
    await db.allCategories(); // opens and seeds the database
    await seed?.call(db);
  });
  // The router is app-global, so reset it or the previous test's route leaks in.
  router.go('/dashboard');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), prefsProvider.overrideWithValue(sp)],
      child: const FeiApp(),
    ),
  );
  await settle(tester);
  return (db, sp);
}

/// Lets pending database work finish, then settles animations.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

/// Runs real (non-fake-async) database work from inside a widget test.
Future<T> dbRun<T>(WidgetTester tester, Future<T> Function() body) async => (await tester.runAsync(body)) as T;

/// Unmounts the app so drift's stream-cleanup timers fire inside the test.
/// The in-memory database needs no explicit close.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Switches tabs via the bottom bar (the destination must not be the current tab).
Future<void> openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.byTooltip(tab)));
  await settle(tester);
}

/// Scrolls the current screen's main list until [finder] is built and visible.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first,
  );
  await settle(tester);
}

/// Checks that the search field showing [hint] centers the hint vertically, level with its search icon.
void expectHintCentered(WidgetTester tester, String hint) {
  final field = find.widgetWithText(TextField, hint);
  final box = tester.getRect(find.descendant(of: field, matching: find.byType(InputDecorator)));
  final text = tester.getRect(find.descendant(of: field, matching: find.text(hint)));
  final icon = tester.getRect(find.descendant(of: field, matching: find.byIcon(Icons.search)));
  expect(text.center.dy, moreOrLessEquals(box.center.dy, epsilon: 0.5));
  expect(text.center.dy, moreOrLessEquals(icon.center.dy, epsilon: 0.5));
}
