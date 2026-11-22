import 'package:drift/drift.dart';

import 'database.dart';

class SeedCategory {
  const SeedCategory(this.name, this.emoji, this.color, {this.isFixed = false});
  final String name;
  final String emoji;
  final int color;
  final bool isFixed;
}

class SeedGroup {
  const SeedGroup(this.name, this.kind, this.categories);
  final String name;
  final TxKind kind;
  final List<SeedCategory> categories;
}

/// Defaults mirror the web app's categories and chart colors, organised into
/// Monarch-style groups.
const defaultGroups = [
  SeedGroup('Income', TxKind.income, [
    SeedCategory('Paycheck', '💰', 0xFF2E7D32),
    SeedCategory('Interest', '🏦', 0xFF66BB6A),
    SeedCategory('Other Income', '💵', 0xFF81C784),
  ]),
  SeedGroup('Housing', TxKind.expense, [
    SeedCategory('Rent', '🏠', 0xFFFF6384, isFixed: true),
    SeedCategory('Home', '🛋️', 0xFF009EFF),
    SeedCategory('Utility', '💡', 0xFFB0BEC5),
  ]),
  SeedGroup('Food & Drink', TxKind.expense, [
    SeedCategory('Grocery', '🛒', 0xFF11734B),
    SeedCategory('Food & Dining', '🍽️', 0xFFFFB900),
  ]),
  SeedGroup('Lifestyle', TxKind.expense, [
    SeedCategory('Personal', '🧍', 0xFF215A6C),
    SeedCategory('Entertainment', '🎬', 0xFFF93380),
    SeedCategory('Health', '🩺', 0xFFB10202),
    SeedCategory('Travel', '✈️', 0xFFD97E00),
  ]),
  SeedGroup('Transportation', TxKind.expense, [SeedCategory('Transportation', '🚗', 0xFFFD8D50)]),
  SeedGroup('Other', TxKind.expense, [SeedCategory('Miscellaneous', '📦', 0xFF5A3286)]),
];

/// Looks up a default's styling by (case-insensitive) name, used when
/// importing categories from the web app.
SeedCategory? defaultCategoryNamed(String name) {
  final wanted = name.trim().toLowerCase();
  for (final g in defaultGroups) {
    for (final c in g.categories) {
      if (c.name.toLowerCase() == wanted) return c;
    }
  }
  return null;
}

Future<void> seedDefaults(AppDatabase db) async {
  var groupOrder = 0;
  var categoryOrder = 0;
  for (final g in defaultGroups) {
    final groupId = newId();
    await db
        .into(db.categoryGroups)
        .insert(
          CategoryGroupsCompanion.insert(
            id: Value(groupId),
            name: g.name,
            kind: g.kind,
            sortOrder: Value(groupOrder++),
          ),
        );
    for (final c in g.categories) {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              groupId: groupId,
              name: c.name,
              kind: g.kind,
              emoji: Value(c.emoji),
              color: Value(c.color),
              isFixed: Value(c.isFixed),
              sortOrder: Value(categoryOrder++),
            ),
          );
    }
  }
}
