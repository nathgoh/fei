import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/dates.dart';
import '../core/money.dart';
import 'database.dart';
import 'seed.dart';

class ImportResult {
  int added = 0;
  int skipped = 0;
  int categoriesCreated = 0;
  int seriesCreated = 0;
  final List<String> warnings = [];

  String describe() {
    final parts = [
      '$added transaction${added == 1 ? '' : 's'} imported',
      if (skipped > 0) '$skipped already present',
      if (categoriesCreated > 0) '$categoriesCreated new categor${categoriesCreated == 1 ? 'y' : 'ies'}',
      if (seriesCreated > 0) '$seriesCreated recurring series',
    ];
    return parts.join(' · ');
  }
}

/// A file picked by the user.
class ImportFile {
  ImportFile(this.name, this.content);
  final String name;
  final String content;
}

const _uuid = Uuid();
final _ns = Namespace.url.value;

/// Stable ID for an imported row, so importing the same file twice doesn't
/// create duplicates.
String _importId(String key) => _uuid.v5(_ns, 'fei-import:$key');

/// Finds categories by name, creating them on demand.
class _Resolver {
  _Resolver(this.db, this.result);
  final AppDatabase db;
  final ImportResult result;
  late Map<String, Category> _categories;
  late List<CategoryGroup> _groups;
  var _paletteIndex = 0;

  static const _palette = [
    0xFF26A69A,
    0xFF7E57C2,
    0xFFEF5350,
    0xFF42A5F5,
    0xFFFFCA28,
    0xFF8D6E63,
    0xFFEC407A,
    0xFF9CCC65,
    0xFF5C6BC0,
    0xFFFFA726,
  ];

  Future<void> load() async {
    _categories = {for (final c in await db.allCategories()) _catKey(c.name, c.kind): c};
    _groups = await db.allGroups();
  }

  String _catKey(String name, TxKind kind) => '${kind.name}:${name.trim().toLowerCase()}';

  Future<Category> category(String rawName, TxKind kind) async {
    final name = rawName.trim().isEmpty ? (kind == TxKind.income ? 'Other Income' : 'Miscellaneous') : rawName.trim();
    final existing = _categories[_catKey(name, kind)];
    if (existing != null) return existing;

    final groupName = kind == TxKind.income ? 'Income' : 'Other';
    var group =
        _groups.firstWhereOrNull((g) => g.kind == kind && g.name.toLowerCase() == groupName.toLowerCase()) ??
        _groups.firstWhereOrNull((g) => g.kind == kind);
    if (group == null) {
      await db.addGroup(groupName, kind);
      _groups = await db.allGroups();
      group = _groups.firstWhere((g) => g.kind == kind);
    }
    final style = defaultCategoryNamed(name);
    final id = await db.addCategory(
      name: name,
      groupId: group.id,
      kind: kind,
      emoji: style?.emoji ?? (kind == TxKind.income ? '💵' : '🏷️'),
      color: style?.color ?? _palette[_paletteIndex++ % _palette.length],
      isFixed: style?.isFixed ?? false,
    );
    result.categoriesCreated++;
    final created = (await db.allCategories()).firstWhere((c) => c.id == id);
    _categories[_catKey(name, kind)] = created;
    return created;
  }
}

Future<Set<String>> _existingIds(AppDatabase db) async {
  final rows = await (db.selectOnly(db.transactions)..addColumns([db.transactions.id])).get();
  return rows.map((r) => r.read(db.transactions.id)!).toSet();
}

// -----------------------------------------------------------------------------
// Web app JSON import
// -----------------------------------------------------------------------------

/// Imports the web app's `categories.json`, `expenses.json` and `incomes.json`.
/// Files are recognised by their content, so names don't matter.
///
/// Income "source" becomes the income category (it's what the web app grouped
/// income by), and expenses sharing a `recurring_id` become a recurring series.
Future<ImportResult> importWebAppJson(AppDatabase db, List<ImportFile> files) async {
  final result = ImportResult();
  final parsed = <({String name, Object? data})>[];
  for (final f in files) {
    try {
      parsed.add((name: f.name, data: jsonDecode(f.content)));
    } on FormatException catch (e) {
      result.warnings.add('${f.name}: not valid JSON (${e.message})');
    }
  }

  await db.transaction(() async {
    final resolver = _Resolver(db, result);
    await resolver.load();
    final existing = await _existingIds(db);

    // Categories first so they get their default styling.
    for (final p in parsed) {
      if (p.data is List) {
        for (final name in (p.data as List).whereType<String>()) {
          await resolver.category(name, TxKind.expense);
        }
      }
    }

    for (final p in parsed) {
      final data = p.data;
      if (data is! Map || data['records'] is! List) continue;
      final records = (data['records'] as List).whereType<Map>().toList();
      final isIncome = records.any((r) => r.containsKey('source')) || p.name.toLowerCase().contains('income');
      final kind = isIncome ? TxKind.income : TxKind.expense;

      // Check every record before using any, so a bad one is skipped rather
      // than breaking recurring grouping or rolling back the whole import.
      final valid = <_WebRecord>[];
      for (final r in records) {
        final date = _parseDate(r['date']?.toString() ?? '');
        final amount = r['amount'];
        if (date == null || amount is! num) {
          result.warnings.add('${p.name}: skipped malformed record ${r['id']}');
          continue;
        }
        valid.add((raw: r, date: date, cents: centsFromNum(amount).abs()));
      }

      if (!isIncome) await _importRecurringSeries(db, resolver, valid, result);

      for (final (raw: r, :date, :cents) in valid) {
        final id = _importId('webapp:${kind.name}:${r['id']}');
        if (existing.contains(id)) {
          result.skipped++;
          continue;
        }
        final category = await resolver.category((isIncome ? r['source'] : r['category'])?.toString() ?? '', kind);
        final recurringId = r['recurring_id']?.toString();
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: Value(id),
                kind: kind,
                amountCents: cents,
                date: date,
                categoryId: category.id,
                notes: Value(_nullIfBlank(r['notes']?.toString())),
                recurringId: Value(
                  recurringId == null || recurringId.isEmpty ? null : _importId('webapp:recurring:$recurringId'),
                ),
              ),
            );
        existing.add(id);
        result.added++;
      }
    }
  });
  return result;
}

/// A web app record whose date and amount have been checked.
typedef _WebRecord = ({Map raw, String date, int cents});

Future<void> _importRecurringSeries(
  AppDatabase db,
  _Resolver resolver,
  List<_WebRecord> records,
  ImportResult result,
) async {
  final groups = groupBy(
    records.where((r) => (r.raw['recurring_id']?.toString() ?? '').isNotEmpty),
    (_WebRecord r) => r.raw['recurring_id'].toString(),
  );
  final existing = {for (final s in await db.allRecurring()) s.id};
  for (final entry in groups.entries) {
    final id = _importId('webapp:recurring:${entry.key}');
    if (existing.contains(id)) continue;
    final rows = entry.value.sortedBy((r) => r.date);
    final first = rows.first;
    final frequency =
        Frequency.values.firstWhereOrNull((f) => f.name == first.raw['frequency']?.toString().toLowerCase()) ??
        Frequency.monthly;
    final category = await resolver.category(first.raw['category']?.toString() ?? '', TxKind.expense);
    final lastDate = rows.last.date;
    await db
        .into(db.recurringSeriesTable)
        .insert(
          RecurringSeriesTableCompanion.insert(
            id: Value(id),
            kind: TxKind.expense,
            amountCents: first.cents,
            categoryId: category.id,
            notes: Value(_nullIfBlank(first.raw['notes']?.toString())),
            frequency: frequency,
            startDate: first.date,
            // The web app generated every occurrence up front, so the last
            // record is the series' end.
            endDate: Value(lastDate),
            generatedThrough: Value(lastDate),
          ),
        );
    result.seriesCreated++;
  }
}

// -----------------------------------------------------------------------------
// CSV
// -----------------------------------------------------------------------------

/// Exports transactions (optionally just one year) as CSV in the same format
/// [importCsv] reads.
Future<String> exportCsv(AppDatabase db, {int? year}) async {
  final txns = await db.transactionsBetween(
    from: year == null ? null : '$year-01-01',
    to: year == null ? null : '$year-12-31',
  );
  final categories = {for (final c in await db.allCategories()) c.id: c};
  final groups = {for (final g in await db.allGroups()) g.id: g};
  final rows = <List<Object?>>[
    ['Date', 'Type', 'Category', 'Group', 'Amount', 'Merchant', 'Notes', 'Recurring'],
  ];
  for (final t in txns.reversed) {
    final c = categories[t.categoryId];
    rows.add([
      t.date,
      t.kind == TxKind.income ? 'Income' : 'Expense',
      c?.name ?? '',
      c == null ? '' : groups[c.groupId]?.name ?? '',
      (t.amountCents / 100).toStringAsFixed(2),
      t.merchant ?? '',
      t.notes ?? '',
      t.recurringId == null ? '' : 'yes',
    ]);
  }
  return Csv(lineDelimiter: '\n').encode(rows);
}

/// Imports a CSV with a header row. Recognised columns (case-insensitive):
///
/// * `Date` (required) – `YYYY-MM-DD` or `M/D/YYYY`
/// * `Amount` (required)
/// * `Type` – `Income` / `Expense`. Without it, negative amounts are
///   expenses and positive amounts are income (typical bank exports).
/// * `Category` or `Source` – created if missing
/// * `Merchant` / `Description` / `Payee`, `Notes` / `Memo`
///
/// Other columns (such as `Account` in older exports) are ignored.
///
/// This covers this app's export and the web app's expense/income exports.
Future<ImportResult> importCsv(AppDatabase db, ImportFile file) async {
  final result = ImportResult();
  final rows = Csv().decode(file.content.replaceFirst('﻿', ''));
  if (rows.isEmpty) {
    result.warnings.add('${file.name}: empty file');
    return result;
  }
  final header = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
  int? col(List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    return null;
  }

  final dateCol = col(['date', 'transaction date', 'posted date']);
  final amountCol = col(['amount', 'amount (\$)']);
  if (dateCol == null || amountCol == null) {
    result.warnings.add('${file.name}: needs "Date" and "Amount" columns');
    return result;
  }
  final typeCol = col(['type', 'kind']);
  final categoryCol = col(['category', 'source']);
  final merchantCol = col(['merchant', 'description', 'payee', 'name']);
  final notesCol = col(['notes', 'memo', 'note']);

  String cell(List<dynamic> row, int? i) => i == null || i >= row.length ? '' : row[i].toString().trim();

  await db.transaction(() async {
    final resolver = _Resolver(db, result);
    await resolver.load();
    final existing = await _existingIds(db);
    final seenInFile = <String, int>{};

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      final date = _parseDate(cell(row, dateCol));
      final cents = parseCents(cell(row, amountCol));
      if (date == null || cents == null) {
        result.warnings.add('Row ${r + 1}: could not read date/amount');
        continue;
      }
      final typeText = cell(row, typeCol).toLowerCase();
      final kind = typeText.startsWith('inc') || typeText == 'credit'
          ? TxKind.income
          : typeText.startsWith('exp') || typeText == 'debit'
          ? TxKind.expense
          : (cents < 0 ? TxKind.expense : TxKind.income);

      // Identical rows within one file are legitimate (two coffees), so the
      // occurrence count is part of the key.
      final content = row.map((c) => c.toString().trim()).join('\u001f');
      final n = seenInFile.update(content, (v) => v + 1, ifAbsent: () => 0);
      final id = _importId('csv:$content#$n');
      if (existing.contains(id)) {
        result.skipped++;
        continue;
      }
      final category = await resolver.category(cell(row, categoryCol), kind);
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: Value(id),
              kind: kind,
              amountCents: cents.abs(),
              date: date,
              categoryId: category.id,
              merchant: Value(_nullIfBlank(cell(row, merchantCol))),
              notes: Value(_nullIfBlank(cell(row, notesCol))),
            ),
          );
      existing.add(id);
      result.added++;
    }
  });
  return result;
}

/// Reads an imported `YYYY-MM-DD…` or `M/D/YY(YY)` date as `YYYY-MM-DD`, or
/// null if it isn't a real calendar date. (`DateTime` alone would quietly
/// turn Feb 30 into Mar 2, or month 13 into next January.)
String? _parseDate(String s) {
  final int year, month, day;
  if (RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s) case final iso?) {
    (year, month, day) = (int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  } else if (RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})').firstMatch(s) case final us?) {
    final y = int.parse(us[3]!);
    (year, month, day) = (y < 100 ? y + 2000 : y, int.parse(us[1]!), int.parse(us[2]!));
  } else {
    return null;
  }
  final date = DateTime(year, month, day);
  return date.month == month && date.day == day ? ymd(date) : null;
}

String? _nullIfBlank(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty || t == 'null' ? null : t;
}
