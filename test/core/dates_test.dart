import 'package:fei/core/dates.dart';
import 'package:fei/data/tables.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ymd / parseYmd', () {
    test('round-trip and zero-pad', () {
      expect(ymd(DateTime(2026, 3, 7)), '2026-03-07');
      expect(parseYmd('2026-03-07'), DateTime(2026, 3, 7));
    });

    test('parseYmd ignores anything after the date', () {
      expect(parseYmd('2026-03-07T12:34:56Z'), DateTime(2026, 3, 7));
    });

    test('todayYmd is today with no time part', () {
      final now = DateTime.now();
      expect(todayYmd(), ymd(now));
      expect(today(), DateTime(now.year, now.month, now.day));
    });
  });

  group('months', () {
    test('monthKey is a sortable YYYY-MM prefix', () {
      expect(monthKey(2026, 3), '2026-03');
      expect('2026-03-31'.startsWith(monthKey(2026, 3)), isTrue);
    });

    test('daysInMonth handles leap years', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 12), 31);
      expect(daysInMonth(2026, 4), 30);
    });

    test('names and abbreviations', () {
      expect(monthName(1), 'January');
      expect(monthShort(9), 'Sep');
      expect(formatMonthYear(2026, 11), 'November 2026');
      expect(formatDateShort(DateTime(2026, 11, 8)), 'Nov 8, 2026');
      expect(formatDateLong(DateTime(2026, 11, 8)), 'Sunday, November 8');
    });
  });

  group('nthOccurrence', () {
    test('monthly clamps month-end without drifting', () {
      final start = DateTime(2026, 1, 31);
      expect(
        [for (var n = 0; n < 4; n++) ymd(nthOccurrence(start, Frequency.monthly, n))],
        ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'],
      );
    });

    test('weekly, biweekly, quarterly and yearly (from a leap day)', () {
      final start = DateTime(2024, 2, 29);
      expect(ymd(nthOccurrence(start, Frequency.weekly, 1)), '2024-03-07');
      expect(ymd(nthOccurrence(start, Frequency.biweekly, 2)), '2024-03-28');
      expect(ymd(nthOccurrence(start, Frequency.quarterly, 1)), '2024-05-29');
      expect(ymd(nthOccurrence(start, Frequency.yearly, 1)), '2025-02-28');
      expect(ymd(nthOccurrence(start, Frequency.yearly, 4)), '2028-02-29');
    });

    test('crosses year boundaries', () {
      expect(ymd(nthOccurrence(DateTime(2026, 11, 15), Frequency.monthly, 3)), '2027-02-15');
      expect(ymd(nthOccurrence(DateTime(2026, 12, 28), Frequency.weekly, 1)), '2027-01-04');
    });
  });

  group('occurrencesBetween', () {
    test('respects the range and the end date', () {
      final dates = occurrencesBetween(
        DateTime(2026, 1, 15),
        Frequency.monthly,
        DateTime(2026, 2, 1),
        DateTime(2026, 12, 31),
        end: DateTime(2026, 5, 15),
      );
      expect(dates.map(ymd), ['2026-02-15', '2026-03-15', '2026-04-15', '2026-05-15']);
    });

    test('range bounds are inclusive', () {
      final dates = occurrencesBetween(
        DateTime(2026, 1, 1),
        Frequency.weekly,
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 15),
      );
      expect(dates.map(ymd), ['2026-01-08', '2026-01-15']);
    });

    test('empty when the series ends before the range', () {
      final dates = occurrencesBetween(
        DateTime(2026, 1, 1),
        Frequency.monthly,
        DateTime(2026, 6, 1),
        DateTime(2026, 12, 31),
        end: DateTime(2026, 3, 1),
      );
      expect(dates, isEmpty);
    });
  });

  test('perMonth and frequencyLabel cover every frequency', () {
    expect(perMonth(Frequency.weekly), closeTo(4.333, 0.001));
    expect(perMonth(Frequency.biweekly), closeTo(2.167, 0.001));
    expect(perMonth(Frequency.monthly), 1);
    expect(perMonth(Frequency.quarterly), closeTo(0.333, 0.001));
    expect(perMonth(Frequency.yearly), closeTo(0.083, 0.001));
    expect(Frequency.values.map(frequencyLabel), ['Weekly', 'Every 2 weeks', 'Monthly', 'Quarterly', 'Yearly']);
  });
}
