import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/text.dart';
import '../../data/database.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets.dart';
import 'merchant_field.dart';

/// Opens the add/edit transaction sheet. With [startRecurring] the "Repeat"
/// option starts switched on.
Future<void> showTransactionForm(BuildContext context, {Txn? txn, bool startRecurring = false}) {
  final form = _TransactionForm(txn: txn, startRecurring: startRecurring);
  if (context.isWide) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760), child: form),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => form,
  );
}

class _TransactionForm extends ConsumerStatefulWidget {
  const _TransactionForm({this.txn, this.startRecurring = false});
  final Txn? txn;
  final bool startRecurring;

  @override
  ConsumerState<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<_TransactionForm> {
  late TxKind _kind;
  late final TextEditingController _amount;
  late String _merchant;
  late final TextEditingController _notes;
  late DateTime _date;
  String? _categoryId;
  late bool _repeat;
  Frequency _frequency = Frequency.monthly;
  DateTime? _endDate;
  String? _amountError;
  bool _merchantMissing = false;
  bool _saving = false;

  bool get _editing => widget.txn != null;

  @override
  void initState() {
    super.initState();
    final t = widget.txn;
    _kind = t?.kind ?? TxKind.expense;
    _amount = TextEditingController(text: t == null ? '' : (t.amountCents / 100).toStringAsFixed(2));
    _merchant = t?.merchant ?? '';
    _notes = TextEditingController(text: t?.notes ?? '');
    _date = t == null ? today() : parseYmd(t.date);
    _categoryId = t?.categoryId;
    _repeat = widget.startRecurring;
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseCents(_amount.text) ?? 0;
    setState(() {
      _amountError = cents == 0 ? 'Enter an amount' : null;
      _merchantMissing = _merchant.trim().isEmpty;
    });
    if (_amountError != null || _merchantMissing) return;
    if (_categoryId == null) {
      showMessage(context, 'Pick a category');
      return;
    }
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    try {
      if (_repeat && !_editing) {
        await db.createSeries(
          kind: _kind,
          amountCents: cents.abs(),
          categoryId: _categoryId!,
          merchant: normalizeMerchant(_merchant),
          notes: _notes.text,
          frequency: _frequency,
          startDate: ymd(_date),
          endDate: _endDate == null ? null : ymd(_endDate!),
        );
      } else {
        await db.saveTransaction(
          id: widget.txn?.id,
          kind: _kind,
          amountCents: cents.abs(),
          date: ymd(_date),
          categoryId: _categoryId!,
          merchant: normalizeMerchant(_merchant),
          notes: _notes.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save: $e');
      }
    }
  }

  Future<void> _delete() async {
    final db = ref.read(databaseProvider);
    final id = widget.txn!.id;
    await db.deleteTransactions([id]);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Transaction deleted'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: 'Undo', onPressed: () => db.restoreTransactions([id])),
        ),
      );
  }

  Future<void> _pickDate({required bool end}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: end ? (_endDate ?? addDays(_date, 365)) : _date,
      firstDate: end ? _date : DateTime(2000),
      lastDate: DateTime(today().year + 10),
    );
    if (picked == null) return;
    setState(() => end ? _endDate = picked : _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryMapProvider);
    final category = categories[_categoryId];
    final isPast = !_date.isAfter(today());

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text(
          _editing
              ? 'Edit transaction'
              : _repeat
              ? 'New recurring'
              : 'New transaction',
        ),
        actions: [
          if (_editing) IconButton(tooltip: 'Delete', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SegmentedButton<TxKind>(
            segments: const [
              ButtonSegment(value: TxKind.expense, label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
              ButtonSegment(value: TxKind.income, label: Text('Income'), icon: Icon(Icons.arrow_downward)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              if (categories[_categoryId]?.kind != _kind) _categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: !_editing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            decoration: InputDecoration(prefixText: r'$ ', hintText: '0.00', errorText: _amountError),
            onChanged: (_) => _amountError == null ? null : setState(() => _amountError = null),
          ),
          const SizedBox(height: 12),
          _PickerField(
            label: 'Category',
            leading: CategoryAvatar(category, size: 32),
            value: category?.name ?? 'Choose a category',
            onTap: () async {
              final picked = await pickCategory(context, kind: _kind, selectedId: _categoryId);
              if (picked != null) setState(() => _categoryId = picked.id);
            },
          ),
          const SizedBox(height: 12),
          _PickerField(
            label: _repeat ? 'Starts' : 'Date',
            leading: const Icon(Icons.event_outlined),
            value: formatDateShort(_date),
            onTap: () => _pickDate(end: false),
          ),
          const SizedBox(height: 12),
          MerchantField(
            kind: _kind,
            categoryId: _categoryId,
            initialValue: _merchant,
            onChanged: (v) => setState(() {
              _merchant = v;
              _merchantMissing = false;
            }),
            missing: _merchantMissing,
            prefixIcon: const Icon(Icons.storefront_outlined),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes)),
          ),
          if (_editing && widget.txn!.recurringId != null) ...[
            const SizedBox(height: 12),
            Card(
              color: context.colors.secondaryContainer.withValues(alpha: 0.5),
              child: ListTile(
                leading: const Icon(Icons.repeat),
                title: const Text('Part of a recurring series'),
                subtitle: const Text('Changes here only affect this occurrence.'),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/recurring');
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ],
          if (!_editing) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat'),
              subtitle: const Text('Creates a recurring series'),
              value: _repeat,
              onChanged: (v) => setState(() => _repeat = v),
            ),
            if (_repeat) ...[
              DropdownButtonFormField<Frequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Frequency', prefixIcon: Icon(Icons.repeat)),
                items: [for (final f in Frequency.values) DropdownMenuItem(value: f, child: Text(frequencyLabel(f)))],
                onChanged: (v) => setState(() => _frequency = v!),
              ),
              const SizedBox(height: 12),
              _PickerField(
                label: 'Ends',
                leading: const Icon(Icons.event_busy_outlined),
                value: _endDate == null ? 'Never' : formatDateShort(_endDate!),
                onTap: () => _pickDate(end: true),
                trailing: _endDate == null
                    ? null
                    : IconButton(
                        tooltip: 'No end date',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _endDate = null),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  isPast
                      ? 'Occurrences from ${formatDateShort(_date)} up to today are added now; '
                            'later ones are added as their dates arrive.'
                      : 'The first occurrence is added on ${formatDateShort(_date)}.',
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(
              _editing
                  ? 'Save changes'
                  : _repeat
                  ? 'Add recurring'
                  : 'Add transaction',
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.label, required this.value, required this.onTap, this.leading, this.trailing});
  final String label;
  final String value;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: leading == null ? null : Padding(padding: const EdgeInsets.all(8), child: leading),
          suffixIcon: trailing ?? const Icon(Icons.expand_more),
        ),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Lets the user choose a category (of [kind], if given), grouped Monarch-style.
Future<Category?> pickCategory(BuildContext context, {TxKind? kind, String? selectedId}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CategoryPicker(kind: kind, selectedId: selectedId),
  );
}

class _CategoryPicker extends ConsumerStatefulWidget {
  const _CategoryPicker({required this.kind, this.selectedId});
  final TxKind? kind;
  final String? selectedId;

  @override
  ConsumerState<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<_CategoryPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).value ?? const [];
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final q = _query.toLowerCase();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search categories', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                for (final g in groups.where((g) => widget.kind == null || g.kind == widget.kind)) ...[
                  if (categories.any((c) => c.groupId == g.id && c.name.toLowerCase().contains(q)))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        g.name.toUpperCase(),
                        style: context.text.labelMedium?.copyWith(color: context.colors.primary, letterSpacing: 1),
                      ),
                    ),
                  for (final c in categories.where((c) => c.groupId == g.id && c.name.toLowerCase().contains(q)))
                    ListTile(
                      leading: CategoryAvatar(c, size: 36),
                      title: Text(c.name),
                      selected: c.id == widget.selectedId,
                      trailing: c.id == widget.selectedId ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
