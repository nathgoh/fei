import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../core/dates.dart';
import '../data/database.dart';

class CategoryTotal {
  CategoryTotal(this.category, this.cents, this.share, this.count);
  final Category category;
  final int cents;

  /// Share of the kind's total, 0–100.
  final double share;
  final int count;
}

class MonthTotals {
  MonthTotals(this.month);
  final int month;
  int incomeCents = 0;
  int expenseCents = 0;
  final Map<String, int> expenseByCategory = {};

  int get savingsCents => incomeCents - expenseCents;
  bool get hasData => incomeCents != 0 || expenseCents != 0;
}

/// Aggregates for a set of transactions (typically a year or a month).
class PeriodSummary {
  PeriodSummary._({
    required this.incomeCents,
    required this.expenseCents,
    required this.fixedCents,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.months,
    required this.transactionCount,
  });

  final int incomeCents;
  final int expenseCents;

  /// Spending in categories flagged "fixed" (e.g. Rent).
  final int fixedCents;
  final List<CategoryTotal> expenseByCategory;
  final List<CategoryTotal> incomeByCategory;

  /// Index 0 = January.
  final List<MonthTotals> months;
  final int transactionCount;

  int get flexibleCents => expenseCents - fixedCents;
  int get savingsCents => incomeCents - expenseCents;
  double? get savingsRate => incomeCents > 0 ? savingsCents / incomeCents * 100 : null;

  /// Expenses as a percentage of income; null without income.
  double? get spentShare => incomeCents > 0 ? expenseCents / incomeCents * 100 : null;
  bool get isEmpty => transactionCount == 0;

  /// The cash-flow chart's shared axis for income and savings, in cents:
  /// income, or spending when it exceeds income.
  int get flowTotal => math.max(incomeCents, expenseCents);

  /// Savings on that axis: what's left, from the left, or when spending
  /// exceeds income, the overspend beyond the income bar.
  ({int start, int end}) get savingsSpan =>
      savingsCents >= 0 ? (start: 0, end: savingsCents) : (start: incomeCents, end: expenseCents);

  List<MonthTotals> get activeMonths => months.where((m) => m.hasData).toList();

  /// Months from the first to the last month with any data, inclusive.
  /// Quiet months in between count, so averages aren't inflated.
  int get monthSpan {
    final active = activeMonths;
    if (active.isEmpty) return 0;
    return active.last.month - active.first.month + 1;
  }

  int get avgExpensePerMonth => monthSpan == 0 ? 0 : (expenseCents / monthSpan).round();
  int get avgFlexiblePerMonth => monthSpan == 0 ? 0 : (flexibleCents / monthSpan).round();

  int monthlyAverageFor(String categoryId) {
    if (monthSpan == 0) return 0;
    final total = expenseByCategory.firstWhereOrNull((c) => c.category.id == categoryId)?.cents ?? 0;
    return (total / monthSpan).round();
  }
}

PeriodSummary summarize(List<Txn> txns, Map<String, Category> categories) {
  var income = 0, expense = 0, fixed = 0;
  final expenseBy = <String, int>{};
  final expenseCount = <String, int>{};
  final incomeBy = <String, int>{};
  final incomeCount = <String, int>{};
  final months = List.generate(12, (i) => MonthTotals(i + 1));

  for (final t in txns) {
    final month = months[int.parse(t.date.substring(5, 7)) - 1];
    final category = categories[t.categoryId];
    if (t.kind == TxKind.income) {
      income += t.amountCents;
      month.incomeCents += t.amountCents;
      incomeBy.update(t.categoryId, (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
      incomeCount.update(t.categoryId, (v) => v + 1, ifAbsent: () => 1);
    } else {
      expense += t.amountCents;
      month.expenseCents += t.amountCents;
      month.expenseByCategory.update(t.categoryId, (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
      expenseBy.update(t.categoryId, (v) => v + t.amountCents, ifAbsent: () => t.amountCents);
      expenseCount.update(t.categoryId, (v) => v + 1, ifAbsent: () => 1);
      if (category?.isFixed ?? false) fixed += t.amountCents;
    }
  }

  List<CategoryTotal> totals(Map<String, int> by, Map<String, int> counts, int total) {
    return by.entries
        .where((e) => categories.containsKey(e.key))
        .map(
          (e) => CategoryTotal(categories[e.key]!, e.value, total == 0 ? 0 : e.value / total * 100, counts[e.key] ?? 0),
        )
        .sorted((a, b) => b.cents.compareTo(a.cents));
  }

  return PeriodSummary._(
    incomeCents: income,
    expenseCents: expense,
    fixedCents: fixed,
    expenseByCategory: totals(expenseBy, expenseCount, expense),
    incomeByCategory: totals(incomeBy, incomeCount, income),
    months: months,
    transactionCount: txns.length,
  );
}

/// Running total of flexible spending by day of month (index 0 = day 1).
/// Fixed costs are left out so a rent payment doesn't dominate.
List<int> cumulativeDailySpending(List<Txn> txns, Map<String, Category> categories, int year, int month) {
  final days = List.filled(daysInMonth(year, month), 0);
  final prefix = monthKey(year, month);
  for (final t in txns) {
    if (t.kind != TxKind.expense || !t.date.startsWith(prefix)) continue;
    if (categories[t.categoryId]?.isFixed ?? false) continue;
    days[int.parse(t.date.substring(8, 10)) - 1] += t.amountCents;
  }
  for (var i = 1; i < days.length; i++) {
    days[i] += days[i - 1];
  }
  return days;
}

// -----------------------------------------------------------------------------
// Recurring
// -----------------------------------------------------------------------------

class UpcomingOccurrence {
  UpcomingOccurrence(this.series, this.date);
  final RecurringSeries series;
  final DateTime date;
}

bool isSeriesActive(RecurringSeries s, [DateTime? asOf]) {
  if (s.endDate == null) return true;
  return !parseYmd(s.endDate!).isBefore(asOf ?? today());
}

/// Occurrences due after today, within [days] days.
List<UpcomingOccurrence> upcomingOccurrences(List<RecurringSeries> series, {int days = 30, DateTime? asOf}) {
  final from = addDays(asOf ?? today(), 1);
  final to = addDays(from, days - 1);
  final result = <UpcomingOccurrence>[];
  for (final s in series) {
    final end = s.endDate == null ? null : parseYmd(s.endDate!);
    for (final d in occurrencesBetween(parseYmd(s.startDate), s.frequency, from, to, end: end)) {
      result.add(UpcomingOccurrence(s, d));
    }
  }
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}

DateTime? nextOccurrence(RecurringSeries s, {DateTime? asOf}) {
  final from = addDays(asOf ?? today(), 1);
  final end = s.endDate == null ? null : parseYmd(s.endDate!);
  final start = parseYmd(s.startDate);
  for (var n = 0; n < 100000; n++) {
    final d = nthOccurrence(start, s.frequency, n);
    if (end != null && d.isAfter(end)) return null;
    if (!d.isBefore(from)) return d;
  }
  return null;
}

/// Estimated monthly cost (or income) of a series.
int monthlyEquivalent(RecurringSeries s) => (s.amountCents * perMonth(s.frequency)).round();
