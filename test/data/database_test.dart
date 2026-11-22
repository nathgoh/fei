import 'package:drift/drift.dart' show Value;
import 'package:fei/core/dates.dart';
import 'package:fei/data/database.dart';
import 'package:fei/data/seed.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  group('seed', () {
    test('creates the default groups and categories, with Rent fixed', () async {
      final groups = await db.allGroups();
      expect(groups.map((g) => g.name), unorderedEquals(defaultGroups.map((g) => g.name)));
      final categories = await db.allCategories();
      expect(categories.map((c) => c.name), containsAll(['Rent', 'Grocery', 'Food & Dining', 'Paycheck', 'Interest']));
      expect((await categoryNamed(db, 'Rent')).isFixed, isTrue);
      expect(categories.where((c) => c.isFixed).map((c) => c.name), ['Rent']);
      expect((await categoryNamed(db, 'Paycheck')).kind, TxKind.income);
      expect((await categoryNamed(db, 'Grocery')).kind, TxKind.expense);
    });

    test('every category belongs to a group of the same kind', () async {
      final groups = {for (final g in await db.allGroups()) g.id: g};
      for (final c in await db.allCategories()) {
        expect(groups[c.groupId]?.kind, c.kind, reason: c.name);
      }
    });

    test('ids are UUIDs and rows carry sync timestamps', () async {
      final c = await categoryNamed(db, 'Grocery');
      expect(c.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$')));
      expect(c.deletedAt, isNull);
      expect(c.createdAt.isUtc, isTrue);
    });
  });

  group('categories and groups', () {
    test('add, rename and delete a group', () async {
      final id = await db.addGroup('Pets', TxKind.expense);
      await db.renameGroup(id, 'Pet care');
      expect((await db.allGroups()).map((g) => g.name), contains('Pet care'));

      final vet = await db.addCategory(name: 'Vet', groupId: id, kind: TxKind.expense, emoji: '🐶');
      expect(await db.deleteGroup(id), isFalse, reason: 'still has a category');

      await db.deleteCategory(vet);
      expect(await db.deleteGroup(id), isTrue);
      expect((await db.allGroups()).map((g) => g.name), isNot(contains('Pet care')));
    });

    test('updateCategory changes fields and bumps updatedAt', () async {
      final utility = await categoryNamed(db, 'Utility');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.updateCategory(utility.id, const CategoriesCompanion(isFixed: Value(true), emoji: Value('⚡')));
      final updated = await categoryNamed(db, 'Utility');
      expect(updated.isFixed, isTrue);
      expect(updated.emoji, '⚡');
      expect(updated.updatedAt.isAfter(utility.updatedAt), isTrue);
    });

    test('deleting a used category moves its transactions and series', () async {
      await addTxn(db, category: 'Travel', cents: 100, date: '2026-01-01');
      await addSeries(db, category: 'Travel', cents: 200, start: '2026-01-01', end: '2026-01-01');
      final travel = await categoryNamed(db, 'Travel');
      final misc = await categoryNamed(db, 'Miscellaneous');
      expect(await db.countTransactionsForCategory(travel.id), 1);

      await db.deleteCategory(travel.id, reassignTo: misc.id);
      expect((await db.allCategories()).map((c) => c.name), isNot(contains('Travel')));
      expect((await db.transactionsBetween()).single.categoryId, misc.id);
      expect((await db.allRecurring()).single.categoryId, misc.id);
    });

    test('watchCategories emits changes', () async {
      final group = (await db.allGroups()).first;
      final names = db.watchCategories().map((cs) => cs.map((c) => c.name).toList());
      final done = expectLater(names, emitsThrough(contains('Bakery')));
      await db.addCategory(name: 'Bakery', groupId: group.id, kind: group.kind);
      await done;
    });
  });

  group('transactions', () {
    test('save, edit, soft-delete and restore', () async {
      await addTxn(db, category: 'Grocery', cents: 4250, date: '2026-03-02', merchant: 'Costco');
      final t = (await db.transactionsBetween()).single;
      expect(t.merchant, 'Costco');
      expect(t.recurringId, isNull);

      await db.saveTransaction(
        id: t.id,
        kind: t.kind,
        amountCents: 5000,
        date: t.date,
        categoryId: t.categoryId,
        merchant: '  ',
        notes: ' weekly shop ',
      );
      final edited = (await db.transactionsBetween()).single;
      expect(edited.id, t.id);
      expect(edited.amountCents, 5000);
      expect(edited.merchant, isNull, reason: 'blank text is stored as null');
      expect(edited.notes, 'weekly shop');
      expect(edited.updatedAt.isBefore(t.updatedAt), isFalse);

      await db.deleteTransactions([t.id]);
      expect(await db.transactionsBetween(), isEmpty);
      await db.restoreTransactions([t.id]);
      expect(await db.transactionsBetween(), hasLength(1));
    });

    test('range filter is inclusive and newest first', () async {
      await addTxn(db, category: 'Grocery', cents: 100, date: '2025-12-31');
      await addTxn(db, category: 'Grocery', cents: 200, date: '2026-01-01');
      await addTxn(db, category: 'Grocery', cents: 300, date: '2026-01-31');
      await addTxn(db, category: 'Grocery', cents: 400, date: '2026-02-01');
      final jan = await db.transactionsBetween(from: '2026-01-01', to: '2026-01-31');
      expect(jan.map((t) => t.amountCents), [300, 200]);
      expect(await db.transactionsBetween(from: '2026-01-15'), hasLength(2));
      expect(await db.transactionsBetween(to: '2025-12-31'), hasLength(1));
    });

    test('watchYears lists years with live transactions, newest first', () async {
      await addTxn(db, category: 'Grocery', cents: 100, date: '2024-06-01');
      await addTxn(db, category: 'Grocery', cents: 100, date: '2026-01-01');
      await addTxn(db, category: 'Grocery', cents: 100, date: '2025-12-31');
      expect(await db.watchYears().first, [2026, 2025, 2024]);

      final old = (await db.transactionsBetween(to: '2024-12-31')).single;
      await db.deleteTransactions([old.id]);
      expect(await db.watchYears().first, [2026, 2025]);
    });

    test('watchTransactions emits new rows in range', () async {
      final stream = db.watchTransactions(from: '2026-01-01', to: '2026-01-31').map((ts) => ts.length);
      final done = expectLater(stream, emitsInOrder([0, emitsThrough(1)]));
      await addTxn(db, category: 'Grocery', cents: 100, date: '2025-12-31'); // out of range
      await addTxn(db, category: 'Grocery', cents: 100, date: '2026-01-10');
      await done;
    });
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
      final txns = await db.transactionsBetween();
      expect(txns.map((t) => t.date).toSet(), {'2026-01-31', '2026-03-31', '2026-04-30', '2026-05-31'});
      expect(txns.every((t) => t.recurringId == id), isTrue);
      expect((await db.allRecurring()).single.generatedThrough, '2026-05-31');
    });

    test('occurrences copy the series details', () async {
      await addSeries(
        db,
        category: 'Paycheck',
        cents: 412500,
        start: '2026-01-02',
        merchant: 'Acme Corp',
        end: '2026-01-02',
      );
      await db.materializeRecurring(asOf: DateTime(2026, 1, 31));
      final t = (await db.transactionsBetween()).single;
      expect(t.kind, TxKind.income);
      expect(t.amountCents, 412500);
      expect(t.merchant, 'Acme Corp');
      expect(t.categoryId, (await categoryNamed(db, 'Paycheck')).id);
    });

    test('stops at the end date', () async {
      await addSeries(db, category: 'Entertainment', cents: 1599, start: '2026-01-10', end: '2026-03-10');
      expect(await db.materializeRecurring(asOf: DateTime(2026, 12, 31)), 3);
      expect(await db.materializeRecurring(asOf: DateTime(2027, 12, 31)), 0);
    });

    test('a series starting in the future generates nothing yet', () async {
      await addSeries(db, category: 'Rent', cents: 1, start: '2026-06-01');
      expect(await db.materializeRecurring(asOf: DateTime(2026, 5, 31)), 0);
      expect((await db.allRecurring()).single.generatedThrough, isNull);
      expect(await db.materializeRecurring(asOf: DateTime(2026, 6, 1)), 1);
    });

    test('materializeRecurring(seriesId) only touches that series', () async {
      final a = await addSeries(db, category: 'Rent', cents: 1, start: '2026-01-01');
      await addSeries(db, category: 'Home', cents: 2, start: '2026-01-01');
      expect(await db.materializeRecurring(seriesId: a, asOf: DateTime(2026, 2, 1)), 2);
      expect((await db.transactionsBetween()).map((t) => t.amountCents).toSet(), {1});
    });

    test('createSeries adds past occurrences up to today only', () async {
      final grocery = await categoryNamed(db, 'Grocery');
      await db.createSeries(
        kind: TxKind.expense,
        amountCents: 1000,
        categoryId: grocery.id,
        merchant: 'Farm box',
        frequency: Frequency.weekly,
        startDate: ymd(today().subtract(const Duration(days: 14))),
      );
      final txns = await db.transactionsBetween();
      expect(txns, hasLength(3)); // 14 and 7 days ago, and today
      expect(txns.first.date, todayYmd());
      expect((await db.allRecurring()).single.generatedThrough, todayYmd());
    });

    test('updateSeries: future-only by default, applyToPast rewrites history, earlier end trims', () async {
      // Bounded so updateSeries' own catch-up generation (up to real today) adds nothing.
      await addSeries(db, category: 'Rent', cents: 100000, start: '2026-01-01', end: '2026-06-01');
      await db.materializeRecurring(asOf: DateTime(2026, 6, 1));
      var s = (await db.allRecurring()).single;

      await db.updateSeries(s, amountCents: 120000, categoryId: s.categoryId, endDate: s.endDate);
      expect((await db.allRecurring()).single.amountCents, 120000);
      expect((await db.transactionsBetween()).every((t) => t.amountCents == 100000), isTrue);

      s = (await db.allRecurring()).single;
      final home = await categoryNamed(db, 'Home');
      await db.updateSeries(
        s,
        amountCents: 120000,
        categoryId: home.id,
        merchant: 'Landlord',
        endDate: s.endDate,
        applyToPast: true,
      );
      final rewritten = await db.transactionsBetween();
      expect(rewritten.every((t) => t.amountCents == 120000 && t.categoryId == home.id), isTrue);
      expect(rewritten.every((t) => t.merchant == 'Landlord'), isTrue);

      s = (await db.allRecurring()).single;
      await db.updateSeries(s, amountCents: 120000, categoryId: s.categoryId, endDate: '2026-03-15');
      expect((await db.transactionsBetween()).map((t) => t.date).toSet(), {'2026-01-01', '2026-02-01', '2026-03-01'});
      expect((await db.allRecurring()).single.generatedThrough, '2026-03-15');
    });

    test('stopSeries ends today and keeps past occurrences', () async {
      final start = today().subtract(const Duration(days: 21));
      await addSeries(db, category: 'Health', cents: 4500, start: ymd(start), frequency: Frequency.weekly);
      await db.materializeRecurring();
      final before = await db.transactionsBetween();

      await db.stopSeries((await db.allRecurring()).single);
      expect((await db.allRecurring()).single.endDate, todayYmd());
      expect(await db.transactionsBetween(), hasLength(before.length));
    });

    test('deleteSeries keeps or removes its transactions', () async {
      final keep = await addSeries(db, category: 'Rent', cents: 1, start: '2026-01-01');
      final drop = await addSeries(db, category: 'Home', cents: 2, start: '2026-01-01');
      await db.materializeRecurring(asOf: DateTime(2026, 3, 1));
      await db.deleteSeries(keep, deleteTransactions: false);
      await db.deleteSeries(drop, deleteTransactions: true);
      expect(await db.allRecurring(), isEmpty);
      expect((await db.transactionsBetween()).map((t) => t.amountCents).toSet(), {1});
      // A deleted series is never generated again.
      expect(await db.materializeRecurring(asOf: DateTime(2026, 12, 1)), 0);
    });
  });

  test('eraseAll wipes data and re-seeds the defaults', () async {
    await addTxn(db, category: 'Grocery', cents: 1, date: '2026-01-01');
    await addSeries(db, category: 'Rent', cents: 1, start: '2026-01-01');
    final group = (await db.allGroups()).first;
    await db.addCategory(name: 'Custom', groupId: group.id, kind: group.kind);

    await db.eraseAll();
    expect(await db.transactionsBetween(), isEmpty);
    expect(await db.allRecurring(), isEmpty);
    final names = (await db.allCategories()).map((c) => c.name);
    expect(names, contains('Rent'));
    expect(names, isNot(contains('Custom')));
  });
}
