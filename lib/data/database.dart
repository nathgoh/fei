import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/dates.dart';
import 'seed.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [CategoryGroups, Categories, Accounts, RecurringSeriesTable, Transactions])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static QueryExecutor _openConnection() => driftDatabase(
    name: 'fei',
    web: DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')),
  );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('CREATE INDEX idx_transactions_date ON transactions (date)');
      await seedDefaults(this);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  DateTime get _now => DateTime.now().toUtc();

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  Stream<List<CategoryGroup>> watchGroups() =>
      (select(categoryGroups)
            ..where((g) => g.deletedAt.isNull())
            ..orderBy([(g) => OrderingTerm(expression: g.sortOrder), (g) => OrderingTerm(expression: g.name)]))
          .watch();

  Stream<List<Category>> watchCategories() =>
      (select(categories)
            ..where((c) => c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm(expression: c.sortOrder), (c) => OrderingTerm(expression: c.name)]))
          .watch();

  Future<List<Category>> allCategories() => (select(categories)..where((c) => c.deletedAt.isNull())).get();

  Future<List<CategoryGroup>> allGroups() => (select(categoryGroups)..where((g) => g.deletedAt.isNull())).get();

  Future<String> addGroup(String name, TxKind kind) async {
    final count = (await allGroups()).length;
    final id = newId();
    await into(categoryGroups)
        .insert(CategoryGroupsCompanion.insert(id: Value(id), name: name, kind: kind, sortOrder: Value(count)));
    return id;
  }

  Future<void> renameGroup(String id, String name) => (update(
    categoryGroups,
  )..where((g) => g.id.equals(id))).write(CategoryGroupsCompanion(name: Value(name), updatedAt: Value(_now)));

  /// Deletes an empty group. Returns false if it still has categories.
  Future<bool> deleteGroup(String id) async {
    final inUse = await (select(categories)..where((c) => c.groupId.equals(id) & c.deletedAt.isNull())).get();
    if (inUse.isNotEmpty) return false;
    await (update(
      categoryGroups,
    )..where((g) => g.id.equals(id))).write(CategoryGroupsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)));
    return true;
  }

  Future<String> addCategory({
    required String name,
    required String groupId,
    required TxKind kind,
    String emoji = '🏷️',
    int color = 0xFF888888,
    bool isFixed = false,
  }) async {
    final id = newId();
    final count = (await allCategories()).length;
    await into(categories).insert(
      CategoriesCompanion.insert(
        id: Value(id),
        groupId: groupId,
        name: name,
        kind: kind,
        emoji: Value(emoji),
        color: Value(color),
        isFixed: Value(isFixed),
        sortOrder: Value(count),
      ),
    );
    return id;
  }

  Future<void> updateCategory(String id, CategoriesCompanion changes) =>
      (update(categories)..where((c) => c.id.equals(id))).write(changes.copyWith(updatedAt: Value(_now)));

  Future<int> countTransactionsForCategory(String id) async {
    final count = transactions.id.count();
    final row =
        await (selectOnly(transactions)
              ..addColumns([count])
              ..where(transactions.categoryId.equals(id) & transactions.deletedAt.isNull()))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Soft-deletes a category, first moving its transactions and recurring
  /// series to [reassignTo] (required when the category is in use).
  Future<void> deleteCategory(String id, {String? reassignTo}) => transaction(() async {
    if (reassignTo != null) {
      await (update(transactions)..where((t) => t.categoryId.equals(id))).write(
        TransactionsCompanion(categoryId: Value(reassignTo), updatedAt: Value(_now)),
      );
      await (update(recurringSeriesTable)..where((r) => r.categoryId.equals(id))).write(
        RecurringSeriesTableCompanion(categoryId: Value(reassignTo), updatedAt: Value(_now)),
      );
    }
    await (update(
      categories,
    )..where((c) => c.id.equals(id))).write(CategoriesCompanion(deletedAt: Value(_now), updatedAt: Value(_now)));
  });

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  Stream<List<Account>> watchAccounts() =>
      (select(accounts)
            ..where((a) => a.deletedAt.isNull())
            ..orderBy([(a) => OrderingTerm(expression: a.sortOrder), (a) => OrderingTerm(expression: a.name)]))
          .watch();

  Future<List<Account>> allAccounts() => (select(accounts)..where((a) => a.deletedAt.isNull())).get();

  Future<String> addAccount(String name, AccountType type) async {
    final id = newId();
    final count = (await allAccounts()).length;
    await into(accounts)
        .insert(AccountsCompanion.insert(id: Value(id), name: name, type: Value(type), sortOrder: Value(count)));
    return id;
  }

  Future<void> updateAccount(String id, AccountsCompanion changes) =>
      (update(accounts)..where((a) => a.id.equals(id))).write(changes.copyWith(updatedAt: Value(_now)));

  /// Soft-deletes an account label; transactions keep their history but lose the label.
  Future<void> deleteAccount(String id) => transaction(() async {
    await (update(transactions)..where((t) => t.accountId.equals(id))).write(
      TransactionsCompanion(accountId: const Value(null), updatedAt: Value(_now)),
    );
    await (update(recurringSeriesTable)..where((r) => r.accountId.equals(id))).write(
      RecurringSeriesTableCompanion(accountId: const Value(null), updatedAt: Value(_now)),
    );
    await (update(
      accounts,
    )..where((a) => a.id.equals(id))).write(AccountsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)));
  });

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  /// Transactions in an inclusive `YYYY-MM-DD` range, newest first.
  Stream<List<Txn>> watchTransactions({String? from, String? to}) {
    final q = select(transactions)..where((t) => t.deletedAt.isNull());
    if (from != null) q.where((t) => t.date.isBiggerOrEqualValue(from));
    if (to != null) q.where((t) => t.date.isSmallerOrEqualValue(to));
    q.orderBy([
      (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return q.watch();
  }

  Future<List<Txn>> transactionsBetween({String? from, String? to}) => watchTransactions(from: from, to: to).first;

  Stream<List<int>> watchYears() {
    final year = transactions.date.substr(1, 4);
    final q = selectOnly(transactions, distinct: true)
      ..addColumns([year])
      ..where(transactions.deletedAt.isNull())
      ..orderBy([OrderingTerm(expression: year, mode: OrderingMode.desc)]);
    return q.map((row) => int.parse(row.read(year)!)).watch();
  }

  Future<void> saveTransaction({
    String? id,
    required TxKind kind,
    required int amountCents,
    required String date,
    required String categoryId,
    String? accountId,
    String? merchant,
    String? notes,
    String? recurringId,
  }) async {
    final companion = TransactionsCompanion(
      kind: Value(kind),
      amountCents: Value(amountCents),
      date: Value(date),
      categoryId: Value(categoryId),
      accountId: Value(accountId),
      merchant: Value(_blankToNull(merchant)),
      notes: Value(_blankToNull(notes)),
      updatedAt: Value(_now),
    );
    if (id == null) {
      await into(transactions).insert(companion.copyWith(id: Value(newId()), recurringId: Value(recurringId)));
    } else {
      await (update(transactions)..where((t) => t.id.equals(id))).write(companion);
    }
  }

  Future<void> deleteTransactions(Iterable<String> ids) => (update(
    transactions,
  )..where((t) => t.id.isIn(ids))).write(TransactionsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)));

  Future<void> restoreTransactions(Iterable<String> ids) => (update(
    transactions,
  )..where((t) => t.id.isIn(ids))).write(TransactionsCompanion(deletedAt: const Value(null), updatedAt: Value(_now)));

  // ---------------------------------------------------------------------------
  // Recurring
  // ---------------------------------------------------------------------------

  Stream<List<RecurringSeries>> watchRecurring() =>
      (select(recurringSeriesTable)
            ..where((r) => r.deletedAt.isNull())
            ..orderBy([(r) => OrderingTerm(expression: r.startDate)]))
          .watch();

  Future<List<RecurringSeries>> allRecurring() =>
      (select(recurringSeriesTable)..where((r) => r.deletedAt.isNull())).get();

  Future<String> createSeries({
    required TxKind kind,
    required int amountCents,
    required String categoryId,
    String? accountId,
    String? merchant,
    String? notes,
    required Frequency frequency,
    required String startDate,
    String? endDate,
  }) async {
    final id = newId();
    await into(recurringSeriesTable).insert(
      RecurringSeriesTableCompanion.insert(
        id: Value(id),
        kind: kind,
        amountCents: amountCents,
        categoryId: categoryId,
        accountId: Value(accountId),
        merchant: Value(_blankToNull(merchant)),
        notes: Value(_blankToNull(notes)),
        frequency: frequency,
        startDate: startDate,
        endDate: Value(endDate),
      ),
    );
    await materializeRecurring(seriesId: id);
    return id;
  }

  /// Updates a series. Changes always apply to future occurrences; with
  /// [applyToPast] they're also written to already-generated transactions.
  /// Moving the end date earlier removes generated occurrences after it.
  Future<void> updateSeries(
    RecurringSeries s, {
    required int amountCents,
    required String categoryId,
    String? accountId,
    String? merchant,
    String? notes,
    String? endDate,
    bool applyToPast = false,
  }) => transaction(() async {
    var generatedThrough = s.generatedThrough;
    if (endDate != null && generatedThrough != null && endDate.compareTo(generatedThrough) < 0) {
      await (update(transactions)..where((t) => t.recurringId.equals(s.id) & t.date.isBiggerThanValue(endDate))).write(
        TransactionsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)),
      );
      generatedThrough = endDate;
    }
    await (update(recurringSeriesTable)..where((r) => r.id.equals(s.id))).write(
      RecurringSeriesTableCompanion(
        amountCents: Value(amountCents),
        categoryId: Value(categoryId),
        accountId: Value(accountId),
        merchant: Value(_blankToNull(merchant)),
        notes: Value(_blankToNull(notes)),
        endDate: Value(endDate),
        generatedThrough: Value(generatedThrough),
        updatedAt: Value(_now),
      ),
    );
    if (applyToPast) {
      await (update(transactions)..where((t) => t.recurringId.equals(s.id) & t.deletedAt.isNull())).write(
        TransactionsCompanion(
          amountCents: Value(amountCents),
          categoryId: Value(categoryId),
          accountId: Value(accountId),
          merchant: Value(_blankToNull(merchant)),
          notes: Value(_blankToNull(notes)),
          updatedAt: Value(_now),
        ),
      );
    }
    await materializeRecurring(seriesId: s.id);
  });

  /// Ends a series today; past occurrences are kept.
  Future<void> stopSeries(RecurringSeries s) => updateSeries(
    s,
    amountCents: s.amountCents,
    categoryId: s.categoryId,
    accountId: s.accountId,
    merchant: s.merchant,
    notes: s.notes,
    endDate: todayYmd(),
  );

  Future<void> deleteSeries(String id, {required bool deleteTransactions}) => transaction(() async {
    if (deleteTransactions) {
      await (update(transactions)..where((t) => t.recurringId.equals(id))).write(
        TransactionsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)),
      );
    }
    await (update(recurringSeriesTable)..where((r) => r.id.equals(id))).write(
      RecurringSeriesTableCompanion(deletedAt: Value(_now), updatedAt: Value(_now)),
    );
  });

  /// Generates any occurrences due up to [asOf] (default today) that haven't
  /// been generated yet. Safe to call repeatedly.
  Future<int> materializeRecurring({String? seriesId, DateTime? asOf}) => transaction(() async {
    final limit = asOf ?? today();
    final q = select(recurringSeriesTable)..where((r) => r.deletedAt.isNull());
    if (seriesId != null) q.where((r) => r.id.equals(seriesId));
    var created = 0;
    for (final s in await q.get()) {
      final start = parseYmd(s.startDate);
      final from = s.generatedThrough == null ? start : parseYmd(s.generatedThrough!).add(const Duration(days: 1));
      final end = s.endDate == null ? null : parseYmd(s.endDate!);
      final upTo = end != null && end.isBefore(limit) ? end : limit;
      if (upTo.isBefore(from)) continue;

      for (final d in occurrencesBetween(start, s.frequency, from, upTo)) {
        await into(transactions).insert(
          TransactionsCompanion.insert(
            id: Value(newId()),
            kind: s.kind,
            amountCents: s.amountCents,
            date: ymd(d),
            categoryId: s.categoryId,
            accountId: Value(s.accountId),
            merchant: Value(s.merchant),
            notes: Value(s.notes),
            recurringId: Value(s.id),
          ),
        );
        created++;
      }
      await (update(recurringSeriesTable)..where((r) => r.id.equals(s.id))).write(
        RecurringSeriesTableCompanion(generatedThrough: Value(ymd(upTo)), updatedAt: Value(_now)),
      );
    }
    return created;
  });

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  /// Permanently removes everything and re-seeds the default categories.
  Future<void> eraseAll() => transaction(() async {
    await delete(transactions).go();
    await delete(recurringSeriesTable).go();
    await delete(accounts).go();
    await delete(categories).go();
    await delete(categoryGroups).go();
    await seedDefaults(this);
  });
}

String? _blankToNull(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}
