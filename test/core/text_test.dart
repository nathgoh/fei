import 'package:fei/core/text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeMerchant trims and collapses spaces, keeping the casing as typed', () {
    expect(normalizeMerchant('costco'), 'costco');
    expect(normalizeMerchant('COSTCO  '), 'COSTCO');
    expect(normalizeMerchant("  trader   JOE'S "), "trader JOE'S");
    expect(normalizeMerchant('blue\tbottle'), 'blue bottle');
    expect(normalizeMerchant('  PG&E '), 'PG&E');
    expect(normalizeMerchant('IKEA'), 'IKEA');
    expect(normalizeMerchant("McDonald's"), "McDonald's");
    expect(normalizeMerchant(' eBay'), 'eBay');
    expect(normalizeMerchant('élan  café'), 'élan café');
    expect(normalizeMerchant('   '), '');
  });

  test('merchantKey ignores case and spacing, including letters outside ASCII', () {
    expect(merchantKey('  PG&E '), merchantKey('pg&e'));
    expect(merchantKey('Trader  Joe\'s'), merchantKey("TRADER JOE'S"));
    expect(merchantKey('ÉLAN Café'), merchantKey('élan café'));
    expect(merchantKey('eBay'), isNot(merchantKey('e Bay')));
  });
}
