import 'package:fei/data/database.dart';
import 'package:fei/domain/analytics.dart';
import 'package:fei/domain/sankey.dart';
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

  Future<SankeyData> build({bool collapseSources = false}) async =>
      buildCashFlowSankey(summarize(await db.transactionsBetween(), cats), collapseSources: collapseSources);

  int inflow(SankeyData d, String id) => d.links.where((l) => l.to == id).fold(0, (a, l) => a + l.value);
  int outflow(SankeyData d, String id) => d.links.where((l) => l.from == id).fold(0, (a, l) => a + l.value);

  test('several income sources: sources → total → expenses + savings → categories', () async {
    await addTxn(db, category: 'Paycheck', cents: 300000, date: '2026-01-15');
    await addTxn(db, category: 'Interest', cents: 1000, date: '2026-01-15');
    await addTxn(db, category: 'Grocery', cents: 30000, date: '2026-01-05');
    await addTxn(db, category: 'Rent', cents: 20000, date: '2026-01-01');

    final data = await build();
    expect(data.columns, 4);
    expect(
      data.nodes.map((n) => n.label),
      containsAll(['Paycheck', 'Interest', 'Total income', 'Expenses', 'Savings', 'Grocery', 'Rent']),
    );
    expect(data.nodes.firstWhere((n) => n.id == 'savings').value, 251000);

    // Flow is conserved through the middle nodes.
    final total = data.nodes.firstWhere((n) => n.label == 'Total income');
    expect(inflow(data, total.id), 301000);
    expect(outflow(data, total.id), 301000);
    expect(inflow(data, 'expenses'), 50000);
    expect(outflow(data, 'expenses'), 50000);
  });

  test('collapseSources skips the total column', () async {
    await addTxn(db, category: 'Paycheck', cents: 300000, date: '2026-01-15');
    await addTxn(db, category: 'Interest', cents: 1000, date: '2026-01-15');
    await addTxn(db, category: 'Grocery', cents: 30000, date: '2026-01-05');
    expect((await build(collapseSources: true)).columns, 3);
  });

  test('a single income source skips the total column; overspending adds "From savings"', () async {
    await addTxn(db, category: 'Paycheck', cents: 1000, date: '2026-01-15');
    await addTxn(db, category: 'Grocery', cents: 1500, date: '2026-01-05');
    final data = await build();
    expect(data.columns, 3);
    expect(data.nodes.any((n) => n.id == 'savings'), isFalse);
    expect(data.nodes.firstWhere((n) => n.id == 'deficit').value, 500);
    expect(inflow(data, 'expenses'), 1500);
  });

  test('expenses only', () async {
    await addTxn(db, category: 'Grocery', cents: 1500, date: '2026-01-05');
    expect((await build()).columns, 2);
  });

  test('no data gives an empty chart', () async {
    final data = await build();
    expect(data.nodes, isEmpty);
    expect(data.columns, 0);
  });
}
