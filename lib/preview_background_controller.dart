import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _previewCheckerboardKey = 'previewCheckerboardEnabled';

/// Liga um fundo quadriculado (indicador universal de transparência, como em
/// editores de imagem) atrás da prévia nas três telas de edição (vídeo, foto
/// e montagem), no lugar da cor de fundo padrão do tema — preferência global,
/// a mesma nas três telas. Carregado por [loadPreviewCheckerboardPreference]
/// antes do primeiro frame, mesmo padrão de `theme_controller.dart`.
final ValueNotifier<bool> previewCheckerboardNotifier = ValueNotifier(false);

/// Carrega a preferência salva (ou `false`, se ainda não houver nenhuma) em
/// [previewCheckerboardNotifier]. Deve ser chamada antes de `runApp`.
Future<void> loadPreviewCheckerboardPreference() async {
  final prefs = await SharedPreferences.getInstance();
  previewCheckerboardNotifier.value =
      prefs.getBool(_previewCheckerboardKey) ?? false;
}

/// Liga/desliga o fundo quadriculado e salva a nova preferência.
Future<void> setPreviewCheckerboardEnabled(bool enabled) async {
  previewCheckerboardNotifier.value = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_previewCheckerboardKey, enabled);
}
