import 'package:fei/core/dates.dart';
import 'package:fei/core/money.dart';
import 'package:fei/data/tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nthOccurrence', () {
    test('monthly clamps month-end without drifting', () {
      final start = DateTime(2026, 1, 31);
      expect(
        [for (var n = 0; n < 4; n++) ymd(nthOccurrence(start, Frequency.monthly, n))],
        ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'],
      );
    });

    test('weekly, biweekly, quarterly, yearly', () {
      final start = DateTime(2024, 2, 29);
      expect(ymd(nthOccurrence(start, Frequency.weekly, 1)), '2024-03-07');
      expect(ymd(nthOccurrence(start, Frequency.biweekly, 2)), '2024-03-28');
      expect(ymd(nthOccurrence(start, Frequency.quarterly, 1)), '2024-05-29');
      expect(ymd(nthOccurrence(start, Frequency.yearly, 1)), '2025-02-28');
      expect(ymd(nthOccurrence(start, Frequency.yearly, 4)), '2028-02-29');
    });
  });

  test('occurrencesBetween respects range and end date', () {
    final dates = occurrencesBetween(
      DateTime(2026, 1, 15),
      Frequency.monthly,
      DateTime(2026, 2, 1),
      DateTime(2026, 12, 31),
      end: DateTime(2026, 5, 15),
    );
    expect(dates.map(ymd), ['2026-02-15', '2026-03-15', '2026-04-15', '2026-05-15']);
  });

  test('parseCents handles common formats', () {
    expect(parseCents('12'), 1200);
    expect(parseCents(r'$1,234.56'), 123456);
    expect(parseCents('-3.2'), -320);
    expect(parseCents('(4.00)'), -400);
    expect(parseCents('0.1'), 10);
    expect(parseCents('abc'), isNull);
    expect(parseCents(''), isNull);
  });

  test('formatMoney', () {
    expect(formatMoney(123456), r'$1,234.56');
    expect(formatSigned(500), r'+$5.00');
    expect(formatSigned(-500), r'-$5.00');
  });
}
