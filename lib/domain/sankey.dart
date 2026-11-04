import 'dart:ui';

import 'analytics.dart';

class SankeyNode {
  SankeyNode(this.id, this.label, this.value, this.color, this.column, {this.share});
  final String id;
  final String label;
  final int value;
  final Color color;
  final int column;

  /// Optional percentage shown next to the amount.
  final double? share;
}

class SankeyLink {
  SankeyLink(this.from, this.to, this.value, this.color);
  final String from;
  final String to;
  final int value;
  final Color color;
}

class SankeyData {
  SankeyData(this.nodes, this.links);
  final List<SankeyNode> nodes;
  final List<SankeyLink> links;
  int get columns => nodes.isEmpty ? 0 : nodes.map((n) => n.column).reduce((a, b) => a > b ? a : b) + 1;
}

const incomeColor = Color(0xFF2E7D32);
const totalIncomeColor = Color(0xFF1B5E20);
const expensesColor = Color(0xFF808080);
const savingsColor = Color(0xFF1976D2);
const deficitColor = Color(0xFFC62828);

/// Income categories → Total income → Expenses / Savings → Expense categories,
/// as in the web app's "Financial Flow" chart.
///
/// With a single income category, or [collapseSources] (narrow screens), the
/// per-source column is skipped. When spending exceeds income, a
/// "From savings" node feeds the shortfall.
SankeyData buildCashFlowSankey(PeriodSummary s, {bool collapseSources = false}) {
  final nodes = <SankeyNode>[];
  final links = <SankeyLink>[];
  if (s.expenseCents == 0 && s.incomeCents == 0) return SankeyData(nodes, links);

  final hasIncome = s.incomeCents > 0;
  final multiSource = s.incomeByCategory.length > 1 && !collapseSources;
  // Columns: [sources] → [total] → expenses/savings → categories
  final totalCol = hasIncome && multiSource ? 1 : 0;
  final expensesCol = hasIncome ? totalCol + 1 : 0;
  final categoryCol = expensesCol + 1;

  String totalId = 'income';
  if (hasIncome) {
    if (multiSource) {
      for (final c in s.incomeByCategory) {
        nodes.add(SankeyNode('in:${c.category.id}', c.category.name, c.cents, incomeColor, 0));
        links.add(SankeyLink('in:${c.category.id}', totalId, c.cents, incomeColor));
      }
      nodes.add(SankeyNode(totalId, 'Total income', s.incomeCents, totalIncomeColor, totalCol));
    } else {
      final label = s.incomeByCategory.length == 1 ? s.incomeByCategory.single.category.name : 'Income';
      nodes.add(SankeyNode(totalId, label, s.incomeCents, totalIncomeColor, totalCol));
    }
  }

  if (s.expenseCents > 0) {
    nodes.add(SankeyNode('expenses', 'Expenses', s.expenseCents, expensesColor, expensesCol));
    if (hasIncome) {
      final covered = s.expenseCents < s.incomeCents ? s.expenseCents : s.incomeCents;
      links.add(SankeyLink(totalId, 'expenses', covered, expensesColor));
    }
  }
  if (hasIncome && s.savingsCents > 0) {
    nodes.add(SankeyNode('savings', 'Savings', s.savingsCents, savingsColor, expensesCol, share: s.savingsRate));
    links.add(SankeyLink(totalId, 'savings', s.savingsCents, savingsColor));
  }
  if (hasIncome && s.savingsCents < 0) {
    // Spending beyond income is drawn as coming from savings.
    nodes.add(SankeyNode('deficit', 'From savings', -s.savingsCents, deficitColor, totalCol));
    links.add(SankeyLink('deficit', 'expenses', -s.savingsCents, deficitColor));
  }

  for (final c in s.expenseByCategory) {
    final color = Color(c.category.color);
    nodes.add(SankeyNode('cat:${c.category.id}', c.category.name, c.cents, color, categoryCol, share: c.share));
    links.add(SankeyLink('expenses', 'cat:${c.category.id}', c.cents, color));
  }
  return SankeyData(nodes, links);
}
