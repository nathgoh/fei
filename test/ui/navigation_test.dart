import 'package:flutter_test/flutter_test.dart';

import '../support/app.dart';

void main() {
  testWidgets('a fresh install shows an empty state on every tab', (tester) async {
    await pumpFei(tester);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('No spending this month.'), findsOneWidget);
    expect(find.text('No flexible spending yet'), findsOneWidget);
    await scrollTo(tester, find.text('No transactions this month.'));

    await openTab(tester, 'Transactions');
    expect(find.textContaining('No transactions in'), findsOneWidget);

    await openTab(tester, 'Cash Flow');
    expect(find.text('No data for this year'), findsOneWidget);

    await openTab(tester, 'Recurring');
    expect(find.text('No recurring transactions'), findsOneWidget);

    await openTab(tester, 'Dashboard');
    expect(find.text('No spending this month.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('settings opens each sub-page', (tester) async {
    await pumpFei(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);

    for (final (tile, heading) in [
      ('Appearance', 'Preview'),
      ('Categories', 'Rent'),
      ('Import & export', 'Choose JSON files'),
    ]) {
      await tester.ensureVisible(find.text(tile));
      await tester.tap(find.text(tile));
      await settle(tester);
      expect(find.textContaining(heading), findsWidgets, reason: tile);
      await tester.pageBack();
      await settle(tester);
    }
    await unmount(tester);
  });
}
