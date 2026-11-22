import 'package:fei/core/dates.dart';
import 'package:fei/core/money.dart';
import 'package:fei/data/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/db.dart';

void main() {
  final now = today();

  Future<void> seed(AppDatabase db) async {
    await addSeries(
      db,
      category: 'Health',
      cents: 4500,
      start: todayYmd(),
      frequency: Frequency.weekly,
      merchant: 'Gym',
    );
    await addSeries(
      db,
      category: 'Entertainment',
      cents: 1599,
      start: ymd(now.subtract(const Duration(days: 90))),
      end: ymd(now.subtract(const Duration(days: 30))),
      merchant: 'Old streaming',
    );
    await db.materializeRecurring();
  }

  testWidgets('shows monthly cost, what is coming up, and active vs ended series', (tester) async {
    await pumpFei(tester, seed: seed);
    await openTab(tester, 'Recurring');

    expect(find.text(formatMoney(19500)), findsOneWidget); // $45 weekly ≈ $195 a month
    expect(find.text('per month, 1 active'), findsOneWidget);
    expect(find.text('Gym'), findsWidgets);
    expect(find.text('Weekly · Next ${formatDateShort(now.add(const Duration(days: 7)))}'), findsOneWidget);

    await scrollTo(tester, find.text('Ended (1)'));
    await tester.tap(find.text('Ended (1)'));
    await settle(tester);
    expect(find.text('Old streaming'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('editing a series: change the amount, then end it today', (tester) async {
    final (db, _) = await pumpFei(tester, seed: seed);
    await openTab(tester, 'Recurring');
    await tester.tap(find.text('Gym').last);
    await settle(tester);
    expect(find.text('Edit recurring'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '50');
    await tester.tap(find.text('Save'));
    await settle(tester);
    final gym = (await dbRun(tester, db.allRecurring)).firstWhere((s) => s.merchant == 'Gym');
    expect(gym.amountCents, 5000);

    await tester.tap(find.text('Gym').last);
    await settle(tester);
    await tester.ensureVisible(find.text('End today'));
    await tester.tap(find.text('End today'));
    await settle(tester);
    final ended = (await dbRun(tester, db.allRecurring)).firstWhere((s) => s.merchant == 'Gym');
    expect(ended.endDate, todayYmd());
    await unmount(tester);
  });

  testWidgets('deleting a series can keep its transactions', (tester) async {
    final (db, _) = await pumpFei(tester, seed: seed);
    await openTab(tester, 'Recurring');
    final before = (await dbRun(tester, db.transactionsBetween)).length;

    await tester.tap(find.text('Gym').last);
    await settle(tester);
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Keep transactions'));
    await settle(tester);

    expect((await dbRun(tester, db.allRecurring)).map((s) => s.merchant), ['Old streaming']);
    expect(await dbRun(tester, db.transactionsBetween), hasLength(before));
    await unmount(tester);
  });
}
