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
  final wanted = name.toLowerCase();
  for (final g in defaultGroups) {
    for (final c in g.categories) {
      if (c.name.toLowerCase() == wanted) return c;
    }
  }
  return null;
}

Future<void> seedDefaults(AppDatabase db) async {
  for (final g in defaultGroups) {
    final groupId = await db.addGroup(g.name, g.kind);
    for (final c in g.categories) {
      await db.addCategory(
        name: c.name,
        groupId: groupId,
        kind: g.kind,
        emoji: c.emoji,
        color: c.color,
        isFixed: c.isFixed,
      );
    }
  }
}
