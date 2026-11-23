import 'package:fei/data/database.dart';
import 'package:fei/domain/analytics.dart';
import 'package:fei/domain/waterfall.dart';
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

  Future<CashFlowWaterfall> build() async => CashFlowWaterfall.of(summarize(await db.transactionsBetween(), cats));

  test('income fills the axis and savings fill from the left', () async {
    await addTxn(db, category: 'Paycheck', cents: 300000, date: '2026-01-15');
    await addTxn(db, category: 'Interest', cents: 1000, date: '2026-01-15');
    await addTxn(db, category: 'Grocery', cents: 30000, date: '2026-01-05');
    await addTxn(db, category: 'Rent', cents: 20000, date: '2026-01-01');

    final w = await build();
    expect(w.total, 301000);
    expect(w.income, (start: 0, end: 301000));
    expect(w.savings, (start: 0, end: 251000));
    expect(w.isDeficit, isFalse);
    expect([for (final s in w.sources) s.category.name], ['Paycheck', 'Interest']);
    expect([for (final c in w.categories) c.category.name], ['Grocery', 'Rent']);
    expect(w.spentShare, closeTo(16.6, 0.1));
    expect(w.savingsRate, closeTo(83.4, 0.1));
  });

  test('overspending makes savings negative, spanning the overspend', () async {
    await addTxn(db, category: 'Paycheck', cents: 1000, date: '2026-01-15');
    await addTxn(db, category: 'Grocery', cents: 1500, date: '2026-01-05');
    final w = await build();
    expect(w.total, 1500);
    expect(w.isDeficit, isTrue);
    expect(w.savingsCents, -500);
    expect(w.income, (start: 0, end: 1000));
    expect(w.savings, (start: 1000, end: 1500));
    expect(w.spentShare, closeTo(150, 0.01));
  });

  test('expenses only', () async {
    await addTxn(db, category: 'Grocery', cents: 1500, date: '2026-01-05');
    final w = await build();
    expect(w.hasIncome, isFalse);
    expect(w.spentShare, isNull);
  });

  test('income only', () async {
    await addTxn(db, category: 'Paycheck', cents: 1000, date: '2026-01-15');
    final w = await build();
    expect(w.hasExpenses, isFalse);
    expect(w.savings, (start: 0, end: 1000));
  });

  test('no data', () async {
    expect((await build()).isEmpty, isTrue);
  });
}
