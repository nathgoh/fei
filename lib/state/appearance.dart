import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme.dart';
import 'providers.dart';

/// Device-local look-and-feel preferences (not synced).
class Appearance {
  const Appearance({this.accent = defaultAccent, this.background = BackgroundStyle.tinted});
  final Color accent;
  final BackgroundStyle background;

  Appearance copyWith({Color? accent, BackgroundStyle? background}) =>
      Appearance(accent: accent ?? this.accent, background: background ?? this.background);
}

class AppearanceNotifier extends Notifier<Appearance> {
  static const _accentKey = 'appearance.accent';
  static const _backgroundKey = 'appearance.background';

  @override
  Appearance build() {
    final prefs = ref.watch(prefsProvider);
    final accent = prefs.getInt(_accentKey);
    final background = BackgroundStyle.values.firstWhereOrNull((b) => b.name == prefs.getString(_backgroundKey));
    return Appearance(
      accent: accent == null ? defaultAccent : Color(accent),
      background: background ?? BackgroundStyle.tinted,
    );
  }

  Future<void> setAccent(Color color) async {
    state = state.copyWith(accent: color);
    await ref.read(prefsProvider).setInt(_accentKey, color.toARGB32());
  }

  Future<void> setBackground(BackgroundStyle background) async {
    state = state.copyWith(background: background);
    await ref.read(prefsProvider).setString(_backgroundKey, background.name);
  }

  Future<void> reset() async {
    state = const Appearance();
    final prefs = ref.read(prefsProvider);
    await prefs.remove(_accentKey);
    await prefs.remove(_backgroundKey);
  }
}

final appearanceProvider = NotifierProvider<AppearanceNotifier, Appearance>(AppearanceNotifier.new);
