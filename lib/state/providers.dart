import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dates.dart';
import '../data/database.dart';
import '../domain/analytics.dart';

/// Overridden in `main()` once the database is open.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

/// Overridden in `main()` with the loaded preferences.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final groupsProvider = StreamProvider<List<CategoryGroup>>((ref) => ref.watch(databaseProvider).watchGroups());

final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(databaseProvider).watchCategories());

final categoryMapProvider = Provider<Map<String, Category>>((ref) {
  final list = ref.watch(categoriesProvider).value ?? const [];
  return {for (final c in list) c.id: c};
});

final recurringProvider = StreamProvider<List<RecurringSeries>>((ref) => ref.watch(databaseProvider).watchRecurring());

/// Years that have transactions, newest first, always including this year.
final yearsProvider = StreamProvider<List<int>>((ref) {
  final current = DateTime.now().year;
  return ref.watch(databaseProvider).watchYears().map((years) => ({current, ...years}.toList()..sort((a, b) => b - a)));
});

/// Transactions in an inclusive `YYYY-MM-DD` range; null bounds are open.
final transactionsProvider = StreamProvider.family<List<Txn>, ({String? from, String? to})>(
  (ref, range) => ref.watch(databaseProvider).watchTransactions(from: range.from, to: range.to),
);

/// Merchants (or income sources) used before, most used first, for the
/// merchant field's suggestions. A null category means every category.
final merchantSuggestionsProvider = StreamProvider.autoDispose
    .family<List<String>, ({TxKind kind, String? categoryId})>(
      (ref, arg) => ref.watch(databaseProvider).watchMerchants(kind: arg.kind, categoryId: arg.categoryId),
    );

({String from, String to}) yearRange(int year) => (from: '$year-01-01', to: '$year-12-31');

({String from, String to}) monthRange(int year, int month) =>
    (from: '${monthKey(year, month)}-01', to: '${monthKey(year, month)}-${daysInMonth(year, month)}');

final yearSummaryProvider = Provider.family<AsyncValue<PeriodSummary>, int>((ref, year) {
  final categories = ref.watch(categoryMapProvider);
  return ref.watch(transactionsProvider(yearRange(year))).whenData((t) => summarize(t, categories));
});
