import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fei/data/database.dart';

/// A fresh in-memory database, seeded with the default categories on first use.
AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Future<Category> categoryNamed(AppDatabase db, String name) async =>
    (await db.allCategories()).firstWhere((c) => c.name == name);

/// Adds a transaction in the named (seeded) category. Its kind follows the
/// category, so 'Paycheck' is income and 'Grocery' an expense.
Future<void> addTxn(
  AppDatabase db, {
  required String category,
  required int cents,
  required String date,
  String? merchant,
  String? notes,
}) async {
  final c = await categoryNamed(db, category);
  await db.saveTransaction(
    kind: c.kind,
    amountCents: cents,
    date: date,
    categoryId: c.id,
    merchant: merchant,
    notes: notes,
  );
}

/// Inserts a series without generating occurrences, so tests control when
/// [AppDatabase.materializeRecurring] runs.
Future<String> addSeries(
  AppDatabase db, {
  required String category,
  required int cents,
  required String start,
  Frequency frequency = Frequency.monthly,
  String? end,
  String? merchant,
}) async {
  final c = await categoryNamed(db, category);
  final id = newId();
  await db
      .into(db.recurringSeriesTable)
      .insert(
        RecurringSeriesTableCompanion.insert(
          id: Value(id),
          kind: c.kind,
          amountCents: cents,
          categoryId: c.id,
          merchant: Value(merchant),
          frequency: frequency,
          startDate: start,
          endDate: Value(end),
        ),
      );
  return id;
}

int sumCents(Iterable<Txn> txns) => txns.fold(0, (a, t) => a + t.amountCents);
