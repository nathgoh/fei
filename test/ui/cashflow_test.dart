import 'package:fei/core/dates.dart';
import 'package:fei/ui/charts/sankey_chart.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';
import '../support/db.dart';

void main() {
  final now = today();
  final firstOfMonth = ymd(DateTime(now.year, now.month, 1));

  testWidgets('shows the year totals, flow chart and breakdowns without overflowing', (tester) async {
    await pumpFei(
      tester,
      seed: (db) async {
        await addTxn(db, category: 'Paycheck', cents: 400000, date: firstOfMonth);
        await addTxn(db, category: 'Interest', cents: 5000, date: firstOfMonth);
        await addTxn(db, category: 'Rent', cents: 200000, date: firstOfMonth);
        await addTxn(db, category: 'Grocery', cents: 45000, date: firstOfMonth);
        await addTxn(db, category: 'Travel', cents: 30000, date: '${now.year - 1}-06-01'); // another year
      },
    );
    await openTab(tester, 'Cash Flow');

    expect(find.text('${now.year}'), findsWidgets);
    expect(find.text(r'$4,050.00'), findsWidgets); // total income
    expect(find.text(r'$2,450.00'), findsWidgets); // total expenses
    expect(find.text(r'$1,600.00'), findsWidgets); // total savings
    expect(find.text('39.5%'), findsOneWidget); // saved
    expect(find.byType(SankeyChart), findsOneWidget);

    await scrollTo(tester, find.text('Spending by category'));
    expect(find.text('Grocery'), findsWidgets);
    expect(find.text('Travel'), findsNothing);

    await scrollTo(tester, find.text('Monthly breakdown'));
    await unmount(tester);
  });

  testWidgets('the year switcher shows other years', (tester) async {
    await pumpFei(
      tester,
      seed: (db) => addTxn(db, category: 'Travel', cents: 30000, date: '${now.year - 1}-06-01'),
    );
    await openTab(tester, 'Cash Flow');
    expect(find.text('No data for this year'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous').last);
    await settle(tester);
    expect(find.text('${now.year - 1}'), findsWidgets);
    expect(find.text(r'$300.00'), findsWidgets);
    await unmount(tester);
  });
}
