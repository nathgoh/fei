import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../domain/analytics.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../transactions/merchant_field.dart';
import '../transactions/transaction_form.dart';
import '../widgets.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(recurringProvider);
    final categories = ref.watch(categoryMapProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring'), actions: const [SettingsButton()]),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // tabs stay mounted in an IndexedStack; shared default tags clash
        onPressed: () => showTransactionForm(context, startRecurring: true),
        tooltip: 'Add recurring',
        child: const Icon(Icons.add),
      ),
      body: AsyncView(
        seriesAsync,
        builder: (series) {
          if (series.isEmpty) {
            return const EmptyState(
              icon: Icons.event_repeat_outlined,
              title: 'No recurring transactions',
              message:
                  'Track rent, subscriptions and paychecks. Occurrences are added automatically as their dates arrive.',
            );
          }
          final active = series.where(isSeriesActive).toList();
          final ended = series.whereNot(isSeriesActive).toList();
          final expenseMonthly = active.where((s) => s.kind == TxKind.expense).map(monthlyEquivalent).sum;
          final incomeMonthly = active.where((s) => s.kind == TxKind.income).map(monthlyEquivalent).sum;
          final upcoming = upcomingOccurrences(active, days: 30);

          String title(RecurringSeries s) => s.merchant ?? s.notes ?? categories[s.categoryId]?.name ?? 'Recurring';

          Widget tile(RecurringSeries s) {
            final next = nextOccurrence(s);
            final status = isSeriesActive(s)
                ? next == null
                      ? 'No more occurrences'
                      : 'Next ${formatDateShort(next)}'
                : 'Ended ${formatDateShort(parseYmd(s.endDate!))}';
            return ListTile(
              leading: CategoryAvatar(categories[s.categoryId]),
              title: Text(title(s), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${frequencyLabel(s.frequency)} · $status'),
              trailing: AmountText(s.amountCents, s.kind),
              onTap: () => showSeriesEditor(context, s),
            );
          }

          return PageBody(
            maxWidth: 900,
            children: [
              TileGrid(
                children: [
                  StatTile(
                    label: 'Recurring expenses',
                    value: formatMoney(expenseMonthly),
                    caption: 'per month, ${active.where((s) => s.kind == TxKind.expense).length} active',
                  ),
                  StatTile(
                    label: 'Recurring income',
                    value: formatMoney(incomeMonthly),
                    valueColor: context.incomeColor,
                    caption: 'per month',
                  ),
                ],
              ),
              SectionCard(
                title: 'Next 30 days',
                padding: const EdgeInsets.only(bottom: 8),
                child: upcoming.isEmpty
                    ? const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Nothing due.'))
                    : Column(
                        children: [
                          for (final o in upcoming)
                            ListTile(
                              dense: true,
                              leading: SizedBox(
                                width: 40,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      monthShort(o.date.month).toUpperCase(),
                                      style: context.text.labelSmall?.copyWith(color: context.colors.primary),
                                    ),
                                    Text('${o.date.day}', style: context.text.titleMedium),
                                  ],
                                ),
                              ),
                              title: Text(title(o.series)),
                              subtitle: Text(categories[o.series.categoryId]?.name ?? ''),
                              trailing: AmountText(o.series.amountCents, o.series.kind),
                              onTap: () => showSeriesEditor(context, o.series),
                            ),
                        ],
                      ),
              ),
              if (active.isNotEmpty)
                SectionCard(
                  title: 'Active',
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(children: active.map(tile).toList()),
                ),
              if (ended.isNotEmpty)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    title: Text('Ended (${ended.length})'),
                    shape: const Border(),
                    children: ended.map(tile).toList(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> showSeriesEditor(BuildContext context, RecurringSeries series) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _SeriesEditor(series: series),
);

class _SeriesEditor extends ConsumerStatefulWidget {
  const _SeriesEditor({required this.series});
  final RecurringSeries series;

  @override
  ConsumerState<_SeriesEditor> createState() => _SeriesEditorState();
}

class _SeriesEditorState extends ConsumerState<_SeriesEditor> {
  late final _amount = TextEditingController(text: (widget.series.amountCents / 100).toStringAsFixed(2));
  late String _merchant = widget.series.merchant ?? '';
  bool _merchantMissing = false;
  late final _notes = TextEditingController(text: widget.series.notes ?? '');
  late String _categoryId = widget.series.categoryId;
  late DateTime? _endDate = widget.series.endDate == null ? null : parseYmd(widget.series.endDate!);
  bool _applyToPast = false;

  RecurringSeries get s => widget.series;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseCents(_amount.text);
    if (cents == null || cents == 0) {
      showMessage(context, 'Enter an amount');
      return;
    }
    if (_merchant.trim().isEmpty) {
      setState(() => _merchantMissing = true);
      return;
    }
    await ref
        .read(databaseProvider)
        .updateSeries(
          s.id,
          amountCents: cents.abs(),
          categoryId: _categoryId,
          merchant: _merchant,
          notes: _notes.text,
          endDate: _endDate == null ? null : ymd(_endDate!),
          applyToPast: _applyToPast,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _stop() async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(databaseProvider).stopSeries(s);
    if (mounted) Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Recurring series ended today'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _delete() async {
    final db = ref.read(databaseProvider);
    final deleteTxns = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recurring series?'),
        content: const Text('Keep the transactions it already created, or delete them too?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep transactions')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (deleteTxns == null) return;
    await db.deleteSeries(s.id, deleteTransactions: deleteTxns);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryMapProvider);
    final category = categories[_categoryId];
    final active = isSeriesActive(s);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Edit recurring', style: context.text.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${frequencyLabel(s.frequency)} since ${formatDateShort(parseYmd(s.startDate))}',
            style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(labelText: 'Amount', prefixText: r'$ '),
          ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: context.colors.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: CategoryAvatar(category, size: 32),
            title: Text(category?.name ?? 'Category'),
            trailing: const Icon(Icons.expand_more),
            onTap: () async {
              final picked = await pickCategory(context, kind: s.kind, selectedId: _categoryId);
              if (picked != null) setState(() => _categoryId = picked.id);
            },
          ),
          const SizedBox(height: 12),
          MerchantField(
            kind: s.kind,
            categoryId: _categoryId,
            initialValue: _merchant,
            onChanged: (v) => setState(() {
              _merchant = v;
              _merchantMissing = false;
            }),
            decoration: InputDecoration(errorText: _merchantMissing ? merchantMissingMessage(s.kind) : null),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 12),
          ListTile(
            tileColor: context.colors.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.event_busy_outlined),
            title: Text(_endDate == null ? 'No end date' : 'Ends ${formatDateShort(_endDate!)}'),
            trailing: _endDate == null
                ? const Icon(Icons.edit_calendar_outlined)
                : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _endDate = null)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDate ?? today(),
                firstDate: parseYmd(s.startDate),
                lastDate: DateTime(today().year + 10),
              );
              if (picked != null) setState(() => _endDate = picked);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Also update past occurrences'),
            subtitle: const Text('Otherwise changes apply from the next occurrence'),
            value: _applyToPast,
            onChanged: (v) => setState(() => _applyToPast = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Save'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (active)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('End today'),
                  ),
                ),
              if (active) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(foregroundColor: context.colors.error),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
