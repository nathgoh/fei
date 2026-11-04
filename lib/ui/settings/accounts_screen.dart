import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../state/providers.dart';
import '../widgets.dart';

IconData accountIcon(AccountType t) => switch (t) {
  AccountType.checking => Icons.account_balance_outlined,
  AccountType.savings => Icons.savings_outlined,
  AccountType.credit => Icons.credit_card,
  AccountType.cash => Icons.payments_outlined,
  AccountType.other => Icons.wallet_outlined,
};

String accountTypeLabel(AccountType t) => switch (t) {
  AccountType.checking => 'Checking',
  AccountType.savings => 'Savings',
  AccountType.credit => 'Credit card',
  AccountType.cash => 'Cash',
  AccountType.other => 'Other',
};

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null, // tabs stay mounted in an IndexedStack; shared default tags clash
        icon: const Icon(Icons.add),
        label: const Text('Add account'),
        onPressed: () => showDialog(context: context, builder: (_) => const _AccountDialog()),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: accounts.isEmpty
              ? const EmptyState(
                  icon: Icons.credit_card_outlined,
                  title: 'No accounts',
                  message:
                      'Accounts are optional labels for which card or account paid. '
                      'Once you add one, a "Paid with" field appears on transactions. No balances are tracked.',
                )
              : ListView(
                  children: [
                    for (final a in accounts)
                      ListTile(
                        leading: Icon(accountIcon(a.type)),
                        title: Text(a.name),
                        subtitle: Text(accountTypeLabel(a.type)),
                        trailing: const Icon(Icons.edit_outlined, size: 20),
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => _AccountDialog(account: a),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AccountDialog extends ConsumerStatefulWidget {
  const _AccountDialog({this.account});
  final Account? account;

  @override
  ConsumerState<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends ConsumerState<_AccountDialog> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late AccountType _type = widget.account?.type ?? AccountType.credit;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    if (widget.account == null) {
      await db.addAccount(name, _type);
    } else {
      await db.updateAccount(widget.account!.id, AccountsCompanion(name: Value(name), type: Value(_type)));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete ${widget.account!.name}?',
      message: 'Transactions keep their history but lose this label.',
    );
    if (!ok) return;
    await ref.read(databaseProvider).deleteAccount(widget.account!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.account == null ? 'New account' : 'Edit account'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Amex Gold'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in AccountType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Row(
                      children: [Icon(accountIcon(t), size: 18), const SizedBox(width: 8), Text(accountTypeLabel(t))],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.account != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
