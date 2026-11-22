import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../domain/analytics.dart';
import '../theme.dart';

/// Rounds an axis maximum up to a "nice" number.
double niceMax(double value) {
  if (value <= 0) return 10000; // empty chart: $0–$100 axis
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 2.5, 5, 10]) {
    if (value <= m * magnitude) return m * magnitude;
  }
  return 10 * magnitude;
}

FlTitlesData _titles(BuildContext context, {required Widget Function(double) bottom, required double interval}) {
  final style = context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant);
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 48,
        interval: interval,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          child: Text(formatCompact(v), style: style),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: 1,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          child: DefaultTextStyle.merge(style: style, child: bottom(v)),
        ),
      ),
    ),
  );
}

FlGridData _grid(BuildContext context, double interval) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (_) => FlLine(color: context.colors.outlineVariant.withValues(alpha: 0.3), strokeWidth: 1),
);

/// Monarch-style cumulative spending: the selected month vs. the one before.
class SpendingComparisonChart extends StatelessWidget {
  const SpendingComparisonChart({
    super.key,
    required this.current,
    required this.previous,
    required this.throughDay,
    required this.currentLabel,
    required this.previousLabel,
  });

  /// Cumulative cents per day.
  final List<int> current;
  final List<int> previous;

  /// Last day of [current] to draw (today for the current month).
  final int throughDay;

  /// Short month names for the tooltips, e.g. "Nov" and "Oct".
  final String currentLabel;
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final maxY = niceMax([...current.take(throughDay), ...previous].fold<int>(0, math.max).toDouble());
    final interval = maxY / 4;
    final days = math.max(current.length, previous.length);
    List<FlSpot> spots(List<int> values, int count) => [
      for (var i = 0; i < count; i++) FlSpot(i + 1.0, values[i].toDouble()),
    ];

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 1,
          maxX: days.toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: _grid(context, interval),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            context,
            interval: interval,
            bottom: (v) {
              final d = v.toInt();
              return d == 1 || d % 7 == 0 ? Text('$d') : const SizedBox.shrink();
            },
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => context.colors.surfaceContainerHighest,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${s.barIndex == 0 ? previousLabel : currentLabel} ${s.x.toInt()}\n${formatMoney(s.y.round())}',
                    context.text.labelSmall!.copyWith(color: s.bar.color),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots(previous, previous.length),
              color: context.colors.outline,
              barWidth: 2,
              dashArray: [4, 4],
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: spots(current, math.min(throughDay, current.length)),
              color: context.colors.primary,
              barWidth: 3,
              isCurved: true,
              preventCurveOverShooting: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: context.colors.primary.withValues(alpha: 0.15)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Income vs. expenses for each month of a year.
class MonthlyCashFlowChart extends StatelessWidget {
  const MonthlyCashFlowChart({super.key, required this.months, this.onMonthTap});
  final List<MonthTotals> months;
  final ValueChanged<int>? onMonthTap;

  @override
  Widget build(BuildContext context) {
    final maxY = niceMax(months.map((m) => math.max(m.incomeCents, m.expenseCents)).fold<int>(0, math.max).toDouble());
    final interval = maxY / 4;
    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: _grid(context, interval),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context, interval: interval, bottom: (v) => Text(monthShort(v.toInt() + 1)[0])),
          barTouchData: BarTouchData(
            touchCallback: (event, response) {
              final group = response?.spot?.touchedBarGroupIndex;
              if (event is FlTapUpEvent && group != null) onMonthTap?.call(group + 1);
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => context.colors.surfaceContainerHighest,
              getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                '${monthShort(group.x + 1)} ${rodIndex == 0 ? 'income' : 'expenses'}\n${formatMoney(rod.toY.round())}',
                context.text.labelSmall!.copyWith(color: rod.color),
              ),
            ),
          ),
          barGroups: [
            for (final m in months)
              BarChartGroupData(
                x: m.month - 1,
                barsSpace: 2,
                barRods: [
                  BarChartRodData(
                    toY: m.incomeCents.toDouble(),
                    color: incomeGreen,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                  BarChartRodData(
                    toY: m.expenseCents.toDouble(),
                    color: expenseOrange,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Spending in one category, month by month.
class CategoryTrendChart extends StatelessWidget {
  const CategoryTrendChart({super.key, required this.monthlyCents, required this.color, this.average});
  final List<int> monthlyCents; // 12 entries
  final Color color;
  final int? average;

  @override
  Widget build(BuildContext context) {
    final maxY = niceMax(monthlyCents.fold<int>(0, math.max).toDouble());
    final interval = maxY / 4;
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          gridData: _grid(context, interval),
          borderData: FlBorderData(show: false),
          titlesData: _titles(context, interval: interval, bottom: (v) => Text(monthShort(v.toInt() + 1)[0])),
          extraLinesData: average == null
              ? null
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: average!.toDouble(),
                      color: context.colors.onSurfaceVariant,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ],
                ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => context.colors.surfaceContainerHighest,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${monthShort(group.x + 1)}\n${formatMoney(rod.toY.round())}',
                context.text.labelSmall!,
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < 12; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: monthlyCents[i].toDouble(),
                    color: color,
                    width: 12,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class ChartLegend extends StatelessWidget {
  const ChartLegend(this.entries, {super.key});
  final Map<String, Color> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final e in entries.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: e.value, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
              Text(e.key, style: context.text.labelSmall),
            ],
          ),
      ],
    );
  }
}
