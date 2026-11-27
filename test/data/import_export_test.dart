import 'dart:convert';

import 'package:fei/data/database.dart';
import 'package:fei/data/import_export.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/db.dart';

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
    for (final (id, month) in [(2, '01'), (3, '02'), (4, '03')])
      {
        'id': id,
        'amount': 1800.0,
        'category': 'Rent',
        'date': '2025-$month-01',
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

List<ImportFile> webFiles() => [
  ImportFile('categories.json', webCategories),
  ImportFile('expenses.json', webExpenses),
  ImportFile('incomes.json', webIncomes),
];

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  group('web app JSON', () {
    test('imports expenses, income sources and recurring series', () async {
      final r = await importWebAppJson(db, webFiles());
      expect(r.added, 8);
      expect(r.skipped, 0);
      expect(r.seriesCreated, 1);
      expect(r.warnings, isEmpty);
      expect(r.describe(), contains('8 transactions imported'));

      final cats = {for (final c in await db.allCategories()) c.id: c};
      final txns = await db.transactionsBetween();
      expect(sumCents(txns.where((t) => t.kind == TxKind.expense)), 546550);
      expect(sumCents(txns.where((t) => t.kind == TxKind.income)), 801234);

      // Unknown categories and income sources are created; a blank source
      // falls back to Other Income.
      expect(cats.values.map((c) => c.name), containsAll(['Pet Supplies', 'Acme Corp', 'Other Income']));
      expect(cats.values.firstWhere((c) => c.name == 'Acme Corp').kind, TxKind.income);
      final blank = txns.firstWhere((t) => t.amountCents == 1234);
      expect(cats[blank.categoryId]!.name, 'Other Income');

      final costco = txns.firstWhere((t) => t.notes == 'Costco');
      expect(costco.amountCents, 4550);
      expect(cats[costco.categoryId]!.name, 'Grocery');
      expect(txns.firstWhere((t) => t.amountCents == 2000).notes, isNull);
    });

    test('recurring records become one ended series, with no extra occurrences', () async {
      await importWebAppJson(db, webFiles());
      final series = (await db.allRecurring()).single;
      expect(series.frequency, Frequency.monthly);
      expect(series.startDate, '2025-01-01');
      expect(series.endDate, '2025-03-01');
      expect(series.amountCents, 180000);
      final txns = await db.transactionsBetween();
      expect(txns.where((t) => t.recurringId == series.id), hasLength(3));
      expect(await db.materializeRecurring(), 0);
    });

    test('re-importing the same files adds nothing', () async {
      await importWebAppJson(db, webFiles());
      final again = await importWebAppJson(db, webFiles());
      expect(again.added, 0);
      expect(again.skipped, 8);
      expect(again.seriesCreated, 0);
      expect(await db.transactionsBetween(), hasLength(8));
      expect(again.describe(), contains('8 already present'));
    });

    test('files are recognised by content, not name', () async {
      final r = await importWebAppJson(db, [ImportFile('backup (1).json', webIncomes)]);
      expect(r.added, 3);
      expect((await db.transactionsBetween()).every((t) => t.kind == TxKind.income), isTrue);
    });

    test('invalid JSON is reported and the rest still imports', () async {
      final r = await importWebAppJson(db, [
        ImportFile('broken.json', '{"records": ['),
        ImportFile('incomes.json', webIncomes),
      ]);
      expect(r.added, 3);
      expect(r.warnings.single, startsWith('broken.json: not valid JSON'));
    });
  });

  test('web app JSON: malformed records are skipped with a warning and the rest import', () async {
    final expenses = jsonEncode({
      'records': [
        {'id': 1, 'amount': 5, 'category': 'Grocery', 'date': '2026-01-05'},
        {'id': 2, 'amount': 5, 'category': 'Grocery', 'date': '2026-13-45'},
        {'id': 3, 'amount': 5, 'category': 'Rent', 'frequency': 'Monthly', 'recurring_id': 'r1'}, // no date
        {'id': 4, 'amount': 'five', 'category': 'Rent', 'date': '2026-02-01', 'recurring_id': 'r1'},
        {'id': 5, 'amount': 7, 'category': 'Rent', 'date': '2026-03-01', 'frequency': 'Monthly', 'recurring_id': 'r1'},
      ],
    });
    final r = await importWebAppJson(db, [ImportFile('expenses.json', expenses)]);
    expect(r.added, 2);
    expect(r.warnings, [
      for (final id in [2, 3, 4]) 'expenses.json: skipped malformed record $id',
    ]);
    expect((await db.transactionsBetween()).map((t) => t.date).toSet(), {'2026-01-05', '2026-03-01'});
    expect((await db.allRecurring()).single.startDate, '2026-03-01');
  });

  group('CSV', () {
    test('impossible calendar dates are rejected, not rolled into the next month', () async {
      const csv = 'Date,Amount,Type\n2026-02-30,5,Expense\n2/30/2026,5,Expense\n2026-02-28,5,Expense\n';
      final r = await importCsv(db, ImportFile('bank.csv', csv));
      expect(r.added, 1);
      expect(r.warnings, ['Row 2: could not read date/amount', 'Row 3: could not read date/amount']);
      expect((await db.transactionsBetween()).single.date, '2026-02-28');
    });

    test('export has the expected columns, oldest first', () async {
      await addTxn(db, category: 'Grocery', cents: 1250, date: '2026-01-05', merchant: 'Costco', notes: 'Milk, eggs');
      await addTxn(db, category: 'Paycheck', cents: 400000, date: '2026-01-02');
      final lines = (await exportCsv(db)).split('\n');
      expect(lines[0], 'Date,Type,Category,Group,Amount,Merchant,Notes,Recurring');
      expect(lines[1], '2026-01-02,Income,Paycheck,Income,4000.00,,,');
      expect(lines[2], '2026-01-05,Expense,Grocery,Food & Drink,12.50,Costco,"Milk, eggs",');
    });

    test('export can be limited to a year and marks recurring rows', () async {
      await addTxn(db, category: 'Grocery', cents: 100, date: '2025-12-31');
      await addSeries(db, category: 'Rent', cents: 200000, start: '2026-01-01', end: '2026-01-01');
      await db.materializeRecurring(asOf: DateTime(2026, 1, 1));
      final lines = (await exportCsv(db, year: 2026)).trim().split('\n');
      expect(lines, hasLength(2));
      expect(lines[1], endsWith(',yes'));
    });

    test('export → erase → import round-trips and is idempotent', () async {
      await importWebAppJson(db, webFiles());
      final before = await db.transactionsBetween();
      final csv = await exportCsv(db);

      await db.eraseAll();
      final r = await importCsv(db, ImportFile('fei.csv', csv));
      expect(r.added, before.length);
      expect(r.warnings, isEmpty);
      final after = await db.transactionsBetween();
      for (final kind in TxKind.values) {
        expect(sumCents(after.where((t) => t.kind == kind)), sumCents(before.where((t) => t.kind == kind)));
      }
      expect(after.map((t) => t.date).toSet(), before.map((t) => t.date).toSet());

      final again = await importCsv(db, ImportFile('fei.csv', csv));
      expect(again.added, 0);
      expect(again.skipped, before.length);
    });

    test('bank-style CSV: sign gives the type, US dates, duplicates within a file are kept', () async {
      const csv =
          'Posted Date,Description,Amount,Category\n'
          '10/02/2026,COFFEE SHOP,-4.50,Food & Dining\n'
          '10/02/2026,COFFEE SHOP,-4.50,Food & Dining\n'
          '10/03/2026,PAYROLL,"2,500.00",Paycheck\n'
          'not a date,???,x,\n';
      final r = await importCsv(db, ImportFile('bank.csv', csv));
      expect(r.added, 3);
      expect(r.warnings, ['Row 5: could not read date/amount']);
      final txns = await db.transactionsBetween();
      expect(txns.where((t) => t.kind == TxKind.expense).map((t) => t.amountCents), [450, 450]);
      final pay = txns.firstWhere((t) => t.kind == TxKind.income);
      expect(pay.amountCents, 250000);
      expect(pay.merchant, 'PAYROLL');
      expect(pay.date, '2026-10-03');
    });

    test("the web app's own CSV exports import", () async {
      const expenses = 'Type,Category,Amount,Date,Notes\nExpense,Grocery,12.5,2025-01-03,Milk\n';
      const incomes = 'Type,Source,Amount,Date\nIncome,Acme Corp,4000.0,2025-01-15\n';
      await importCsv(db, ImportFile('e.csv', expenses));
      await importCsv(db, ImportFile('i.csv', incomes));
      final txns = await db.transactionsBetween();
      expect(txns, hasLength(2));
      expect(txns.firstWhere((t) => t.kind == TxKind.income).amountCents, 400000);
      expect(txns.firstWhere((t) => t.kind == TxKind.expense).notes, 'Milk');
    });

    test('a file without Date and Amount columns is rejected', () async {
      final r = await importCsv(db, ImportFile('x.csv', 'Name,Value\nfoo,1\n'));
      expect(r.added, 0);
      expect(r.warnings.single, contains('needs "Date" and "Amount" columns'));
    });
  });
}
