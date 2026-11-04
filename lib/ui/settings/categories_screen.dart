import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets.dart';

const _palette = [
  0xFFFF6384,
  0xFF009EFF,
  0xFFB0BEC5,
  0xFF11734B,
  0xFFFFB900,
  0xFF215A6C,
  0xFFF93380,
  0xFFB10202,
  0xFFD97E00,
  0xFFFD8D50,
  0xFF5A3286,
  0xFF2E7D32,
  0xFF26A69A,
  0xFF7E57C2,
  0xFF42A5F5,
  0xFF8D6E63,
  0xFF9CCC65,
  0xFF5C6BC0,
];

const _emojis = [
  '🏠',
  '🛋️',
  '💡',
  '🛒',
  '🍽️',
  '☕',
  '🍺',
  '🧍',
  '🎬',
  '🎮',
  '🩺',
  '💊',
  '✈️',
  '🏨',
  '🚗',
  '⛽',
  '🚆',
  '📦',
  '🎁',
  '👕',
  '💇',
  '📱',
  '💻',
  '📚',
  '🐶',
  '👶',
  '🏋️',
  '🧾',
  '💰',
  '🏦',
  '💵',
  '📈',
  '🎓',
  '🔧',
  '🌿',
  '🏷️',
];

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).value ?? const [];
    final categories = ref.watch(categoriesProvider).value ?? const [];

    Widget section(TxKind kind, String title) {
      final kindGroups = groups.where((g) => g.kind == kind).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
            child: Text(title, style: context.text.titleLarge),
          ),
          for (final g in kindGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      g.name.toUpperCase(),
                      style: context.text.labelMedium?.copyWith(color: context.colors.primary, letterSpacing: 1),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add category to ${g.name}',
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _CategoryDialog(kind: kind, groupId: g.id),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Group options',
                    onSelected: (action) async {
                      final db = ref.read(databaseProvider);
                      if (action == 'rename') {
                        final name = await _promptText(context, title: 'Rename group', initial: g.name);
                        if (name != null) await db.renameGroup(g.id, name);
                      } else if (action == 'delete') {
                        final ok = await db.deleteGroup(g.id);
                        if (!ok && context.mounted) showMessage(context, 'Move or delete its categories first');
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
            for (final c in categories.where((c) => c.groupId == g.id))
              ListTile(
                leading: CategoryAvatar(c),
                title: Text(c.name),
                subtitle: c.isFixed ? const Text('Fixed · excluded from flexible averages') : null,
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => _CategoryDialog(kind: kind, category: c),
                ),
              ),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null, // tabs stay mounted in an IndexedStack; shared default tags clash
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New group'),
        onPressed: () async {
          final kind = await showDialog<TxKind>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('New group for'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, TxKind.expense),
                  child: const Text('Expenses'),
                ),
                SimpleDialogOption(onPressed: () => Navigator.pop(context, TxKind.income), child: const Text('Income')),
              ],
            ),
          );
          if (kind == null || !context.mounted) return;
          final name = await _promptText(context, title: 'Group name');
          if (name != null) await ref.read(databaseProvider).addGroup(name, kind);
        },
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [section(TxKind.expense, 'Expenses'), section(TxKind.income, 'Income')],
          ),
        ),
      ),
    );
  }
}

Future<String?> _promptText(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim().isEmpty ? null : controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({required this.kind, this.category, this.groupId});
  final TxKind kind;
  final Category? category;
  final String? groupId;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late final _emoji = TextEditingController(text: widget.category?.emoji ?? '🏷️');
  late int _color = widget.category?.color ?? _palette.first;
  late bool _fixed = widget.category?.isFixed ?? false;
  late String? _groupId = widget.category?.groupId ?? widget.groupId;

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _groupId == null) return;
    final existing = ref.read(categoriesProvider).value ?? const [];
    final duplicate = existing.any(
      (c) => c.id != widget.category?.id && c.kind == widget.kind && c.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      showMessage(context, 'Category already exists');
      return;
    }
    final emoji = _emoji.text.trim().isEmpty ? '🏷️' : _emoji.text.trim();
    final db = ref.read(databaseProvider);
    if (widget.category == null) {
      await db.addCategory(
        name: name,
        groupId: _groupId!,
        kind: widget.kind,
        emoji: emoji,
        color: _color,
        isFixed: _fixed,
      );
    } else {
      await db.updateCategory(
        widget.category!.id,
        CategoriesCompanion(
          name: Value(name),
          emoji: Value(emoji),
          color: Value(_color),
          isFixed: Value(_fixed),
          groupId: Value(_groupId!),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final db = ref.read(databaseProvider);
    final c = widget.category!;
    final inUse = await db.countTransactionsForCategory(c.id);
    if (!mounted) return;
    if (inUse == 0) {
      if (await confirm(context, title: 'Delete ${c.name}?', message: 'This category has no transactions.')) {
        await db.deleteCategory(c.id);
        if (mounted) Navigator.pop(context);
      }
      return;
    }
    final others = (ref.read(categoriesProvider).value ?? const [])
        .where((o) => o.kind == c.kind && o.id != c.id)
        .toList();
    if (others.isEmpty) {
      showMessage(context, 'Cannot delete the last ${c.kind.name} category');
      return;
    }
    final target = await showDialog<Category>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move $inUse transaction${inUse == 1 ? '' : 's'} to…'),
        children: [
          for (final o in others)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o),
              child: Row(children: [Text(o.emoji), const SizedBox(width: 12), Text(o.name)]),
            ),
        ],
      ),
    );
    if (target == null) return;
    await db.deleteCategory(c.id, reassignTo: target.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final groups = (ref.watch(groupsProvider).value ?? const []).where((g) => g.kind == widget.kind).toList();
    return AlertDialog(
      title: Text(widget.category == null ? 'New category' : 'Edit category'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _emoji,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24),
                      decoration: const InputDecoration(labelText: 'Emoji'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      autofocus: widget.category == null,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final e in _emojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _emoji.text = e),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: groups.any((g) => g.id == _groupId) ? _groupId : null,
                decoration: const InputDecoration(labelText: 'Group'),
                items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name))],
                onChanged: (v) => setState(() => _groupId = v),
              ),
              const SizedBox(height: 16),
              Text('Chart colour', style: context.text.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _palette)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c == _color ? context.colors.onSurface : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (widget.kind == TxKind.expense)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fixed cost'),
                  subtitle: const Text('Excluded from flexible spending and "avg excl. fixed" (like Rent)'),
                  value: _fixed,
                  onChanged: (v) => setState(() => _fixed = v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.category != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
