import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../state/providers.dart';
import '../emoji_glyph.dart';
import '../theme.dart';
import '../widgets.dart';
import 'transaction_form.dart';

class TransactionFilter {
  const TransactionFilter({this.year, this.month, this.kind = TxKind.expense, this.categoryId, this.query = ''});
  final int? year;
  final int? month;

  /// Which tab is showing: expenses or income.
  final TxKind kind;
  final String? categoryId;
  final String query;

  ({String? from, String? to}) get range {
    if (year == null) return (from: null, to: null);
    if (month == null) return yearRange(year!);
    return monthRange(year!, month!);
  }

  String get periodLabel => year == null
      ? 'All time'
      : month == null
      ? '$year'
      : formatMonthYear(year!, month!);

  TransactionFilter copyWith({
    Object? year = _keep,
    Object? month = _keep,
    TxKind? kind,
    Object? categoryId = _keep,
    String? query,
  }) => TransactionFilter(
    year: year == _keep ? this.year : year as int?,
    month: month == _keep ? this.month : month as int?,
    kind: kind ?? this.kind,
    categoryId: categoryId == _keep ? this.categoryId : categoryId as String?,
    query: query ?? this.query,
  );
}

const _keep = Object();

class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() {
    final now = DateTime.now();
    return TransactionFilter(year: now.year, month: now.month);
  }

  void set(TransactionFilter filter) => state = filter;
}

/// Shared so other screens can drill down (e.g. tapping a month in Cash Flow).
final transactionFilterProvider = NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
  TransactionFilterNotifier.new,
);

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

/// The tabs, in the order they appear.
const _tabKinds = [TxKind.expense, TxKind.income];

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> with SingleTickerProviderStateMixin {
  bool _searching = false;
  final _search = TextEditingController();
  late final TabController _tabs = TabController(
    length: _tabKinds.length,
    vsync: this,
    initialIndex: _tabKinds.indexOf(ref.read(transactionFilterProvider).kind),
  );

  @override
  void dispose() {
    _search.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// Switches tab. The category filter is cleared, since a category belongs to only one kind.
  void _selectTab(int index) {
    final kind = _tabKinds[index];
    if (kind != _filter.kind) _set(_filter.copyWith(kind: kind, categoryId: null));
  }

  TransactionFilter get _filter => ref.read(transactionFilterProvider);
  void _set(TransactionFilter f) => ref.read(transactionFilterProvider.notifier).set(f);

  void _shiftMonth(int delta) {
    final f = _filter;
    if (f.year == null) return;
    if (f.month == null) {
      _set(f.copyWith(year: f.year! + delta));
    } else {
      final d = DateTime(f.year!, f.month! + delta);
      _set(f.copyWith(year: d.year, month: d.month));
    }
  }

  Future<void> _pickPeriod() async {
    final years = ref.read(yearsProvider).value ?? [DateTime.now().year];
    final result = await showDialog<TransactionFilter>(
      context: context,
      builder: (context) => _PeriodDialog(initial: _filter, years: years),
    );
    if (result != null) _set(result);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionFilterProvider);
    final categories = ref.watch(categoryMapProvider);
    final txnsAsync = ref.watch(transactionsProvider(filter.range));
    // Other screens can change the tab when they drill down here.
    ref.listen(transactionFilterProvider.select((f) => f.kind), (_, kind) {
      final index = _tabKinds.indexOf(kind);
      if (_tabs.index != index) _tabs.animateTo(index);
    });
    final isIncome = filter.kind == TxKind.income;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search merchant, notes, category',
                  filled: false,
                  border: InputBorder.none,
                ),
                onChanged: (v) => _set(_filter.copyWith(query: v)),
              )
            : const Text('Transactions'),
        bottom: TabBar(
          controller: _tabs,
          onTap: _selectTab,
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'Income'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search.clear();
                _set(_filter.copyWith(query: ''));
              }
            }),
          ),
          const SettingsButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // tabs stay mounted in an IndexedStack; shared default tags clash
        onPressed: () => showTransactionForm(context, kind: filter.kind),
        tooltip: isIncome ? 'Add income' : 'Add expense',
        child: const Icon(Icons.add),
      ),
      // Keeps the filter bar and list to one readable column on wide screens.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              _FilterBar(
                filter: filter,
                categories: categories,
                onPrevious: filter.year == null ? null : () => _shiftMonth(-1),
                onNext: filter.year == null ? null : () => _shiftMonth(1),
                onPickPeriod: _pickPeriod,
                onChanged: _set,
              ),
              Expanded(
                child: AsyncView(
                  txnsAsync,
                  builder: (all) {
                    final ofKind = all.where((t) => t.kind == filter.kind).toList();
                    final txns = _apply(ofKind, filter, categories);
                    if (txns.isEmpty) {
                      return EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: ofKind.isEmpty
                            ? 'No ${isIncome ? 'income' : 'expenses'} in ${filter.periodLabel}'
                            : 'Nothing matches these filters',
                        message: ofKind.isEmpty ? 'Tap Add to record ${isIncome ? 'income' : 'an expense'}.' : null,
                      );
                    }
                    return _TransactionList(txns: txns, kind: filter.kind, categories: categories);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Txn> _apply(List<Txn> txns, TransactionFilter f, Map<String, Category> categories) {
    final q = f.query.trim().toLowerCase();
    return txns.where((t) {
      if (f.categoryId != null && t.categoryId != f.categoryId) return false;
      if (q.isNotEmpty) {
        final haystack = [
          t.merchant,
          t.notes,
          categories[t.categoryId]?.name,
          formatMoney(t.amountCents),
        ].whereType<String>().join(' ').toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.categories,
    required this.onPrevious,
    required this.onNext,
    required this.onPickPeriod,
    required this.onChanged,
  });
  final TransactionFilter filter;
  final Map<String, Category> categories;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickPeriod;
  final ValueChanged<TransactionFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final category = categories[filter.categoryId];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              // Balances the filter button so the period stays centred.
              const SizedBox(width: 48),
              Expanded(
                child: Center(
                  child: PeriodSwitcher(
                    label: filter.periodLabel,
                    onPrevious: onPrevious,
                    onNext: onNext,
                    onTap: onPickPeriod,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Filter by category',
                icon: const Icon(Icons.filter_list),
                isSelected: category != null,
                onPressed: () async {
                  final picked = await pickCategory(context, kind: filter.kind, selectedId: filter.categoryId);
                  if (picked != null) onChanged(filter.copyWith(categoryId: picked.id));
                },
              ),
            ],
          ),
          if (category != null)
            Chip(
              avatar: EmojiGlyph(category.emoji, size: 14),
              label: Text(category.name),
              onDeleted: () => onChanged(filter.copyWith(categoryId: null)),
              deleteButtonTooltipMessage: 'Clear filter',
            ),
        ],
      ),
    );
  }
}

class _TransactionList extends ConsumerWidget {
  const _TransactionList({required this.txns, required this.kind, required this.categories});

  /// All of one [kind].
  final List<Txn> txns;
  final TxKind kind;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = txns.map((t) => t.amountCents).sum;
    final byDay = groupBy(txns, (Txn t) => t.date);
    final items = <Object>[];
    for (final day in byDay.keys) {
      items.add(day);
      items.addAll(byDay[day]!);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              '${txns.length} transaction${txns.length == 1 ? '' : 's'} · '
              '${kind == TxKind.income ? 'Received' : 'Spent'} ${formatMoney(total)}',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          );
        }
        final item = items[i - 1];
        if (item is String) {
          final date = parseYmd(item);
          final dayTotal = byDay[item]!.map((t) => t.amountCents).sum;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    date == today() ? 'Today' : formatDateLong(date),
                    style: context.text.labelLarge?.copyWith(color: context.colors.primary),
                  ),
                ),
                Text(
                  formatMoney(dayTotal),
                  style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        final t = item as Txn;
        return Dismissible(
          key: ValueKey(t.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: context.colors.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline, color: context.colors.onErrorContainer),
          ),
          onDismissed: (_) {
            final db = ref.read(databaseProvider);
            db.deleteTransactions([t.id]);
            showMessage(
              context,
              'Transaction deleted',
              action: SnackBarAction(label: 'Undo', onPressed: () => db.restoreTransactions([t.id])),
            );
          },
          child: TransactionTile(
            txn: t,
            category: categories[t.categoryId],
            onTap: () => showTransactionForm(context, txn: t),
          ),
        );
      },
    );
  }
}

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog({required this.initial, required this.years});
  final TransactionFilter initial;
  final List<int> years;

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late int _year = widget.initial.year ?? DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final years = {...widget.years, _year}.toList()..sort((a, b) => b - a);
    return AlertDialog(
      title: const Text('Show transactions for'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: 'Year'),
              items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (y) => setState(() => _year = y!),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: [
                for (var m = 1; m <= 12; m++)
                  _MonthButton(
                    label: monthShort(m),
                    selected: widget.initial.year == _year && widget.initial.month == m,
                    onTap: () => Navigator.pop(context, widget.initial.copyWith(year: _year, month: m)),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, widget.initial.copyWith(year: null, month: null)),
          child: const Text('All time'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, widget.initial.copyWith(year: _year, month: null)),
          child: Text('All of $_year'),
        ),
      ],
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return selected
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(label),
          );
  }
}
