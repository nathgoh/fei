import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generates a time-ordered UUID (v7) so rows created on different devices
/// never collide and sort roughly by creation time once synced.
String newId() => _uuid.v7();

/// Columns every synced table carries.
///
/// * `id` is a client-generated UUID, so rows can be created offline.
/// * `updatedAt` is bumped on every write; the future sync pushes rows whose
///   `updatedAt` is newer than the last successful push.
/// * `deletedAt` makes deletes soft, so they can propagate to the server.
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now().toUtc())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now().toUtc())();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Whether money flows in or out. Stored as text ('income' / 'expense').
enum TxKind { income, expense }

/// How often a recurring series repeats.
enum Frequency { weekly, biweekly, monthly, quarterly, yearly }

@DataClassName('CategoryGroup')
class CategoryGroups extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<TxKind>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DataClassName('Category')
class Categories extends Table with SyncColumns {
  TextColumn get groupId => text().references(CategoryGroups, #id)();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<TxKind>()();
  TextColumn get emoji => text().withDefault(const Constant('🏷️'))();

  /// ARGB colour used in charts.
  IntColumn get color => integer().withDefault(const Constant(0xFF888888))();

  /// Fixed costs (e.g. rent) are excluded from "flexible" spending and the
  /// "average excluding fixed" figures, like Rent was in the web app.
  BoolColumn get isFixed => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// A rule that materialises transactions on a schedule.
///
/// Occurrences are generated up to today (never into the future), and
/// `generatedThrough` records the last date generated so deleting one
/// occurrence doesn't make it come back.
@DataClassName('RecurringSeries')
class RecurringSeriesTable extends Table with SyncColumns {
  @override
  String get tableName => 'recurring_series';

  TextColumn get kind => textEnum<TxKind>()();
  IntColumn get amountCents => integer()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get merchant => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get frequency => textEnum<Frequency>()();

  /// Calendar dates as `YYYY-MM-DD`.
  TextColumn get startDate => text()();
  TextColumn get endDate => text().nullable()();
  TextColumn get generatedThrough => text().nullable()();
}

@DataClassName('Txn')
@TableIndex(name: 'idx_transactions_date', columns: {#date})
class Transactions extends Table with SyncColumns {
  TextColumn get kind => textEnum<TxKind>()();

  /// Always positive; [kind] says which direction the money moved.
  IntColumn get amountCents => integer()();

  /// Calendar date as `YYYY-MM-DD` (lexically sortable, maps to SQL DATE).
  TextColumn get date => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get merchant => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get recurringId => text().nullable().references(RecurringSeriesTable, #id)();
}
