import 'package:fei/core/dates.dart';
import 'package:fei/data/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/db.dart';

/// The merchant field, found by its label ('Merchant' or 'Source').
Finder merchantField(String label) => find.widgetWithText(TextField, label);

/// A row in the merchant suggestions.
final suggestionTile = find.ancestor(of: find.byIcon(Icons.history), matching: find.byType(ListTile));

/// The merchant suggestions on screen, top to bottom.
List<String> suggestions(WidgetTester tester) =>
    tester.widgetList<ListTile>(suggestionTile).map((t) => (t.title! as Text).data!).toList();

void main() {
  final now = today();
  final firstOfMonth = ymd(DateTime(now.year, now.month, 1));

  Future<void> seedMonth(AppDatabase db) async {
    await addTxn(db, category: 'Paycheck', cents: 400000, date: firstOfMonth, merchant: 'Acme Corp');
    await addTxn(db, category: 'Grocery', cents: 4550, date: firstOfMonth, merchant: 'Costco');
    await addTxn(db, category: 'Food & Dining', cents: 1200, date: firstOfMonth, merchant: 'Chipotle');
  }

  Future<void> chooseCategory(WidgetTester tester, String name) async {
    await tester.tap(find.text('Choose a category'));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.text(name)));
    await settle(tester);
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
    await tester.enterText(merchantField('Merchant'), 'Costco');
    await tester.tap(find.text('Add transaction').last);
    await settle(tester);

    final t = (await dbRun(tester, db.transactionsBetween)).single;
    expect(t.amountCents, 4250);
    expect(t.kind, TxKind.expense);
    expect(t.date, todayYmd());
    expect(t.merchant, 'Costco');
    expect(find.text(r'$42.50'), findsWidgets);
    expect(find.text('No spending this month.'), findsNothing);
    await unmount(tester);
  });

  testWidgets('the form insists on an amount, a merchant and a category', (tester) async {
    final (db, _) = await pumpFei(tester);
    await openTab(tester, 'Transactions');
    await tester.tap(find.byTooltip('Add transaction'));
    await settle(tester);
    expect(find.text('Notes (optional)'), findsOneWidget);
    expect(find.textContaining('(optional)'), findsOneWidget, reason: 'only notes are optional');
    await tester.tap(find.text('Add transaction').last);
    await settle(tester);
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(find.text('Enter a merchant'), findsOneWidget);
    expect(await dbRun(tester, db.transactionsBetween), isEmpty);

    // Income calls it a source.
    await tester.tap(find.text('Income'));
    await settle(tester);
    expect(merchantField('Source'), findsOneWidget);
    expect(find.text('Enter a source'), findsOneWidget);
    await tester.tap(find.text('Expense'));
    await settle(tester);

    // Whitespace doesn't count.
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.enterText(merchantField('Merchant'), '   ');
    await tester.tap(find.text('Add transaction').last);
    await settle(tester);
    expect(find.text('Enter a merchant'), findsOneWidget);
    expect(await dbRun(tester, db.transactionsBetween), isEmpty);

    await tester.enterText(merchantField('Merchant'), 'Costco');
    await settle(tester);
    expect(find.text('Enter a merchant'), findsNothing, reason: 'typing clears the error');
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
    await tester.enterText(merchantField('Merchant'), 'Netflix');
    await scrollTo(tester, find.text('Add recurring'));
    await tester.tap(find.text('Add recurring'));
    await settle(tester);

    final series = (await dbRun(tester, db.allRecurring)).single;
    expect(series.amountCents, 1599);
    expect(series.merchant, 'Netflix');
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

  testWidgets('saves the merchant trimmed and capitalised, matching past ones whatever the case', (tester) async {
    final (db, _) = await pumpFei(tester, seed: seedMonth);
    await openTab(tester, 'Transactions');
    await tester.tap(find.byTooltip('Add transaction'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '7');
    await chooseCategory(tester, 'Grocery');
    await tester.enterText(merchantField('Merchant'), 'cost');
    await settle(tester);
    expect(suggestions(tester), ['Costco'], reason: 'matching ignores case');
    await tester.enterText(merchantField('Merchant'), '  COSTCO  ');
    await settle(tester);
    expect(suggestions(tester), isEmpty, reason: 'the typed name already is that merchant');
    await tester.tap(find.text('Add transaction').last);
    await settle(tester);

    final added = (await dbRun(tester, db.transactionsBetween)).firstWhere((t) => t.amountCents == 700);
    expect(added.merchant, 'Costco');
    expect(await dbRun(tester, () => db.watchMerchants(kind: TxKind.expense).first), [
      'Costco',
      'Chipotle',
    ], reason: 'merged into the existing Costco, now used twice');
    await unmount(tester);
  });

  testWidgets('editing a transaction without a merchant asks for one', (tester) async {
    final (db, _) = await pumpFei(
      tester,
      seed: (db) => addTxn(db, category: 'Paycheck', cents: 1000, date: firstOfMonth, notes: 'Bonus'),
    );
    await openTab(tester, 'Transactions');
    await tester.tap(find.text('Bonus'));
    await settle(tester);
    expect(merchantField('Source'), findsOneWidget);
    await scrollTo(tester, find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await settle(tester);
    expect(find.text('Enter a source'), findsOneWidget);
    expect((await dbRun(tester, db.transactionsBetween)).single.merchant, isNull);

    await tester.enterText(merchantField('Source'), 'Acme Corp');
    await tester.tap(find.text('Save changes'));
    await settle(tester);
    expect((await dbRun(tester, db.transactionsBetween)).single.merchant, 'Acme Corp');
    await unmount(tester);
  });

  testWidgets('suggests merchants for the kind and category, and fills one in', (tester) async {
    final (db, _) = await pumpFei(
      tester,
      seed: (db) async {
        await seedMonth(db);
        await addTxn(db, category: 'Grocery', cents: 999, date: firstOfMonth, merchant: 'Safeway');
        await addTxn(db, category: 'Grocery', cents: 999, date: firstOfMonth, merchant: 'Safeway');
      },
    );
    await openTab(tester, 'Transactions');
    await tester.tap(find.byTooltip('Add transaction'));
    await settle(tester);

    // Focused and empty: every expense merchant, most used first.
    await tester.tap(merchantField('Merchant'));
    await settle(tester);
    expect(suggestions(tester), ['Safeway', 'Chipotle', 'Costco']);

    // Typing filters, ignoring case.
    await tester.enterText(merchantField('Merchant'), 'CO');
    await settle(tester);
    expect(suggestions(tester), ['Costco']);
    await tester.enterText(merchantField('Merchant'), '');
    await settle(tester);

    // A category narrows them to that category's merchants.
    await chooseCategory(tester, 'Grocery');
    await tester.tap(merchantField('Merchant'));
    await settle(tester);
    expect(suggestions(tester), ['Safeway', 'Costco']);

    // Income suggests sources.
    await tester.tap(find.text('Income'));
    await settle(tester);
    await tester.tap(merchantField('Source'));
    await settle(tester);
    expect(suggestions(tester), ['Acme Corp']);
    await tester.tap(find.text('Expense'));
    await settle(tester);

    // Picking one fills the field, and doesn't touch the category.
    await chooseCategory(tester, 'Grocery');
    await tester.enterText(merchantField('Merchant'), 'saf');
    await settle(tester);
    await tester.tap(find.ancestor(of: find.text('Safeway'), matching: suggestionTile));
    await settle(tester);
    expect(suggestions(tester), isEmpty);
    expect(find.descendant(of: merchantField('Merchant'), matching: find.text('Safeway')), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '5');
    await tester.tap(find.text('Add transaction').last);
    await settle(tester);

    final added = (await dbRun(tester, db.transactionsBetween)).where((t) => t.amountCents == 500).single;
    expect(added.merchant, 'Safeway');
    expect(added.categoryId, (await dbRun(tester, () => categoryNamed(db, 'Grocery'))).id);
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
