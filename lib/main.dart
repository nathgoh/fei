import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/database.dart';
import 'state/providers.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final prefs = await SharedPreferences.getInstance();

  // Add any recurring occurrences that came due while the app was closed, and
  // again on each return to the foreground so a long-lived session keeps up.
  await db.materializeRecurring();
  AppLifecycleListener(onResume: () => db.materializeRecurring());

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), prefsProvider.overrideWithValue(prefs)],
      child: const FeiApp(),
    ),
  );
}
