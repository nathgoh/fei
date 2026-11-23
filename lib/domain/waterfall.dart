import 'analytics.dart';

/// A bar's extent on the waterfall's shared axis, in cents.
typedef Span = ({int start, int end});

/// Income → expenses → savings, read top to bottom.
///
/// * **Income** is stacked by source, on an axis running from 0 to [total]
///   (income, or spending when it exceeds income).
/// * **Expenses** always fills its bar, stacked by category.
/// * **Savings** shares the income axis: what's left from the left, or, when
///   spending exceeds income, the overspend beyond the income bar (negative).
class CashFlowWaterfall {
  CashFlowWaterfall._({
    required this.total,
    required this.incomeCents,
    required this.expenseCents,
    required this.savingsCents,
    required this.sources,
    required this.categories,
    required this.income,
    required this.savings,
    required this.spentShare,
    required this.savingsRate,
  });

  factory CashFlowWaterfall.of(PeriodSummary s) {
    final income = s.incomeCents, expenses = s.expenseCents, savings = s.savingsCents;
    final total = income > expenses ? income : expenses;
    return CashFlowWaterfall._(
      total: total,
      incomeCents: income,
      expenseCents: expenses,
      savingsCents: savings,
      sources: s.incomeByCategory,
      categories: s.expenseByCategory,
      income: (start: 0, end: income),
      savings: savings >= 0 ? (start: 0, end: savings) : (start: income, end: expenses),
      spentShare: income > 0 ? expenses / income * 100 : null,
      savingsRate: s.savingsRate,
    );
  }

  final int total;
  final int incomeCents;
  final int expenseCents;

  /// Income minus expenses; negative when overspending.
  final int savingsCents;

  /// Income by source and expenses by category, largest first. Each
  /// [CategoryTotal.share] is a percentage of its own total.
  final List<CategoryTotal> sources;
  final List<CategoryTotal> categories;

  final Span income;
  final Span savings;

  /// Expenses as a percentage of income; null without income.
  final double? spentShare;

  /// Savings as a percentage of income (negative when overspending); null
  /// without income.
  final double? savingsRate;

  bool get isEmpty => incomeCents == 0 && expenseCents == 0;
  bool get hasIncome => incomeCents > 0;
  bool get hasExpenses => expenseCents > 0;
  bool get isDeficit => savingsCents < 0;
}
