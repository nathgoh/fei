import 'dart:convert';

import 'package:fei/data/database.dart';
import 'package:fei/data/import_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Shaped like the web app's data/ folder.
final webCategories = jsonEncode(['Personal', 'Home', 'Grocery', 'Rent', 'Pet Supplies']);
final webExpenses = jsonEncode({
  'next_id': 6,
  'records': [
    {
      'id': 1,
      'amount': 45.5,
      'category': 'Grocery',
      'date': '2025-01-03',
      'notes': 'Costco',
      'frequency': null,
      'recurring_id': null,
    },
    {
      'id': 2,
      'amount': 1800.0,
      'category': 'Rent',
      'date': '2025-01-01',
      'notes': '',
      'frequency': 'Monthly',
      'recurring_id': 'abc',
    },
    {
      'id': 3,
      'amount': 1800.0,
      'category': 'Rent',
      'date': '2025-02-01',
      'notes': '',
      'frequency': 'Monthly',
      'recurring_id': 'abc',
    },
    {
      'id': 4,
      'amount': 1800.0,
      'category': 'Rent',
      'date': '2025-03-01',
      'notes': '',
      'frequency': 'Monthly',
      'recurring_id': 'abc',
    },
    {'id': 5, 'amount': 20, 'category': 'Pet Supplies', 'date': '2025-02-11', 'notes': null},
  ],
});
final webIncomes = jsonEncode({
  'next_id': 4,
  'records': [
    {'id': 1, 'amount': 4000.0, 'date': '2025-01-15', 'source': 'Acme Corp'},
    {'id': 2, 'amount': 4000.0, 'date': '2025-02-15', 'source': 'Acme Corp'},
    {'id': 3, 'amount': 12.34, 'date': '2025-02-28', 'source': ''},
  ],
});

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  List<ImportFile> webFiles() => [
    ImportFile('categories.json', webCategories),
    ImportFile('expenses.json', webExpenses),
    ImportFile('incomes.json', webIncomes),
  ];

  test('imports web app JSON with categories, income sources and recurring series', () async {
    final r = await importWebAppJson(db, webFiles());
    expect(r.added, 8);
    expect(r.warnings, isEmpty);
    expect(r.seriesCreated, 1);

    final cats = {for (final c in await db.allCategories()) c.id: c};
    final txns = await db.transactionsBetween();
    expect(txns.where((t) => t.kind == TxKind.expense).fold<int>(0, (a, t) => a + t.amountCents), 546550);
    expect(cats.values.map((c) => c.name), containsAll(['Pet Supplies', 'Acme Corp', 'Other Income']));
    expect(cats.values.firstWhere((c) => c.name == 'Acme Corp').kind, TxKind.income);

    final costco = txns.firstWhere((t) => t.notes == 'Costco');
    expect(costco.amountCents, 4550);
    expect(cats[costco.categoryId]!.name, 'Grocery');

    final series = (await db.allRecurring()).single;
    expect(series.frequency, Frequency.monthly);
    expect(series.startDate, '2025-01-01');
    expect(series.endDate, '2025-03-01');
    expect(txns.where((t) => t.recurringId == series.id), hasLength(3));

    // Generation must not duplicate the imported occurrences.
    expect(await db.materializeRecurring(), 0);
  });

  test('re-importing the same files adds nothing', () async {
    await importWebAppJson(db, webFiles());
    final again = await importWebAppJson(db, webFiles());
    expect(again.added, 0);
    expect(again.skipped, 8);
    expect(again.seriesCreated, 0);
    expect(await db.transactionsBetween(), hasLength(8));
  });

  test('CSV export → erase → import round-trips', () async {
    await importWebAppJson(db, webFiles());
    await db.addAccount('Amex', AccountType.credit);
    final before = await db.transactionsBetween();
    final csv = await exportCsv(db);
    expect(csv.split('\n').first, csvHeader.join(','));

    await db.eraseAll();
    final r = await importCsv(db, ImportFile('fei.csv', csv));
    expect(r.added, before.length);
    final after = await db.transactionsBetween();
    int total(List<Txn> t, TxKind k) => t.where((x) => x.kind == k).fold(0, (a, x) => a + x.amountCents);
    expect(total(after, TxKind.expense), total(before, TxKind.expense));
    expect(total(after, TxKind.income), total(before, TxKind.income));

    final again = await importCsv(db, ImportFile('fei.csv', csv));
    expect(again.added, 0);
    expect(again.skipped, before.length);
  });

  test('bank-style CSV without a Type column uses the sign; duplicates in a file are kept', () async {
    const csv =
        'Posted Date,Description,Amount,Category\n'
        '10/02/2026,COFFEE SHOP,-4.50,Food & Dining\n'
        '10/02/2026,COFFEE SHOP,-4.50,Food & Dining\n'
        '10/03/2026,PAYROLL,"2,500.00",Paycheck\n'
        'not a date,???,x,\n';
    final r = await importCsv(db, ImportFile('bank.csv', csv));
    expect(r.added, 3);
    expect(r.warnings, hasLength(1));
    final txns = await db.transactionsBetween();
    expect(txns.where((t) => t.kind == TxKind.expense).map((t) => t.amountCents), [450, 450]);
    final pay = txns.firstWhere((t) => t.kind == TxKind.income);
    expect(pay.amountCents, 250000);
    expect(pay.merchant, 'PAYROLL');
    expect(pay.date, '2026-10-03');
  });

  test("web app's own CSV exports import", () async {
    const expenses = 'Type,Category,Amount,Date,Notes\nExpense,Grocery,12.5,2025-01-03,Milk\n';
    const incomes = 'Type,Source,Amount,Date\nIncome,Acme Corp,4000.0,2025-01-15\n';
    await importCsv(db, ImportFile('e.csv', expenses));
    await importCsv(db, ImportFile('i.csv', incomes));
    final txns = await db.transactionsBetween();
    expect(txns, hasLength(2));
    expect(txns.firstWhere((t) => t.kind == TxKind.income).amountCents, 400000);
    expect(txns.firstWhere((t) => t.kind == TxKind.expense).notes, 'Milk');
  });
}
