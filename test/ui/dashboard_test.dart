import 'dart:math';

import 'package:fei/core/dates.dart';
import 'package:fei/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/db.dart';

void main() {
  final now = today();
  final thisMonth = DateTime(now.year, now.month);
  final lastMonth = DateTime(now.year, now.month - 1);
  final twoBack = DateTime(now.year, now.month - 2);
  String firstOf(DateTime m) => ymd(DateTime(m.year, m.month, 1));

  testWidgets('summary, top categories and recent transactions for this month', (tester) async {
    await pumpFei(
      tester,
      seed: (db) async {
        await addTxn(db, category: 'Paycheck', cents: 400000, date: firstOf(thisMonth), merchant: 'Acme Corp');
        await addTxn(db, category: 'Rent', cents: 200000, date: firstOf(thisMonth), merchant: 'Landlord');
        await addTxn(db, category: 'Grocery', cents: 12345, date: firstOf(thisMonth), merchant: 'Costco');
        await addTxn(db, category: 'Grocery', cents: 99999, date: firstOf(lastMonth), merchant: 'Last month shop');
      },
    );

    expect(find.text(r'$4,000.00'), findsOneWidget); // income
    expect(find.text(r'$2,123.45'), findsOneWidget); // expenses
    expect(find.text(r'$1,876.55'), findsOneWidget); // saved
    expect(find.text('Saved 46.9% of income'), findsOneWidget);
    expect(find.text(r'+ $2,000.00 fixed'), findsOneWidget);

    await scrollTo(tester, find.text('Costco'));
    expect(find.text('Costco'), findsOneWidget);
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('Last month shop'), findsNothing);
    await unmount(tester);
  });

  testWidgets('dashboard offers a way back to the current month', (tester) async {
    await pumpFei(tester);
    final current = formatMonthYear(now.year, now.month);
    expect(find.text(current), findsOneWidget);
    expect(find.text('Present'), findsNothing);

    await tester.tap(find.byTooltip('Previous'));
    await tester.tap(find.byTooltip('Previous'));
    await settle(tester);
    expect(find.text(formatMonthYear(twoBack.year, twoBack.month)), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);

    await tester.tap(find.text('Present'));
    await settle(tester);
    expect(find.text(current), findsOneWidget);
    expect(find.text('Present'), findsNothing);
    await unmount(tester);
  });

  testWidgets('flexible spending compares a finished month with the whole month before', (tester) async {
    await pumpFei(
      tester,
      seed: (db) async {
        await addTxn(db, category: 'Grocery', cents: 5000, date: firstOf(lastMonth));
        await addTxn(db, category: 'Rent', cents: 200000, date: firstOf(lastMonth)); // fixed: not compared
        await addTxn(db, category: 'Grocery', cents: 8000, date: firstOf(twoBack));
      },
    );
    await tester.tap(find.byTooltip('Previous'));
    await settle(tester);

    expect(find.text('\$30.00 less than ${monthShort(twoBack.month)}'), findsOneWidget);
    // The chart key names both months.
    expect(find.text(monthShort(lastMonth.month)), findsOneWidget);
    expect(find.text(monthShort(twoBack.month)), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('flexible spending this month compares with the same days of last month', (tester) async {
    await pumpFei(
      tester,
      seed: (db) async {
        await addTxn(db, category: 'Grocery', cents: 7500, date: firstOf(thisMonth));
        await addTxn(db, category: 'Grocery', cents: 2500, date: firstOf(lastMonth));
      },
    );
    // Through today's day number, capped at the length of last month.
    final lastLen = daysInMonth(lastMonth.year, lastMonth.month);
    final day = min(now.day, lastLen);
    final last = monthShort(lastMonth.month);
    final comparedTo = day < lastLen ? '$last 1–$day' : last;
    expect(find.text('\$50.00 more than $comparedTo'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('upcoming recurring shows what is due in the next 14 days', (tester) async {
    await pumpFei(
      tester,
      seed: (db) async {
        await addSeries(
          db,
          category: 'Health',
          cents: 4500,
          start: todayYmd(),
          frequency: Frequency.weekly,
          merchant: 'Gym',
        );
        await db.materializeRecurring();
      },
    );
    await scrollTo(tester, find.text('Gym').first);
    expect(find.text(formatDateShort(addDays(now, 7))), findsOneWidget);
    await unmount(tester);
  });
}
