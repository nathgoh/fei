import 'package:fei/data/database.dart';
import 'package:fei/domain/analytics.dart';
import 'package:fei/domain/sankey.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late Map<String, Category> cats;
  setUp(() async {
    db = memoryDb();
    cats = {for (final c in await db.allCategories()) c.id: c};
  });
  tearDown(() => db.close());

  test('summarize computes totals, fixed vs flexible, averages over month span', () async {
    await addTxn(db, category: 'Paycheck', cents: 500000, date: '2026-01-15', kind: TxKind.income);
    await addTxn(db, category: 'Paycheck', cents: 500000, date: '2026-03-15', kind: TxKind.income);
    await addTxn(db, category: 'Rent', cents: 200000, date: '2026-01-01');
    await addTxn(db, category: 'Rent', cents: 200000, date: '2026-03-01');
    await addTxn(db, category: 'Grocery', cents: 30000, date: '2026-01-05');
    await addTxn(db, category: 'Grocery', cents: 60000, date: '2026-03-05');

    final s = summarize(await db.transactionsBetween(from: '2026-01-01', to: '2026-12-31'), cats);
    expect(s.incomeCents, 1000000);
    expect(s.expenseCents, 490000);
    expect(s.fixedCents, 400000);
    expect(s.flexibleCents, 90000);
    expect(s.savingsCents, 510000);
    expect(s.savingsRate, closeTo(51.0, 0.001));
    // Jan..Mar = 3 months even though February is empty.
    expect(s.monthSpan, 3);
    expect(s.avgExpensePerMonth, 163333);
    expect(s.avgFlexiblePerMonth, 30000);
    expect(s.expenseByCategory.first.category.name, 'Rent');
    expect(s.expenseByCategory.first.share, closeTo(81.63, 0.01));
    expect(s.months[1].hasData, isFalse);
    expect(s.months[2].expenseByCategory.values.fold<int>(0, (a, b) => a + b), 260000);
    final grocery = s.expenseByCategory.firstWhere((c) => c.category.name == 'Grocery').category;
    expect(s.monthlyAverageFor(grocery.id), 30000);
  });

  test('cumulative daily spending excludes fixed costs', () async {
    await addTxn(db, category: 'Rent', cents: 200000, date: '2026-02-01');
    await addTxn(db, category: 'Grocery', cents: 1000, date: '2026-02-01');
    await addTxn(db, category: 'Grocery', cents: 500, date: '2026-02-10');
    final days = cumulativeDailySpending(await db.transactionsBetween(), cats, 2026, 2);
    expect(days, hasLength(28));
    expect(days[0], 1000);
    expect(days[9], 1500);
    expect(days.last, 1500);
  });

  group('sankey', () {
    test('income sources → total → expenses + savings → categories', () async {
      await addTxn(db, category: 'Paycheck', cents: 300000, date: '2026-01-15', kind: TxKind.income);
      await addTxn(db, category: 'Interest', cents: 1000, date: '2026-01-15', kind: TxKind.income);
      await addTxn(db, category: 'Grocery', cents: 50000, date: '2026-01-05');
      final data = buildCashFlowSankey(summarize(await db.transactionsBetween(), cats));
      expect(data.columns, 4);
      expect(
        data.nodes.map((n) => n.label),
        containsAll(['Paycheck', 'Interest', 'Total income', 'Expenses', 'Savings', 'Grocery']),
      );
      final savings = data.nodes.firstWhere((n) => n.id == 'savings');
      expect(savings.value, 251000);
    });

    test('single income source skips the total column; overspending adds "From savings"', () async {
      await addTxn(db, category: 'Paycheck', cents: 1000, date: '2026-01-15', kind: TxKind.income);
      await addTxn(db, category: 'Grocery', cents: 1500, date: '2026-01-05');
      final data = buildCashFlowSankey(summarize(await db.transactionsBetween(), cats));
      expect(data.columns, 3);
      expect(data.nodes.any((n) => n.id == 'savings'), isFalse);
      final deficit = data.nodes.firstWhere((n) => n.id == 'deficit');
      expect(deficit.value, 500);
      // Flows into "Expenses" add up to total expenses.
      final intoExpenses = data.links.where((l) => l.to == 'expenses').fold<int>(0, (a, l) => a + l.value);
      expect(intoExpenses, 1500);
    });

    test('expenses only', () async {
      await addTxn(db, category: 'Grocery', cents: 1500, date: '2026-01-05');
      final data = buildCashFlowSankey(summarize(await db.transactionsBetween(), cats));
      expect(data.columns, 2);
    });
  });

  test('upcoming occurrences and monthly equivalent', () async {
    await addSeries(db, category: 'Entertainment', cents: 1200, start: '2026-01-05', frequency: Frequency.weekly);
    await addSeries(db, category: 'Rent', cents: 100000, start: '2026-01-01', end: '2026-01-31');
    final series = await db.allRecurring();
    final upcoming = upcomingOccurrences(series, days: 14, asOf: DateTime(2026, 2, 1));
    expect(upcoming.map((o) => o.date.day), [2, 9]);
    expect(isSeriesActive(series.firstWhere((s) => s.amountCents == 100000), DateTime(2026, 2, 1)), isFalse);
    expect(monthlyEquivalent(series.firstWhere((s) => s.amountCents == 1200)), 5200);
    expect(nextOccurrence(series.first, asOf: DateTime(2026, 2, 1))?.day, 2);
  });
}
