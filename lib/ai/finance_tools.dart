import 'dart:convert';

import 'package:collection/collection.dart';

import '../core/dates.dart';
import '../data/database.dart';
import '../domain/analytics.dart';

/// A function the model can call. [parameters] is a JSON schema.
class AgentTool {
  AgentTool({required this.name, required this.description, required this.parameters, required this.run});
  final String name;
  final String description;
  final Map<String, Object?> parameters;
  final Future<Object?> Function(Map<String, Object?> args) run;

  Map<String, Object?> toOpenAi() => {
    'type': 'function',
    'function': {'name': name, 'description': description, 'parameters': parameters},
  };
}

class ToolError implements Exception {
  ToolError(this.message);
  final String message;
}

double _dollars(int cents) => cents / 100;
double _round1(double v) => (v * 10).roundToDouble() / 10;

/// Ports of the web app's agent tools, reading from the local database.
class FinanceTools {
  FinanceTools(this.db);
  final AppDatabase db;

  late Map<String, Category> _categories;
  late List<Txn> _all;

  Future<void> _load() async {
    _categories = {for (final c in await db.allCategories()) c.id: c};
    _all = await db.transactionsBetween();
  }

  Future<List<int>> years() async {
    final txns = await db.transactionsBetween();
    return txns.map((t) => int.parse(t.date.substring(0, 4))).toSet().sorted((a, b) => a - b);
  }

  Future<List<String>> expenseCategoryNames() async =>
      (await db.allCategories()).where((c) => c.kind == TxKind.expense).map((c) => c.name).toList();

  // ---------------------------------------------------------------------------

  static int resolveMonth(Object? input) {
    var s = input?.toString().trim() ?? '';
    // Models often send "2024-10" or "2024-10-15" instead of a month.
    final m = RegExp(r'^\d{4}-(\d{1,2})(?:-\d{1,2})?$').firstMatch(s);
    if (m != null) s = m[1]!;
    final n = int.tryParse(s);
    if (n != null) {
      if (n >= 1 && n <= 12) return n;
      throw ToolError('Month number must be 1-12, got $n.');
    }
    if (s.isNotEmpty) {
      final i = monthNames.indexWhere((name) => name.toLowerCase().startsWith(s.toLowerCase()));
      if (i >= 0) return i + 1;
    }
    throw ToolError("Could not resolve month '$input'. Use a name (January, jan) or number (1-12).");
  }

  Category _resolveCategory(Object? input, {TxKind kind = TxKind.expense}) {
    final wanted = input?.toString().trim().toLowerCase() ?? '';
    final pool = _categories.values.where((c) => c.kind == kind).toList();
    var match =
        pool.firstWhereOrNull((c) => c.name.toLowerCase() == wanted) ??
        pool.firstWhereOrNull((c) => wanted.isNotEmpty && c.name.toLowerCase().startsWith(wanted));
    if (match == null && wanted.isNotEmpty) {
      // Closest name by edit distance, like the web app's difflib cutoff of 0.6
      // ("groceries" → "Grocery").
      final best = pool
          .map((c) => (c, _similarity(wanted, c.name.toLowerCase())))
          .sortedBy<num>((e) => -e.$2)
          .firstOrNull;
      if (best != null && best.$2 >= 0.6) match = best.$1;
    }
    if (match == null) {
      throw ToolError("Unknown category '$input'. Valid categories: ${pool.map((c) => c.name).join(', ')}.");
    }
    return match;
  }

  static int _int(Object? v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  ({List<Txn> txns, String label}) _period(int year, Object? month) {
    final hasMonth = month != null && month.toString().trim().isNotEmpty && month.toString() != '0';
    if (!hasMonth) {
      return (txns: _all.where((t) => t.date.startsWith('$year-')).toList(), label: '$year');
    }
    final m = resolveMonth(month);
    final prefix = monthKey(year, m);
    return (txns: _all.where((t) => t.date.startsWith(prefix)).toList(), label: '${monthName(m)} $year');
  }

  String _label(Txn t) => t.merchant ?? t.notes ?? _categories[t.categoryId]?.name ?? '';

  // ---------------------------------------------------------------------------

  late final List<AgentTool> tools = [
    AgentTool(
      name: 'get_financial_summary',
      description:
          'Overview of income, expenses, savings, savings rate, and spending by '
          'category for a year or a single month.',
      parameters: _schema(
        {
          'year': _p('integer', 'The year to query (e.g. 2025).'),
          'month': _p(
            'string',
            'A month name or number 1-12 (e.g. "March" or "3"), never a date. Omit for the whole year.',
          ),
        },
        ['year'],
      ),
      run: (a) async {
        await _load();
        final p = _period(_int(a['year']), a['month']);
        if (p.txns.isEmpty) return {'error': 'No income or expenses found for ${p.label}.'};
        final s = summarize(p.txns, _categories);
        return {
          'period': p.label,
          'total_income': _dollars(s.incomeCents),
          'total_expenses': _dollars(s.expenseCents),
          'fixed_expenses': _dollars(s.fixedCents),
          'flexible_expenses': _dollars(s.flexibleCents),
          'transaction_count': s.transactionCount,
          'savings': _dollars(s.savingsCents),
          'savings_rate': _round1(s.savingsRate ?? 0),
          'expense_breakdown': {
            for (final c in s.expenseByCategory)
              c.category.name: {'amount': _dollars(c.cents), 'percentage': _round1(c.share)},
          },
        };
      },
    ),
    AgentTool(
      name: 'get_category_expenses',
      description: 'Total and month-by-month spending for one expense category.',
      parameters: _schema(
        {
          'category': _p('string', 'The category name (e.g. "Grocery").'),
          'year': _p('integer', 'Year to filter by (e.g. 2025). Use 0 for all years.'),
        },
        ['category'],
      ),
      run: (a) async {
        await _load();
        final category = _resolveCategory(a['category']);
        final year = _int(a['year']);
        final txns = _all
            .where((t) => t.categoryId == category.id && t.kind == TxKind.expense)
            .where((t) => year == 0 || t.date.startsWith('$year-'))
            .toList();
        if (txns.isEmpty) {
          return {'error': "No expenses found for '${category.name}'${year == 0 ? '' : ' in $year'}."};
        }
        final byMonth = groupBy(txns, (Txn t) => t.date.substring(0, 7));
        final keys = byMonth.keys.sorted();
        return {
          'category': category.name,
          'year': year == 0 ? 'all' : year,
          'total': _dollars(txns.map((t) => t.amountCents).sum),
          'transaction_count': txns.length,
          'by_month': [
            for (final k in keys)
              {
                'month': formatMonthYear(int.parse(k.substring(0, 4)), int.parse(k.substring(5))),
                'amount': _dollars(byMonth[k]!.map((t) => t.amountCents).sum),
              },
          ],
        };
      },
    ),
    AgentTool(
      name: 'get_top_expenses',
      description: 'The largest individual expenses (single purchases) in a year or month.',
      parameters: _schema(
        {
          'year': _p('integer', 'The year to query (e.g. 2025).'),
          'month': _p('string', 'A month name or number 1-12, never a date. Omit for the whole year.'),
          'limit': _p('integer', 'How many expenses to return (default 5).'),
        },
        ['year'],
      ),
      run: (a) async {
        await _load();
        final p = _period(_int(a['year']), a['month']);
        final expenses = p.txns.where((t) => t.kind == TxKind.expense).toList()
          ..sort((x, y) => y.amountCents.compareTo(x.amountCents));
        if (expenses.isEmpty) return {'error': 'No expenses found for ${p.label}.'};
        return {
          'period': p.label,
          'expenses': [
            for (final t in expenses.take(_int(a['limit'], fallback: 5).clamp(1, 50)))
              {
                'amount': _dollars(t.amountCents),
                'category': _categories[t.categoryId]?.name,
                'date': t.date,
                if (_label(t).isNotEmpty) 'description': _label(t),
              },
          ],
        };
      },
    ),
    AgentTool(
      name: 'get_recurring_expenses',
      description: 'Recurring expenses and subscriptions, with frequency, total, and date range.',
      parameters: _schema({'year': _p('integer', 'Year to filter by (e.g. 2025). Use 0 for all years.')}, []),
      run: (a) async {
        await _load();
        final year = _int(a['year']);
        final series = await db.allRecurring();
        final result = <Map<String, Object?>>[];
        for (final s in series.where((s) => s.kind == TxKind.expense)) {
          final occ = _all
              .where((t) => t.recurringId == s.id)
              .where((t) => year == 0 || t.date.startsWith('$year-'))
              .sortedBy((t) => t.date);
          if (occ.isEmpty && year != 0) continue;
          result.add({
            'label': s.merchant ?? s.notes ?? _categories[s.categoryId]?.name,
            'category': _categories[s.categoryId]?.name,
            'frequency': frequencyLabel(s.frequency),
            'amount': _dollars(s.amountCents),
            'monthly_equivalent': _dollars(monthlyEquivalent(s)),
            'active': isSeriesActive(s),
            'occurrences': occ.length,
            'total': _dollars(occ.map((t) => t.amountCents).sum),
            if (occ.isNotEmpty) 'first_date': occ.first.date,
            if (occ.isNotEmpty) 'last_date': occ.last.date,
            if (nextOccurrence(s) != null) 'next_date': ymd(nextOccurrence(s)!),
          });
        }
        if (result.isEmpty) return {'error': 'No recurring expenses found${year == 0 ? '' : ' in $year'}.'};
        return {'year': year == 0 ? 'all' : year, 'recurring_expenses': result};
      },
    ),
    AgentTool(
      name: 'get_income_sources',
      description: 'Total income and a breakdown by income category/source for a year or a single month.',
      parameters: _schema(
        {
          'year': _p('integer', 'The year to query (e.g. 2025).'),
          'month': _p('string', 'A month name or number 1-12, never a date. Omit for the whole year.'),
        },
        ['year'],
      ),
      run: (a) async {
        await _load();
        final p = _period(_int(a['year']), a['month']);
        final s = summarize(p.txns, _categories);
        if (s.incomeCents == 0) return {'error': 'No income found for ${p.label}.'};
        return {
          'period': p.label,
          'total': _dollars(s.incomeCents),
          'sources': [
            for (final c in s.incomeByCategory)
              {'source': c.category.name, 'total': _dollars(c.cents), 'count': c.count},
          ],
        };
      },
    ),
    AgentTool(
      name: 'compare_months',
      description: 'Compare income, expenses, savings, and per-category spending between two months of the same year.',
      parameters: _schema(
        {
          'year': _p('integer', 'The year (e.g. 2025).'),
          'month_1': _p('string', 'First month (e.g. "January", "jan", or "1").'),
          'month_2': _p('string', 'Second month (e.g. "February", "feb", or "2").'),
        },
        ['year', 'month_1', 'month_2'],
      ),
      run: (a) async {
        await _load();
        final year = _int(a['year']);
        final m1 = resolveMonth(a['month_1']), m2 = resolveMonth(a['month_2']);
        final n1 = monthName(m1), n2 = monthName(m2);
        final s1 = summarize(_period(year, m1).txns, _categories);
        final s2 = summarize(_period(year, m2).txns, _categories);
        Map<String, Object?> cmp(int x, int y) => {n1: _dollars(x), n2: _dollars(y), 'delta': _dollars(y - x)};
        final cats = {for (final c in s1.expenseByCategory) c.category.name: c.cents};
        final cats2 = {for (final c in s2.expenseByCategory) c.category.name: c.cents};
        return {
          'year': year,
          'income': cmp(s1.incomeCents, s2.incomeCents),
          'expenses': cmp(s1.expenseCents, s2.expenseCents),
          'savings': cmp(s1.savingsCents, s2.savingsCents),
          'category_breakdown': {
            for (final name in {...cats.keys, ...cats2.keys}.sorted()) name: cmp(cats[name] ?? 0, cats2[name] ?? 0),
          },
        };
      },
    ),
    AgentTool(
      name: 'get_spending_trend',
      description:
          'Month-by-month spending for a year with month-over-month change, plus the '
          'total and average monthly spending.',
      parameters: _schema(
        {
          'year': _p('integer', 'The year to query (e.g. 2025).'),
          'category': _p('string', 'Category to filter by (e.g. "Grocery"). Omit for all spending.'),
        },
        ['year'],
      ),
      run: (a) async {
        await _load();
        final year = _int(a['year']);
        final catArg = a['category']?.toString().trim() ?? '';
        final category = catArg.isEmpty ? null : _resolveCategory(catArg);
        final txns = _all
            .where((t) => t.kind == TxKind.expense && t.date.startsWith('$year-'))
            .where((t) => category == null || t.categoryId == category.id)
            .toList();
        if (txns.isEmpty) {
          return {'error': 'No expenses found${category == null ? '' : " for '${category.name}'"} in $year.'};
        }
        final byMonth = groupBy(txns, (Txn t) => int.parse(t.date.substring(5, 7)));
        final months = <Map<String, Object?>>[];
        int? prev;
        for (final m in byMonth.keys.sorted((a, b) => a - b)) {
          final amount = byMonth[m]!.map((t) => t.amountCents).sum;
          months.add({
            'month': monthName(m),
            'amount': _dollars(amount),
            if (prev != null && prev != 0) 'mom_change_percent': _round1((amount - prev) / prev * 100),
          });
          prev = amount;
        }
        final total = txns.map((t) => t.amountCents).sum;
        return {
          'year': year,
          'category': category?.name ?? 'all',
          'months': months,
          'total': _dollars(total),
          'average_per_month': _dollars((total / byMonth.length).round()),
        };
      },
    ),
  ];

  /// Runs a tool by name, always returning a JSON string (errors included) so
  /// the model can recover.
  Future<String> call(String name, Map<String, Object?> args) async {
    final tool = tools.firstWhereOrNull((t) => t.name == name);
    if (tool == null) return jsonEncode({'error': 'Unknown tool "$name".'});
    try {
      return jsonEncode(await tool.run(args));
    } on ToolError catch (e) {
      return jsonEncode({'error': e.message});
    } catch (e) {
      return jsonEncode({'error': 'Tool failed: $e'});
    }
  }
}

/// 1.0 for identical strings, falling towards 0 as the edit distance grows.
double _similarity(String a, String b) {
  if (a == b) return 1;
  final longest = a.length > b.length ? a.length : b.length;
  if (longest == 0) return 1;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return 1 - previous[b.length] / longest;
}

Map<String, Object?> _p(String type, String description) => {'type': type, 'description': description};

Map<String, Object?> _schema(Map<String, Object?> props, List<String> required) => {
  'type': 'object',
  'properties': props,
  'required': required,
};
