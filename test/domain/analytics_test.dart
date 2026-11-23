import 'package:fei/data/database.dart';
import 'package:fei/domain/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/db.dart';

void main() {
  late AppDatabase db;
  late Map<String, Category> cats;
  setUp(() async {
    db = memoryDb();
    cats = {for (final c in await db.allCategories()) c.id: c};
  });
  tearDown(() => db.close());

  Future<PeriodSummary> summary() async => summarize(await db.transactionsBetween(), cats);

  group('summarize', () {
    test('totals, fixed vs flexible, and averages over the active month span', () async {
      await addTxn(db, category: 'Paycheck', cents: 500000, date: '2026-01-15');
      await addTxn(db, category: 'Paycheck', cents: 500000, date: '2026-03-15');
      await addTxn(db, category: 'Rent', cents: 200000, date: '2026-01-01');
      await addTxn(db, category: 'Rent', cents: 200000, date: '2026-03-01');
      await addTxn(db, category: 'Grocery', cents: 30000, date: '2026-01-05');
      await addTxn(db, category: 'Grocery', cents: 60000, date: '2026-03-05');

      final s = await summary();
      expect(s.incomeCents, 1000000);
      expect(s.expenseCents, 490000);
      expect(s.fixedCents, 400000);
      expect(s.flexibleCents, 90000);
      expect(s.savingsCents, 510000);
      expect(s.savingsRate, closeTo(51.0, 0.001));
      expect(s.transactionCount, 6);

      // January to March is 3 months even though February is empty.
      expect(s.monthSpan, 3);
      expect(s.activeMonths.map((m) => m.month), [1, 3]);
      expect(s.avgExpensePerMonth, 163333);
      expect(s.avgFlexiblePerMonth, 30000);
      final grocery = cats.values.firstWhere((c) => c.name == 'Grocery');
      expect(s.monthlyAverageFor(grocery.id), 30000);
    });

    test('per-month totals', () async {
      await addTxn(db, category: 'Paycheck', cents: 500000, date: '2026-03-15');
      await addTxn(db, category: 'Rent', cents: 200000, date: '2026-03-01');
      await addTxn(db, category: 'Grocery', cents: 60000, date: '2026-03-05');
      final march = (await summary()).months[2];
      expect(march.month, 3);
      expect(march.incomeCents, 500000);
      expect(march.expenseCents, 260000);
      expect(march.savingsCents, 240000);
      expect(march.expenseByCategory.values.fold<int>(0, (a, b) => a + b), 260000);
      expect((await summary()).months[1].hasData, isFalse);
    });

    test('category totals are sorted, with shares and counts', () async {
      await addTxn(db, category: 'Rent', cents: 200000, date: '2026-01-01');
      await addTxn(db, category: 'Grocery', cents: 30000, date: '2026-01-05');
      await addTxn(db, category: 'Grocery', cents: 15000, date: '2026-01-09');
      await addTxn(db, category: 'Paycheck', cents: 300000, date: '2026-01-15');
      await addTxn(db, category: 'Interest', cents: 100000, date: '2026-01-31');

      final s = await summary();
      expect(s.expenseByCategory.map((c) => c.category.name), ['Rent', 'Grocery']);
      expect(s.expenseByCategory.first.share, closeTo(81.63, 0.01));
      expect(s.expenseByCategory.last.count, 2);
      expect(s.incomeByCategory.map((c) => c.category.name), ['Paycheck', 'Interest']);
      expect(s.incomeByCategory.map((c) => c.share), [75, 25]);
    });

    test('spending more than earned gives a negative savings rate', () async {
      await addTxn(db, category: 'Paycheck', cents: 1000, date: '2026-01-15');
      await addTxn(db, category: 'Grocery', cents: 1500, date: '2026-01-05');
      final s = await summary();
      expect(s.savingsCents, -500);
      expect(s.savingsRate, closeTo(-50, 0.001));
    });

    test('no income means no savings rate; no data means zeros', () async {
      expect((await summary()).isEmpty, isTrue);
      expect((await summary()).monthSpan, 0);
      expect((await summary()).avgExpensePerMonth, 0);

      await addTxn(db, category: 'Grocery', cents: 1500, date: '2026-01-05');
      expect((await summary()).savingsRate, isNull);
    });
  });

  test('cumulativeDailySpending is a running total that leaves out fixed costs and income', () async {
    await addTxn(db, category: 'Rent', cents: 200000, date: '2026-02-01');
    await addTxn(db, category: 'Paycheck', cents: 500000, date: '2026-02-01');
    await addTxn(db, category: 'Grocery', cents: 1000, date: '2026-02-01');
    await addTxn(db, category: 'Grocery', cents: 500, date: '2026-02-10');
    await addTxn(db, category: 'Grocery', cents: 9999, date: '2026-03-01'); // other month
    final txns = await db.transactionsBetween();

    final days = cumulativeDailySpending(txns, cats, 2026, 2);
    expect(days, hasLength(28));
    expect(days[0], 1000);
    expect(days[8], 1000);
    expect(days[9], 1500);
    expect(days.last, 1500);
  });

  group('recurring outlook', () {
    test('upcomingOccurrences are after today, within the window, sorted', () async {
      await addSeries(db, category: 'Entertainment', cents: 1200, start: '2026-01-05', frequency: Frequency.weekly);
      await addSeries(db, category: 'Utility', cents: 6500, start: '2026-01-03');
      final upcoming = upcomingOccurrences(await db.allRecurring(), days: 14, asOf: DateTime(2026, 2, 1));
      expect(upcoming.map((o) => (o.date.day, o.series.amountCents)), [(2, 1200), (3, 6500), (9, 1200)]);
      // asOf itself is not "upcoming".
      final fromTheThird = upcomingOccurrences(await db.allRecurring(), days: 1, asOf: DateTime(2026, 2, 2));
      expect(fromTheThird.single.series.amountCents, 6500);
    });

    test('ended series: inactive, no next occurrence, nothing upcoming', () async {
      await addSeries(db, category: 'Rent', cents: 100000, start: '2026-01-01', end: '2026-01-31');
      final s = (await db.allRecurring()).single;
      expect(isSeriesActive(s, DateTime(2026, 1, 31)), isTrue, reason: 'active through its end date');
      expect(isSeriesActive(s, DateTime(2026, 2, 1)), isFalse);
      expect(nextOccurrence(s, asOf: DateTime(2026, 2, 1)), isNull);
      expect(upcomingOccurrences([s], asOf: DateTime(2026, 2, 1)), isEmpty);
    });

    test('nextOccurrence and monthlyEquivalent', () async {
      await addSeries(db, category: 'Entertainment', cents: 1200, start: '2026-01-05', frequency: Frequency.weekly);
      await addSeries(db, category: 'Travel', cents: 120000, start: '2026-03-01', frequency: Frequency.yearly);
      final series = await db.allRecurring();
      final weekly = series.firstWhere((s) => s.frequency == Frequency.weekly);
      final yearly = series.firstWhere((s) => s.frequency == Frequency.yearly);
      expect(nextOccurrence(weekly, asOf: DateTime(2026, 2, 1)), DateTime(2026, 2, 2));
      expect(nextOccurrence(yearly, asOf: DateTime(2026, 3, 1)), DateTime(2027, 3, 1));
      expect(monthlyEquivalent(weekly), 5200);
      expect(monthlyEquivalent(yearly), 10000);
    });
  });
}
