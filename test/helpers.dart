import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fei/data/database.dart';

AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Future<Category> categoryNamed(AppDatabase db, String name) async =>
    (await db.allCategories()).firstWhere((c) => c.name == name);

Future<void> addTxn(
  AppDatabase db, {
  required String category,
  required int cents,
  required String date,
  TxKind kind = TxKind.expense,
  String? merchant,
}) async {
  final c = await categoryNamed(db, category);
  await db.saveTransaction(kind: kind, amountCents: cents, date: date, categoryId: c.id, merchant: merchant);
}

Future<String> addSeries(
  AppDatabase db, {
  required String category,
  required int cents,
  required String start,
  Frequency frequency = Frequency.monthly,
  String? end,
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
          frequency: frequency,
          startDate: start,
          endDate: Value(end),
        ),
      );
  return id;
}
