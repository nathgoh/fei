import 'package:fei/core/text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeMerchant trims, collapses spaces and capitalises each word', () {
    expect(normalizeMerchant('costco'), 'Costco');
    expect(normalizeMerchant('COSTCO  '), 'Costco');
    expect(normalizeMerchant("  trader   JOE'S "), "Trader Joe's");
    expect(normalizeMerchant('blue\tbottle'), 'Blue Bottle');
    expect(normalizeMerchant('élan café'), 'Élan Café');
    expect(normalizeMerchant('   '), '');
  });
}
