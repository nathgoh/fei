import 'package:fei/core/dates.dart';
import 'package:fei/data/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/db.dart';

void main() {
  final now = today();
  final firstOfMonth = ymd(DateTime(now.year, now.month, 1));

  Future<void> seedMonth(AppDatabase db) async {
    await addTxn(db, category: 'Paycheck', cents: 400000, date: firstOfMonth, merchant: 'Acme Corp');
    await addTxn(db, category: 'Grocery', cents: 4550, date: firstOfMonth, merchant: 'Costco');
    await addTxn(db, category: 'Food & Dining', cents: 1200, date: firstOfMonth, merchant: 'Chipotle');
  }

  Future<void> chooseMenu(WidgetTester tester, String chip, String option) async {
    await tester.tap(find.text(chip));
    await settle(tester);
    await tester.tap(find.text(option).last);
    await settle(tester);
  }

  testWidgets('adding a transaction from the dashboard', (tester) async {
    final (db, _) = await pumpFei(tester);
    await tester.tap(find.byTooltip('Add transaction'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '42.50');
    await tester.tap(find.text('Choose a category'));
    await settle(tester);
    await tester.tap(find.text('Grocery'));
    await settle(tester);
    await tester.tap(find.text('Add transaction').last);
    await settle(tester);

    final t = (await dbRun(tester, db.transactionsBetween)).single;
    expect(t.amountCents, 4250);
    expect(t.kind, TxKind.expense);
    expect(t.date, todayYmd());
    expect(find.text(r'$42.50'), findsWidgets);
    expect(find.text('No spending this month.'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the form insists on an amount and a category', (tester) async {
    final (db, _) = await pumpFei(tester);
    await openTab(tester, 'Transactions');
    await tester.tap(find.byTooltip('Add transaction'));
    await settle(tester);
    await tester.tap(find.text('Add transaction').last);
    await settle(tester);
    expect(await dbRun(tester, db.transactionsBetween), isEmpty);

    await tester.enterText(find.byType(TextField).first, '10');
    await tester.tap(find.text('Add transaction').last);
    await settle(tester);
    expect(find.text('Pick a category'), findsOneWidget);
    expect(await dbRun(tester, db.transactionsBetween), isEmpty);
    await unmount(tester);
  });

  testWidgets('Repeat creates a recurring series', (tester) async {
    final (db, _) = await pumpFei(tester);
    await openTab(tester, 'Recurring');
    await tester.tap(find.byTooltip('Add recurring'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '15.99');
    await tester.tap(find.text('Choose a category'));
    await settle(tester);
    await tester.tap(find.text('Entertainment'));
    await settle(tester);
    await scrollTo(tester, find.text('Add recurring'));
    await tester.tap(find.text('Add recurring'));
    await settle(tester);

    final series = (await dbRun(tester, db.allRecurring)).single;
    expect(series.amountCents, 1599);
    expect(series.frequency, Frequency.monthly);
    expect(series.startDate, todayYmd());
    // Today's occurrence is created straight away.
    expect((await dbRun(tester, db.transactionsBetween)).single.recurringId, series.id);
    await unmount(tester);
  });

  testWidgets('lists the month with totals, and filters by search and type', (tester) async {
    await pumpFei(tester, seed: seedMonth);
    await openTab(tester, 'Transactions');
    expect(find.text(r'3 transactions · In $4,000.00 · Out $57.50'), findsOneWidget);
    expect(find.text('Costco'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'cost');
    await settle(tester);
    expect(find.text(r'1 transaction · In $0.00 · Out $45.50'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz');
    await settle(tester);
    expect(find.text('Nothing matches these filters'), findsOneWidget);
    await tester.tap(find.byTooltip('Close search'));
    await settle(tester);

    await chooseMenu(tester, 'All types', 'Income');
    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Costco'), findsNothing);
    await chooseMenu(tester, 'Income', 'All types');
    expect(find.text('Costco'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('filters by category', (tester) async {
    await pumpFei(tester, seed: seedMonth);
    await openTab(tester, 'Transactions');
    await tester.tap(find.text('All categories'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Search categories'), 'dining');
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.text('Food & Dining')));
    await settle(tester);
    expect(find.text('Food & Dining'), findsWidgets, reason: 'the chip shows the chosen category');
    expect(find.text('Chipotle'), findsOneWidget);
    expect(find.text('Costco'), findsNothing);
    await unmount(tester);
  });

  testWidgets('tapping a transaction edits it', (tester) async {
    final (db, _) = await pumpFei(tester, seed: seedMonth);
    await openTab(tester, 'Transactions');
    await tester.tap(find.text('Costco'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '50');
    await scrollTo(tester, find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await settle(tester);

    final txns = await dbRun(tester, db.transactionsBetween);
    expect(txns.firstWhere((t) => t.merchant == 'Costco').amountCents, 5000);
    expect(txns, hasLength(3));
    await unmount(tester);
  });

  testWidgets('swipe to delete, with undo', (tester) async {
    final (db, _) = await pumpFei(tester, seed: seedMonth);
    await openTab(tester, 'Transactions');
    await tester.drag(find.text('Chipotle'), const Offset(-600, 0));
    await settle(tester);
    expect(find.text('Chipotle'), findsNothing);
    expect(await dbRun(tester, db.transactionsBetween), hasLength(2));

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await dbRun(tester, db.transactionsBetween), hasLength(3));
    expect(find.text('Chipotle'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('month switcher moves between months', (tester) async {
    await pumpFei(tester, seed: seedMonth);
    await openTab(tester, 'Transactions');
    await tester.tap(find.byTooltip('Previous').last);
    await settle(tester);
    final previous = DateTime(now.year, now.month - 1);
    expect(find.text('No transactions in ${formatMonthYear(previous.year, previous.month)}'), findsOneWidget);
    await tester.tap(find.byTooltip('Next').last);
    await settle(tester);
    expect(find.text('Costco'), findsOneWidget);
    await unmount(tester);
  });
}
