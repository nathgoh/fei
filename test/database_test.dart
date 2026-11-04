import 'package:fei/core/dates.dart';
import 'package:fei/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('seeds default groups and categories, with Rent fixed', () async {
    final categories = await db.allCategories();
    expect(categories.map((c) => c.name), containsAll(['Rent', 'Grocery', 'Food & Dining', 'Paycheck']));
    expect((await categoryNamed(db, 'Rent')).isFixed, isTrue);
    expect((await categoryNamed(db, 'Grocery')).isFixed, isFalse);
    expect((await categoryNamed(db, 'Paycheck')).kind, TxKind.income);
  });

  test('saves, edits, soft-deletes and restores transactions', () async {
    await addTxn(db, category: 'Grocery', cents: 4250, date: '2026-03-02', merchant: 'Costco');
    var txns = await db.transactionsBetween();
    expect(txns, hasLength(1));
    final t = txns.single;
    expect(t.merchant, 'Costco');

    await db.saveTransaction(
      id: t.id,
      kind: t.kind,
      amountCents: 5000,
      date: t.date,
      categoryId: t.categoryId,
      merchant: '  ',
    );
    txns = await db.transactionsBetween();
    expect(txns.single.amountCents, 5000);
    expect(txns.single.merchant, isNull, reason: 'blank text is stored as null');
    expect(txns.single.updatedAt.isAfter(t.createdAt) || txns.single.updatedAt == t.createdAt, isTrue);

    await db.deleteTransactions([t.id]);
    expect(await db.transactionsBetween(), isEmpty);
    await db.restoreTransactions([t.id]);
    expect(await db.transactionsBetween(), hasLength(1));
  });

  test('date range filter and years', () async {
    await addTxn(db, category: 'Grocery', cents: 100, date: '2025-12-31');
    await addTxn(db, category: 'Grocery', cents: 200, date: '2026-01-01');
    await addTxn(db, category: 'Grocery', cents: 300, date: '2026-01-31');
    final jan = await db.transactionsBetween(from: '2026-01-01', to: '2026-01-31');
    expect(jan.map((t) => t.amountCents), [300, 200]);
    expect(await db.watchYears().first, [2026, 2025]);
  });

  test('deleting a used category reassigns its transactions', () async {
    await addTxn(db, category: 'Travel', cents: 100, date: '2026-01-01');
    final travel = await categoryNamed(db, 'Travel');
    final misc = await categoryNamed(db, 'Miscellaneous');
    expect(await db.countTransactionsForCategory(travel.id), 1);
    await db.deleteCategory(travel.id, reassignTo: misc.id);
    expect((await db.allCategories()).any((c) => c.name == 'Travel'), isFalse);
    expect((await db.transactionsBetween()).single.categoryId, misc.id);
  });

  test('deleting an account clears the label but keeps transactions', () async {
    final id = await db.addAccount('Amex', AccountType.credit);
    final grocery = await categoryNamed(db, 'Grocery');
    await db.saveTransaction(
      kind: TxKind.expense,
      amountCents: 1,
      date: '2026-01-01',
      categoryId: grocery.id,
      accountId: id,
    );
    await db.deleteAccount(id);
    expect(await db.allAccounts(), isEmpty);
    expect((await db.transactionsBetween()).single.accountId, isNull);
  });

  group('recurring', () {
    test('materialises up to asOf, idempotently, and never regenerates deleted ones', () async {
      final id = await addSeries(db, category: 'Rent', cents: 180000, start: '2026-01-31');
      expect(await db.materializeRecurring(asOf: DateTime(2026, 4, 30)), 4);
      expect((await db.transactionsBetween()).map((t) => t.date).toList().reversed, [
        '2026-01-31',
        '2026-02-28',
        '2026-03-31',
        '2026-04-30',
      ]);
      expect(await db.materializeRecurring(asOf: DateTime(2026, 4, 30)), 0);

      final feb = (await db.transactionsBetween()).firstWhere((t) => t.date == '2026-02-28');
      await db.deleteTransactions([feb.id]);
      expect(await db.materializeRecurring(asOf: DateTime(2026, 5, 31)), 1);
      final dates = (await db.transactionsBetween()).map((t) => t.date).toSet();
      expect(dates, {'2026-01-31', '2026-03-31', '2026-04-30', '2026-05-31'});
      expect((await db.transactionsBetween()).every((t) => t.recurringId == id), isTrue);
    });

    test('respects end date', () async {
      await addSeries(db, category: 'Entertainment', cents: 1599, start: '2026-01-10', end: '2026-03-10');
      expect(await db.materializeRecurring(asOf: DateTime(2026, 12, 31)), 3);
    });

    test('createSeries adds past occurrences up to today only', () async {
      final grocery = await categoryNamed(db, 'Grocery');
      final start = today().subtract(const Duration(days: 14));
      await db.createSeries(
        kind: TxKind.expense,
        amountCents: 1000,
        categoryId: grocery.id,
        frequency: Frequency.weekly,
        startDate: ymd(start),
      );
      expect(await db.transactionsBetween(), hasLength(3)); // -14, -7, today
    });

    test('updateSeries: future-only by default, applyToPast rewrites history, earlier end trims', () async {
      // Bounded so updateSeries' own catch-up generation (up to real today) adds nothing.
      await addSeries(db, category: 'Rent', cents: 100000, start: '2026-01-01', end: '2026-06-01');
      await db.materializeRecurring(asOf: DateTime(2026, 6, 1));
      var s = (await db.allRecurring()).single;

      await db.updateSeries(s, amountCents: 120000, categoryId: s.categoryId, endDate: s.endDate);
      expect((await db.transactionsBetween()).every((t) => t.amountCents == 100000), isTrue);

      s = (await db.allRecurring()).single;
      await db.updateSeries(s, amountCents: 120000, categoryId: s.categoryId, endDate: s.endDate, applyToPast: true);
      expect((await db.transactionsBetween()).every((t) => t.amountCents == 120000), isTrue);

      s = (await db.allRecurring()).single;
      await db.updateSeries(s, amountCents: 120000, categoryId: s.categoryId, endDate: '2026-03-15');
      expect((await db.transactionsBetween()).map((t) => t.date).toSet(), {'2026-01-01', '2026-02-01', '2026-03-01'});
      expect((await db.allRecurring()).single.generatedThrough, '2026-03-15');
    });

    test('deleteSeries can keep or remove its transactions', () async {
      final keep = await addSeries(db, category: 'Rent', cents: 1, start: '2026-01-01');
      final drop = await addSeries(db, category: 'Home', cents: 2, start: '2026-01-01');
      await db.materializeRecurring(asOf: DateTime(2026, 3, 1));
      await db.deleteSeries(keep, deleteTransactions: false);
      await db.deleteSeries(drop, deleteTransactions: true);
      expect(await db.allRecurring(), isEmpty);
      expect((await db.transactionsBetween()).map((t) => t.amountCents).toSet(), {1});
    });
  });

  test('eraseAll wipes data and re-seeds', () async {
    await addTxn(db, category: 'Grocery', cents: 1, date: '2026-01-01');
    await db.addAccount('Cash', AccountType.cash);
    await db.eraseAll();
    expect(await db.transactionsBetween(), isEmpty);
    expect(await db.allAccounts(), isEmpty);
    expect((await db.allCategories()).map((c) => c.name), contains('Rent'));
  });
}
