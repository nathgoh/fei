import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/import_export.dart';
import '../../domain/analytics.dart';
import '../../state/providers.dart';
import '../charts/charts.dart';
import '../charts/sankey_chart.dart';
import '../theme.dart';
import '../transactions/transactions_screen.dart';
import '../widgets.dart';

class CashFlowYearNotifier extends Notifier<int> {
  @override
  int build() => DateTime.now().year;
  void set(int year) => state = year;
}

final cashFlowYearProvider = NotifierProvider<CashFlowYearNotifier, int>(CashFlowYearNotifier.new);

Future<void> exportCsvFile(BuildContext context, AppDatabase db, {int? year}) async {
  try {
    final csv = await exportCsv(db, year: year);
    final saved = await FilePicker.saveFile(
      fileName: year == null ? 'fei_transactions.csv' : 'fei_transactions_$year.csv',
      bytes: utf8.encode(csv),
      mimeType: 'text/csv',
    );
    if (context.mounted && saved != null) showMessage(context, 'Exported CSV');
  } catch (e) {
    if (context.mounted) showMessage(context, 'Export failed: $e');
  }
}

class CashFlowScreen extends ConsumerWidget {
  const CashFlowScreen({super.key});

  void _drillDown(BuildContext context, WidgetRef ref, int year, {int? month, String? categoryId}) {
    ref
        .read(transactionFilterProvider.notifier)
        .set(
          TransactionFilter(
            year: year,
            month: month,
            categoryId: categoryId,
            kind: categoryId == null ? null : TxKind.expense,
          ),
        );
    context.go('/transactions');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(cashFlowYearProvider);
    final years = ref.watch(yearsProvider).value ?? [year];
    final summaryAsync = ref.watch(yearSummaryProvider(year));
    final minYear = years.isEmpty ? year : years.last;
    final maxYear = years.isEmpty ? year : years.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Flow'),
        actions: [
          IconButton(
            tooltip: 'Export $year as CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => exportCsvFile(context, ref.read(databaseProvider), year: year),
          ),
          const SettingsButton(),
        ],
      ),
      body: AsyncView(
        summaryAsync,
        builder: (s) {
          final header = Center(
            child: PeriodSwitcher(
              label: '$year',
              onPrevious: year > minYear ? () => ref.read(cashFlowYearProvider.notifier).set(year - 1) : null,
              onNext: year < maxYear ? () => ref.read(cashFlowYearProvider.notifier).set(year + 1) : null,
            ),
          );
          if (s.isEmpty) {
            return PageBody(
              children: [
                header,
                const EmptyState(
                  icon: Icons.insights_outlined,
                  title: 'No data for this year',
                  message: 'Add transactions, or import your web app data from Settings → Import & export.',
                ),
              ],
            );
          }
          return PageBody(
            children: [
              header,
              TileGrid(
                children: [
                  StatTile(label: 'Total income', value: formatMoney(s.incomeCents), valueColor: context.incomeColor),
                  StatTile(label: 'Total expenses', value: formatMoney(s.expenseCents)),
                  StatTile(
                    label: 'Total savings',
                    value: formatMoney(s.savingsCents),
                    valueColor: s.savingsCents < 0 ? context.negativeColor : null,
                  ),
                  StatTile(
                    label: 'Saved',
                    value: s.savingsRate == null ? '—' : formatPercent(s.savingsRate!),
                    caption: 'of income',
                  ),
                  StatTile(
                    label: 'Avg expense / month',
                    value: formatMoney(s.avgExpensePerMonth),
                    caption: 'over ${s.monthSpan} months',
                  ),
                  StatTile(
                    label: 'Avg / month excl. fixed',
                    value: formatMoney(s.avgFlexiblePerMonth),
                    caption: 'Fixed: ${formatMoney(s.fixedCents)} total',
                  ),
                ],
              ),
              SectionCard(
                title: 'Financial flow',
                child: SankeyChart(summary: s),
              ),
              SectionCard(
                title: 'Income vs. expenses',
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Tap a month to see it',
                    style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
                child: Column(
                  children: [
                    MonthlyCashFlowChart(
                      months: s.months,
                      onMonthTap: (m) => _drillDown(context, ref, year, month: m),
                    ),
                    const SizedBox(height: 8),
                    ChartLegend({'Income': context.incomeColor, 'Expenses': context.expenseColor}),
                  ],
                ),
              ),
              _CategoryAverages(
                summary: s,
                year: year,
                onViewTransactions: (id) => _drillDown(context, ref, year, categoryId: id),
              ),
              _MonthlyTable(
                summary: s,
                onMonthTap: (m) => _drillDown(context, ref, year, month: m),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryAverages extends StatelessWidget {
  const _CategoryAverages({required this.summary, required this.year, required this.onViewTransactions});
  final PeriodSummary summary;
  final int year;
  final ValueChanged<String> onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final rows = summary.expenseByCategory;
    return SectionCard(
      title: 'Spending by category',
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                SizedBox(
                  width: 96,
                  child: Text('Total', textAlign: TextAlign.right, style: context.text.labelSmall),
                ),
                SizedBox(
                  width: 96,
                  child: Text('Monthly avg', textAlign: TextAlign.right, style: context.text.labelSmall),
                ),
              ],
            ),
          ),
          for (final c in rows)
            InkWell(
              onTap: () => _showCategory(context, c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    CategoryAvatar(c.category, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.category.name, overflow: TextOverflow.ellipsis),
                          Text(
                            '${formatPercent(c.share)}${c.category.isFixed ? ' · Fixed' : ''}',
                            style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 96, child: Text(formatMoney(c.cents), textAlign: TextAlign.right)),
                    SizedBox(
                      width: 96,
                      child: Text(
                        formatMoney(summary.monthlyAverageFor(c.category.id)),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCategory(BuildContext context, CategoryTotal c) {
    final monthly = [for (final m in summary.months) m.expenseByCategory[c.category.id] ?? 0];
    final average = summary.monthlyAverageFor(c.category.id);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryAvatar(c.category),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${c.category.name} in $year', style: context.text.titleLarge)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${formatMoney(c.cents)} total · ${formatMoney(average)} / month · ${c.count} transactions',
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              CategoryTrendChart(monthlyCents: monthly, color: Color(c.category.color), average: average),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  onViewTransactions(c.category.id);
                },
                child: const Text('View transactions'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyTable extends StatelessWidget {
  const _MonthlyTable({required this.summary, required this.onMonthTap});
  final PeriodSummary summary;
  final ValueChanged<int> onMonthTap;

  @override
  Widget build(BuildContext context) {
    final header = context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant);
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final body = (narrow ? context.text.bodySmall : context.text.bodyMedium)?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget amount(String text, {TextStyle? style, Color? color, FontWeight? weight}) => Expanded(
      flex: 4,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: (style ?? body)?.copyWith(color: color, fontWeight: weight),
      ),
    );
    return SectionCard(
      title: 'Monthly breakdown',
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Month', style: header)),
                amount('Income', style: header),
                amount('Expenses', style: header),
                amount('Saved', style: header),
              ],
            ),
          ),
          for (final m in summary.activeMonths)
            InkWell(
              onTap: () => onMonthTap(m.month),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text(narrow ? monthShort(m.month) : monthName(m.month), style: body)),
                    amount(formatMoney(m.incomeCents), color: context.incomeColor),
                    amount(formatMoney(m.expenseCents)),
                    amount(
                      formatMoney(m.savingsCents),
                      color: m.savingsCents < 0 ? context.negativeColor : null,
                      weight: FontWeight.w600,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
