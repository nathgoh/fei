import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme.dart';
import 'providers.dart';

/// Device-local look-and-feel preferences (not synced).
class Appearance {
  const Appearance({this.accent = defaultAccent, this.theme = ThemeStyle.tinted});
  final Color accent;
  final ThemeStyle theme;

  Appearance copyWith({Color? accent, ThemeStyle? theme}) =>
      Appearance(accent: accent ?? this.accent, theme: theme ?? this.theme);
}

class AppearanceNotifier extends Notifier<Appearance> {
  static const _accentKey = 'appearance.accent';
  // Named for the old "Background" setting; kept so saved choices survive.
  static const _themeKey = 'appearance.background';

  @override
  Appearance build() {
    final prefs = ref.watch(prefsProvider);
    final accent = prefs.getInt(_accentKey);
    final theme = ThemeStyle.values.firstWhereOrNull((t) => t.name == prefs.getString(_themeKey));
    return Appearance(accent: accent == null ? defaultAccent : Color(accent), theme: theme ?? ThemeStyle.tinted);
  }

  Future<void> setAccent(Color color) async {
    state = state.copyWith(accent: color);
    await ref.read(prefsProvider).setInt(_accentKey, color.toARGB32());
  }

  Future<void> setTheme(ThemeStyle theme) async {
    state = state.copyWith(theme: theme);
    await ref.read(prefsProvider).setString(_themeKey, theme.name);
  }

  Future<void> reset() async {
    state = const Appearance();
    final prefs = ref.read(prefsProvider);
    await prefs.remove(_accentKey);
    await prefs.remove(_themeKey);
  }
}

final appearanceProvider = NotifierProvider<AppearanceNotifier, Appearance>(AppearanceNotifier.new);
