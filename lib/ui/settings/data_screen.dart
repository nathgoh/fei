import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/import_export.dart';
import '../../state/providers.dart';
import '../cashflow/cashflow_screen.dart';
import '../theme.dart';
import '../widgets.dart';

class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  bool _busy = false;

  Future<void> _run(Future<ImportResult?> Function() task) async {
    setState(() => _busy = true);
    try {
      final result = await task();
      if (result != null && mounted) await _showResult(result);
    } catch (e) {
      if (mounted) showMessage(context, 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<ImportFile>> _read(List<PlatformFile> files) async => [
    for (final f in files) ImportFile(f.name, utf8.decode(await f.readAsBytes(), allowMalformed: true)),
  ];

  Future<void> _importJson() => _run(() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Select categories.json, expenses.json and incomes.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return null;
    return importWebAppJson(ref.read(databaseProvider), await _read(files));
  });

  Future<void> _importCsv() => _run(() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv']);
    if (file == null) return null;
    return importCsv(ref.read(databaseProvider), (await _read([file])).single);
  });

  Future<void> _export() async {
    final years = ref.read(yearsProvider).value ?? const [];
    final choice = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Export which transactions?'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 0), child: const Text('All time')),
          for (final y in years) SimpleDialogOption(onPressed: () => Navigator.pop(context, y), child: Text('$y')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await exportCsvFile(context, ref.read(databaseProvider), year: choice == 0 ? null : choice);
  }

  Future<void> _erase() async {
    final ok = await confirm(
      context,
      title: 'Erase all data?',
      message:
          'Permanently deletes every transaction, recurring series, account and custom category on this device. '
          'Default categories are restored. This cannot be undone.',
      confirmLabel: 'Erase everything',
    );
    if (!ok) return;
    await ref.read(databaseProvider).eraseAll();
    if (mounted) showMessage(context, 'All data erased');
  }

  Future<void> _showResult(ImportResult r) => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import complete'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.describe()),
            if (r.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${r.warnings.length} warning${r.warnings.length == 1 ? '' : 's'}:', style: context.text.labelLarge),
              for (final w in r.warnings.take(20)) Text('• $w', style: context.text.bodySmall),
              if (r.warnings.length > 20) Text('…and ${r.warnings.length - 20} more', style: context.text.bodySmall),
            ],
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Import & export')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              SectionCard(
                title: 'Import from the web app',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select categories.json, expenses.json and incomes.json from the web app\'s data folder '
                      '(you can pick them all at once). Income sources become income categories, and recurring '
                      'expenses become recurring series. Importing again skips anything already imported.',
                      style: muted,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _importJson,
                      icon: const Icon(Icons.data_object),
                      label: const Text('Choose JSON files'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'CSV',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import needs Date and Amount columns. Type (Income/Expense), Category or Source, Account, '
                      'Merchant/Description and Notes are used when present. Without a Type column, negative amounts '
                      'are treated as expenses. Works with this app\'s export and the web app\'s CSV exports.',
                      style: muted,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _importCsv,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Import CSV'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _export,
                          icon: const Icon(Icons.download),
                          label: const Text('Export CSV'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Danger zone',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _erase,
                    style: OutlinedButton.styleFrom(foregroundColor: context.colors.error),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Erase all data'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
