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

  // Add any recurring occurrences that came due while the app was closed.
  await db.materializeRecurring();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), prefsProvider.overrideWithValue(prefs)],
      child: const _Lifecycle(child: FeiApp()),
    ),
  );
}

/// Re-runs recurring generation when the app returns to the foreground, so a
/// long-lived session still picks up new occurrences each day.
class _Lifecycle extends ConsumerStatefulWidget {
  const _Lifecycle({required this.child});
  final Widget child;

  @override
  ConsumerState<_Lifecycle> createState() => _LifecycleState();
}

class _LifecycleState extends ConsumerState<_Lifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(databaseProvider).materializeRecurring();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
