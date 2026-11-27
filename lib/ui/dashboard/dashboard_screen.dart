import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../domain/analytics.dart';
import '../../state/providers.dart';
import '../charts/charts.dart';
import '../theme.dart';
import '../transactions/transaction_form.dart';
import '../transactions/transactions_screen.dart';
import '../widgets.dart';

class DashboardMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void shift(int delta) => state = DateTime(state.year, state.month + delta);

  void goToCurrent() => state = build();
}

final dashboardMonthProvider = NotifierProvider<DashboardMonthNotifier, DateTime>(DashboardMonthNotifier.new);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(dashboardMonthProvider);
    final previous = DateTime(month.year, month.month - 1);
    final categories = ref.watch(categoryMapProvider);
    // Load both months in one range so the comparison chart has last month too.
    final range = (from: monthRange(previous.year, previous.month).from, to: monthRange(month.year, month.month).to);
    final txnsAsync = ref.watch(transactionsProvider(range));

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), actions: const [SettingsButton()]),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // tabs stay mounted in an IndexedStack; shared default tags clash
        tooltip: 'Add transaction',
        onPressed: () => showTransactionForm(context),
        child: const Icon(Icons.add),
      ),
      body: AsyncView(
        txnsAsync,
        builder: (txns) {
          final prefix = monthKey(month.year, month.month);
          final thisMonth = txns.where((t) => t.date.startsWith(prefix)).toList();
          final summary = summarize(thisMonth, categories);
          final now = today();
          final isCurrent = month.year == now.year && month.month == now.month;
          final throughDay = isCurrent ? now.day : daysInMonth(month.year, month.month);

          final summaryCard = _SummaryCard(summary: summary);
          final spendingCard = SectionCard(
            title: 'Flexible spending',
            child: _SpendingComparison(
              current: cumulativeDailySpending(txns, categories, month.year, month.month),
              previous: cumulativeDailySpending(txns, categories, previous.year, previous.month),
              month: month,
              previousMonth: previous,
              throughDay: throughDay,
              fixedCents: summary.fixedCents,
            ),
          );
          final categoriesCard = _TopCategoriesCard(summary: summary);
          final upcomingCard = const _UpcomingCard();
          final recentCard = _RecentCard(txns: thisMonth, month: month);

          final header = Column(
            children: [
              PeriodSwitcher(
                label: formatMonthYear(month.year, month.month),
                onPrevious: () => ref.read(dashboardMonthProvider.notifier).shift(-1),
                onNext: () => ref.read(dashboardMonthProvider.notifier).shift(1),
              ),
              // Only shown when browsing another month.
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: isCurrent
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ActionChip(
                          avatar: const Icon(Icons.today, size: 18),
                          label: Text('Present'),
                          onPressed: ref.read(dashboardMonthProvider.notifier).goToCurrent,
                        ),
                      ),
              ),
            ],
          );

          if (context.isWide) {
            return PageBody(
              children: [
                header,
                summaryCard,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: [spendingCard, const SizedBox(height: 16), recentCard])),
                    const SizedBox(width: 16),
                    Expanded(child: Column(children: [categoriesCard, const SizedBox(height: 16), upcomingCard])),
                  ],
                ),
              ],
            );
          }
          return PageBody(children: [header, summaryCard, spendingCard, categoriesCard, upcomingCard, recentCard]);
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final rate = summary.savingsRate;
    Widget figure(String label, int cents, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(label, style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              formatMoney(cents),
              style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                figure('Income', summary.incomeCents, color: context.incomeColor),
                figure('Expenses', summary.expenseCents),
                figure('Saved', summary.savingsCents, color: summary.savingsCents < 0 ? context.negativeColor : null),
              ],
            ),
            if (rate != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (rate / 100).clamp(0, 1),
                  minHeight: 8,
                  color: rate < 0 ? context.negativeColor : context.incomeColor,
                  backgroundColor: context.colors.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                rate >= 0 ? 'Saved ${formatPercent(rate)} of income' : 'Spent ${formatPercent(-rate)} more than earned',
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpendingComparison extends StatelessWidget {
  const _SpendingComparison({
    required this.current,
    required this.previous,
    required this.month,
    required this.previousMonth,
    required this.throughDay,
    required this.fixedCents,
  });
  final List<int> current;
  final List<int> previous;
  final DateTime month;
  final DateTime previousMonth;
  final int throughDay;
  final int fixedCents;

  @override
  Widget build(BuildContext context) {
    final spent = current[throughDay - 1];
    final previousDay = throughDay.clamp(1, previous.length);
    final lastAtSameDay = previous[previousDay - 1];
    final diff = spent - lastAtSameDay;
    final thisLabel = monthShort(month.month);
    final lastLabel = monthShort(previousMonth.month);
    // Mid-month, compare with the same days of last month ("Oct 1–4"); otherwise whole months.
    final comparedTo = previousDay < previous.length ? '$lastLabel 1–$previousDay' : lastLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatMoney(spent), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        Text(
          lastAtSameDay == 0 && spent == 0
              ? 'No flexible spending yet'
              : diff == 0
              ? 'Same as $comparedTo'
              : '${formatMoney(diff.abs())} ${diff > 0 ? 'more' : 'less'} than $comparedTo',
          style: context.text.bodySmall?.copyWith(color: diff > 0 ? context.negativeColor : context.incomeColor),
        ),
        const SizedBox(height: 16),
        SpendingComparisonChart(
          current: current,
          previous: previous,
          throughDay: throughDay,
          currentLabel: thisLabel,
          previousLabel: lastLabel,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Legend(color: context.colors.primary, label: thisLabel),
            _Legend(color: context.colors.outline, label: lastLabel),
            if (fixedCents > 0) Text('+ ${formatMoney(fixedCents)} fixed', style: context.text.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 3, color: color),
      const SizedBox(width: 6),
      Text(label, style: context.text.labelSmall),
    ],
  );
}

class _TopCategoriesCard extends StatelessWidget {
  const _TopCategoriesCard({required this.summary});
  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final top = summary.expenseByCategory.take(6).toList();
    return SectionCard(
      title: 'Spending by category',
      trailing: TextButton(onPressed: () => context.go('/cashflow'), child: const Text('Cash flow')),
      child: top.isEmpty
          ? const Padding(padding: EdgeInsets.all(8), child: Text('No spending this month.'))
          : Column(
              children: [
                for (final c in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        CategoryAvatar(c.category, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(c.category.name, overflow: TextOverflow.ellipsis)),
                                  if (c.category.isFixed)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        'Fixed',
                                        style: context.text.labelSmall?.copyWith(
                                          color: context.colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  Text(formatMoney(c.cents), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: c.share / 100,
                                  minHeight: 6,
                                  color: Color(c.category.color),
                                  backgroundColor: context.colors.surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _UpcomingCard extends ConsumerWidget {
  const _UpcomingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(recurringProvider).value ?? const [];
    final categories = ref.watch(categoryMapProvider);
    final upcoming = upcomingOccurrences(series, days: 14);
    return SectionCard(
      title: 'Upcoming recurring',
      padding: const EdgeInsets.only(bottom: 8),
      trailing: TextButton(onPressed: () => context.go('/recurring'), child: const Text('View all')),
      child: upcoming.isEmpty
          ? const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Nothing due in the next 14 days.'))
          : Column(
              children: [
                for (final o in upcoming.take(5))
                  ListTile(
                    dense: true,
                    leading: CategoryAvatar(categories[o.series.categoryId], size: 32),
                    title: Text(o.series.merchant ?? o.series.notes ?? categories[o.series.categoryId]?.name ?? ''),
                    subtitle: Text(formatDateShort(o.date)),
                    trailing: AmountText(o.series.amountCents, o.series.kind),
                  ),
              ],
            ),
    );
  }
}

class _RecentCard extends ConsumerWidget {
  const _RecentCard({required this.txns, required this.month});
  final List<Txn> txns;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryMapProvider);
    return SectionCard(
      title: 'Recent transactions',
      padding: const EdgeInsets.only(bottom: 8),
      trailing: TextButton(
        onPressed: () {
          final kind = ref.read(transactionFilterProvider).kind;
          ref
              .read(transactionFilterProvider.notifier)
              .set(TransactionFilter(year: month.year, month: month.month, kind: kind));
          context.go('/transactions');
        },
        child: const Text('View all'),
      ),
      child: txns.isEmpty
          ? const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No transactions this month.'))
          : Column(
              children: [
                for (final t in txns.take(6))
                  TransactionTile(
                    txn: t,
                    category: categories[t.categoryId],
                    showDate: true,
                    onTap: () => showTransactionForm(context, txn: t),
                  ),
              ],
            ),
    );
  }
}
