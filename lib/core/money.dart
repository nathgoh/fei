import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(locale: 'en_US', symbol: r'$');
final _compact = NumberFormat.compactCurrency(locale: 'en_US', symbol: r'$');

/// `$1,234.56`. Negative values render as `-$1,234.56`.
String formatMoney(int cents) => _currency.format(cents / 100);

/// `$1.2K` style, for chart axes.
String formatCompact(num cents) => _compact.format(cents / 100);

/// Parses user or CSV input like `1,234.50`, `$12`, `-3.2`, `(4.00)`.
/// Returns null if it isn't a number.
int? parseCents(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  s = s.replaceAll(RegExp(r'[\$,\s]'), '');
  if (s.startsWith('-')) {
    negative = !negative;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  final value = double.tryParse(s);
  if (value == null) return null;
  final cents = (value * 100).round();
  return negative ? -cents : cents;
}

/// Converts a JSON/CSV number (e.g. `12.5`) to cents without float drift.
int centsFromNum(num value) => (value * 100).round();

String formatPercent(double value, {int digits = 1}) => '${value.toStringAsFixed(digits)}%';
