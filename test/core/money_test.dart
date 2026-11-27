import 'package:fei/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseCents handles user and bank formats', () {
    expect(parseCents('12'), 1200);
    expect(parseCents(' 12.5 '), 1250);
    expect(parseCents(r'$1,234.56'), 123456);
    expect(parseCents('+7'), 700);
    expect(parseCents('-3.2'), -320);
    expect(parseCents('(4.00)'), -400);
    expect(parseCents(r'-$4.00'), -400);
    expect(parseCents('0.1'), 10);
    expect(parseCents('19.99'), 1999, reason: 'no float drift');
  });

  test('parseCents rejects non-numbers', () {
    expect(parseCents(''), isNull);
    expect(parseCents('   '), isNull);
    expect(parseCents('abc'), isNull);
    expect(parseCents(r'$'), isNull);
  });

  test('centsFromNum rounds to the nearest cent', () {
    expect(centsFromNum(45.5), 4550);
    expect(centsFromNum(0.29), 29);
    expect(centsFromNum(1800), 180000);
  });

  test('formatMoney', () {
    expect(formatMoney(0), r'$0.00');
    expect(formatMoney(123456), r'$1,234.56');
    expect(formatMoney(-500), r'-$5.00');
  });

  test('formatCompact for chart axes', () {
    expect(formatCompact(150000), r'$1.5K');
    expect(formatCompact(250000000), r'$2.5M');
    expect(formatCompact(5000), r'$50.00', reason: 'below \$1K keeps the cents');
  });

  test('formatPercent', () {
    expect(formatPercent(45), '45.0%');
    expect(formatPercent(12.345, digits: 2), '12.35%');
    expect(formatPercent(-3.2), '-3.2%');
  });
}
