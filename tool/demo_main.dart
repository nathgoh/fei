// Runs the app with ~10 months of realistic sample data, for previewing the UI:
//
//   fvm flutter run -t tool/demo_main.dart
//
// Seeding happens only when the database has no transactions, so it won't
// touch real data. Not part of the shipped app.
import 'dart:math';

import 'package:fei/core/dates.dart';
import 'package:fei/data/database.dart';
import 'package:fei/main.dart' as app;

Future<void> main() async {
  final db = AppDatabase();
  if ((await db.transactionsBetween()).isEmpty) await _seed(db);
  await db.close();
  await app.main();
}

Future<void> _seed(AppDatabase db) async {
  final rng = Random(7);
  final cats = {for (final c in await db.allCategories()) c.name: c.id};
  final now = today();
  final start = DateTime(now.year, now.month - 9, 1);

  await db.createSeries(
    kind: TxKind.income,
    amountCents: 412500,
    categoryId: cats['Paycheck']!,
    merchant: 'Acme Corp',
    frequency: Frequency.biweekly,
    startDate: ymd(addDays(start, 4)),
  );
  await db.createSeries(
    kind: TxKind.expense,
    amountCents: 210000,
    categoryId: cats['Rent']!,
    merchant: 'Landlord',
    frequency: Frequency.monthly,
    startDate: ymd(start),
  );
  await db.createSeries(
    kind: TxKind.expense,
    amountCents: 1599,
    categoryId: cats['Entertainment']!,
    merchant: 'Netflix',
    frequency: Frequency.monthly,
    startDate: ymd(addDays(start, 11)),
  );
  await db.createSeries(
    kind: TxKind.expense,
    amountCents: 6500,
    categoryId: cats['Utility']!,
    merchant: 'PG&E',
    frequency: Frequency.monthly,
    startDate: ymd(addDays(start, 19)),
  );
  await db.createSeries(
    kind: TxKind.expense,
    amountCents: 4500,
    categoryId: cats['Health']!,
    merchant: 'Gym',
    frequency: Frequency.monthly,
    startDate: ymd(addDays(start, 2)),
  );

  final spend = <String, ({List<String> merchants, int min, int max, int perMonth})>{
    'Grocery': (merchants: ['Costco', 'Safeway', "Trader Joe's"], min: 2500, max: 16000, perMonth: 6),
    'Food & Dining': (
      merchants: ['Chipotle', 'Sushi Ran', 'Blue Bottle', 'Pizzeria'],
      min: 600,
      max: 9000,
      perMonth: 9,
    ),
    'Transportation': (merchants: ['Shell', 'Uber', 'Clipper'], min: 300, max: 6500, perMonth: 4),
    'Personal': (merchants: ['Uniqlo', 'Haircut', 'Amazon'], min: 1500, max: 12000, perMonth: 2),
    'Home': (merchants: ['IKEA', 'Target', 'Home Depot'], min: 1200, max: 18000, perMonth: 1),
    'Entertainment': (merchants: ['AMC', 'Steam', 'Concert'], min: 1200, max: 9000, perMonth: 1),
    'Miscellaneous': (merchants: ['USPS', 'Gift'], min: 500, max: 5000, perMonth: 1),
  };
  for (var m = 0; m < 10; m++) {
    final month = DateTime(start.year, start.month + m);
    final lastDay = month.year == now.year && month.month == now.month ? now.day : daysInMonth(month.year, month.month);
    for (final entry in spend.entries) {
      for (var i = 0; i < entry.value.perMonth; i++) {
        final v = entry.value;
        await db.saveTransaction(
          kind: TxKind.expense,
          amountCents: v.min + rng.nextInt(v.max - v.min),
          date: ymd(DateTime(month.year, month.month, 1 + rng.nextInt(lastDay))),
          categoryId: cats[entry.key]!,
          merchant: v.merchants[rng.nextInt(v.merchants.length)],
        );
      }
    }
    if (m == 5) {
      await db.saveTransaction(
        kind: TxKind.expense,
        amountCents: 186000,
        date: ymd(DateTime(month.year, month.month, 12)),
        categoryId: cats['Travel']!,
        merchant: 'United Airlines',
        notes: 'Flights to Tokyo',
      );
    }
    if (m % 3 == 2) {
      await db.saveTransaction(
        kind: TxKind.income,
        amountCents: 3000 + rng.nextInt(4000),
        date: ymd(DateTime(month.year, month.month, lastDay)),
        categoryId: cats['Interest']!,
        merchant: 'HYSA interest',
      );
    }
  }
}
