import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _kSettingsBox = 'settings';
const _kThemeModeKey = 'themeMode';

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final box = Hive.box<dynamic>(_kSettingsBox);
    final raw = box.get(_kThemeModeKey) as String?;
    return _decode(raw);
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    final box = Hive.box<dynamic>(_kSettingsBox);
    final s = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    box.put(_kThemeModeKey, s);
  }

  static ThemeMode _decode(String? v) {
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
