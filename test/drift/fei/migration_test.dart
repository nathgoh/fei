// Migration tests against the schema snapshots in drift_schemas/. After a
// schema change, bump schemaVersion and run:
//
//   fvm dart run drift_dev make-migrations
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:fei/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('schema migrations', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      for (final toVersion in versions.skip(i + 1)) {
        test('from $fromVersion to $toVersion', () async {
          final schema = await verifier.schemaAt(fromVersion);
          final db = AppDatabase(schema.newConnection());
          await verifier.migrateAndValidate(db, toVersion);
          await db.close();
        });
      }
    }
  });

  // A v1 database as the app wrote it: no "paid with" labels were ever set,
  // so every account_id is null.
  test('v1 → v2 keeps every row', () async {
    const ts = '2026-10-01T12:00:00.000Z';
    const group = v1.CategoryGroupsData(
      id: 'g',
      createdAt: ts,
      updatedAt: ts,
      name: 'Food',
      kind: 'expense',
      sortOrder: 0,
    );
    const category = v1.CategoriesData(
      id: 'c',
      createdAt: ts,
      updatedAt: ts,
      groupId: 'g',
      name: 'Grocery',
      kind: 'expense',
      emoji: '🛒',
      color: 0xFF888888,
      isFixed: 0,
      sortOrder: 0,
    );
    const series = v1.RecurringSeriesData(
      id: 's',
      createdAt: ts,
      updatedAt: ts,
      kind: 'expense',
      amountCents: 1599,
      categoryId: 'c',
      merchant: 'Netflix',
      frequency: 'monthly',
      startDate: '2026-10-01',
      generatedThrough: '2026-10-01',
    );
    const recurringTxn = v1.TransactionsData(
      id: 't1',
      createdAt: ts,
      updatedAt: ts,
      kind: 'expense',
      amountCents: 1599,
      date: '2026-10-01',
      categoryId: 'c',
      merchant: 'Netflix',
      recurringId: 's',
    );
    const deletedTxn = v1.TransactionsData(
      id: 't2',
      createdAt: ts,
      updatedAt: ts,
      deletedAt: ts,
      kind: 'expense',
      amountCents: 4200,
      date: '2026-10-03',
      categoryId: 'c',
      notes: 'soft-deleted rows are kept for sync',
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(oldDb.categoryGroups, group);
        batch.insert(oldDb.categories, category);
        batch.insert(oldDb.recurringSeries, series);
        batch.insertAll(oldDb.transactions, [recurringTxn, deletedTxn]);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.categoryGroups).get(), [
          const v2.CategoryGroupsData(
            id: 'g',
            createdAt: ts,
            updatedAt: ts,
            name: 'Food',
            kind: 'expense',
            sortOrder: 0,
          ),
        ]);
        expect(await newDb.select(newDb.categories).get(), [
          const v2.CategoriesData(
            id: 'c',
            createdAt: ts,
            updatedAt: ts,
            groupId: 'g',
            name: 'Grocery',
            kind: 'expense',
            emoji: '🛒',
            color: 0xFF888888,
            isFixed: 0,
            sortOrder: 0,
          ),
        ]);
        expect(await newDb.select(newDb.recurringSeries).get(), [
          const v2.RecurringSeriesData(
            id: 's',
            createdAt: ts,
            updatedAt: ts,
            kind: 'expense',
            amountCents: 1599,
            categoryId: 'c',
            merchant: 'Netflix',
            frequency: 'monthly',
            startDate: '2026-10-01',
            generatedThrough: '2026-10-01',
          ),
        ]);
        expect(await newDb.select(newDb.transactions).get(), [
          const v2.TransactionsData(
            id: 't1',
            createdAt: ts,
            updatedAt: ts,
            kind: 'expense',
            amountCents: 1599,
            date: '2026-10-01',
            categoryId: 'c',
            merchant: 'Netflix',
            recurringId: 's',
          ),
          const v2.TransactionsData(
            id: 't2',
            createdAt: ts,
            updatedAt: ts,
            deletedAt: ts,
            kind: 'expense',
            amountCents: 4200,
            date: '2026-10-03',
            categoryId: 'c',
            notes: 'soft-deleted rows are kept for sync',
          ),
        ]);
      },
    );
  });

  test('the upgraded database works with the app', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);

    final names = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")
        .map((r) => r.read<String>('name'))
        .get();
    expect(names, containsAll(['transactions', 'recurring_series', 'idx_transactions_date']));
    expect(names, isNot(contains('accounts')));

    final groupId = await db.addGroup('Food', TxKind.expense);
    final categoryId = await db.addCategory(name: 'Grocery', groupId: groupId, kind: TxKind.expense);
    await db.saveTransaction(kind: TxKind.expense, amountCents: 100, date: '2026-11-01', categoryId: categoryId);
    expect(await db.transactionsBetween(), hasLength(1));
    await db.close();
  });
}
