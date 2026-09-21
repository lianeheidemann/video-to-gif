import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'themeMode';

/// Modo de tema atual do app (claro ou escuro). Carregado por [loadThemeMode]
/// antes do primeiro frame e alterado por [toggleThemeMode].
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

/// Carrega a preferência salva (ou o brightness atual do sistema, se ainda
/// não houver nenhuma) em [themeModeNotifier]. Deve ser chamada antes de
/// `runApp` para o primeiro frame já nascer no tema correto.
Future<void> loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_themeModeKey);

  if (saved == 'dark') {
    themeModeNotifier.value = ThemeMode.dark;
  } else if (saved == 'light') {
    themeModeNotifier.value = ThemeMode.light;
  } else {
    final systemBrightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    themeModeNotifier.value = systemBrightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
  }
}

/// Alterna entre claro e escuro e salva a nova preferência.
Future<void> toggleThemeMode() async {
  final newMode = themeModeNotifier.value == ThemeMode.dark
      ? ThemeMode.light
      : ThemeMode.dark;
  themeModeNotifier.value = newMode;

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _themeModeKey,
    newMode == ThemeMode.dark ? 'dark' : 'light',
  );
}
