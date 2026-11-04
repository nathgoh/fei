import 'package:intl/intl.dart';

import '../data/tables.dart';

/// Formats a calendar date as `YYYY-MM-DD`.
String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// Parses `YYYY-MM-DD` (anything after the date is ignored) as a local date.
DateTime parseYmd(String s) {
  final parts = s.substring(0, 10).split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String todayYmd() => ymd(today());

/// `YYYY-MM` prefix for a month, used for lexical range filtering.
String monthKey(int year, int month) => '$year-${_two(month)}';

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

String monthName(int month) => monthNames[month - 1];
String monthShort(int month) => monthNames[month - 1].substring(0, 3);

String formatDateLong(DateTime d) => DateFormat('EEEE, MMMM d').format(d);
String formatDateShort(DateTime d) => DateFormat('MMM d, y').format(d);
String formatMonthYear(int year, int month) => DateFormat('MMMM y').format(DateTime(year, month));

/// The [n]th occurrence (0-based) of a schedule starting on [start].
///
/// Always computed from the start date so month-end dates don't drift
/// (Jan 31 → Feb 28 → Mar 31, not Mar 28).
DateTime nthOccurrence(DateTime start, Frequency f, int n) {
  switch (f) {
    case Frequency.weekly:
      return DateTime(start.year, start.month, start.day + 7 * n);
    case Frequency.biweekly:
      return DateTime(start.year, start.month, start.day + 14 * n);
    case Frequency.monthly:
      return _addMonthsClamped(start, n);
    case Frequency.quarterly:
      return _addMonthsClamped(start, 3 * n);
    case Frequency.yearly:
      return _addMonthsClamped(start, 12 * n);
  }
}

DateTime _addMonthsClamped(DateTime start, int months) {
  final total = start.month - 1 + months;
  final year = start.year + total ~/ 12;
  final month = total % 12 + 1;
  final day = start.day.clamp(1, daysInMonth(year, month));
  return DateTime(year, month, day);
}

/// All occurrence dates of a schedule within `[from, to]` (inclusive).
List<DateTime> occurrencesBetween(DateTime start, Frequency f, DateTime from, DateTime to, {DateTime? end}) {
  final last = end != null && end.isBefore(to) ? end : to;
  final result = <DateTime>[];
  for (var n = 0; ; n++) {
    final d = nthOccurrence(start, f, n);
    if (d.isAfter(last)) break;
    if (!d.isBefore(from)) result.add(d);
    if (n > 100000) break; // defensive: malformed schedule
  }
  return result;
}

/// Approximate occurrences per month, for "monthly cost" estimates.
double perMonth(Frequency f) => switch (f) {
  Frequency.weekly => 52 / 12,
  Frequency.biweekly => 26 / 12,
  Frequency.monthly => 1,
  Frequency.quarterly => 1 / 3,
  Frequency.yearly => 1 / 12,
};

String frequencyLabel(Frequency f) => switch (f) {
  Frequency.weekly => 'Weekly',
  Frequency.biweekly => 'Every 2 weeks',
  Frequency.monthly => 'Monthly',
  Frequency.quarterly => 'Quarterly',
  Frequency.yearly => 'Yearly',
};
