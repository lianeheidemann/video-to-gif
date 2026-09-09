import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Erro ao importar uma fonte própria — mensagem já pronta em português para
/// mostrar ao usuário, mesmo padrão de `ImportedAssetException`.
class ImportedFontException implements Exception {
  ImportedFontException(this.message);

  final String message;

  @override
  String toString() => 'ImportedFontException: $message';
}

/// Uma fonte (.ttf/.otf) que o usuário trouxe do aparelho, já copiada para a
/// pasta de dados do app.
class ImportedFont {
  const ImportedFont({
    required this.id,
    required this.family,
    required this.label,
    required this.filePath,
  });

  final String id;

  /// Nome de família com que a fonte é registrada no engine — inventado aqui
  /// a partir do carimbo de tempo (e não lido do arquivo) para nunca colidir
  /// com as fontes embutidas nem com outra fonte importada de mesmo nome.
  /// É esse nome que vai parar em `CollageTextItem.fontFamily`.
  final String family;

  /// Nome do arquivo, mostrado na folha de fontes.
  final String label;

  final String filePath;
}

/// Importa, registra e persiste fontes próprias. O registro no engine
/// (`FontLoader`) vale só enquanto o app está rodando, então
/// [loadAll] registra tudo de novo a cada abertura — é por isso que ele é
/// chamado no `initState` da tela de montagem, junto dos outros importados.
///
/// Uma fonte registrada assim serve tanto à prévia quanto à exportação: as
/// duas desenham com `TextStyle(fontFamily: …)` no mesmo engine.
class ImportedFontStore {
  const ImportedFontStore();

  static const _prefsKey = 'importedFonts';

  Future<ImportedFont> import() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
      dialogTitle: 'Escolha um arquivo de fonte',
    );
    final path = picked?.path;
    if (path == null) {
      throw ImportedFontException('Nenhum arquivo selecionado.');
    }

    final supportDir = await getApplicationSupportDirectory();
    final fontsDir = Directory('${supportDir.path}/imported_fonts');
    await fontsDir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.toLowerCase().endsWith('.otf') ? 'otf' : 'ttf';
    final destPath = '${fontsDir.path}/$stamp.$extension';
    await File(path).copy(destPath);

    final rawLabel = picked!.name;
    final dot = rawLabel.lastIndexOf('.');
    final label = (dot > 0 ? rawLabel.substring(0, dot) : rawLabel).trim();

    final font = ImportedFont(
      id: 'font_$stamp',
      family: 'ImportedFont$stamp',
      label: label.isEmpty ? 'Fonte importada' : label,
      filePath: destPath,
    );

    // Registra antes de persistir: um arquivo que o engine não aceita não
    // pode virar uma opção quebrada na lista de fontes.
    final registered = await _register(font);
    if (!registered) {
      await File(destPath).delete();
      throw ImportedFontException(
        'Não foi possível ler este arquivo como fonte.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    await prefs.setStringList(_prefsKey, [...raw, _encode(font)]);
    return font;
  }

  /// Carrega as fontes guardadas e registra cada uma no engine. Entradas cujo
  /// arquivo sumiu — ou que o engine recusa — ficam de fora em vez de
  /// derrubar a lista inteira.
  Future<List<ImportedFont>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final fonts = <ImportedFont>[];
    for (final entry in raw) {
      final font = _decode(entry);
      if (font == null) continue;
      if (!File(font.filePath).existsSync()) continue;
      if (!await _register(font)) continue;
      fonts.add(font);
    }
    return fonts;
  }

  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final kept = <String>[];
    for (final entry in raw) {
      final font = _decode(entry);
      if (font != null && font.id == id) {
        final file = File(font.filePath);
        if (file.existsSync()) await file.delete();
        continue;
      }
      kept.add(entry);
    }
    await prefs.setStringList(_prefsKey, kept);
  }

  /// `false` quando o arquivo não é uma fonte que o engine saiba ler. Não há
  /// como "desregistrar" uma família depois — por isso a validação é feita
  /// justamente registrando.
  Future<bool> _register(ImportedFont font) async {
    try {
      final bytes = await File(font.filePath).readAsBytes();
      final loader = FontLoader(font.family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _encode(ImportedFont font) => jsonEncode({
    'id': font.id,
    'family': font.family,
    'label': font.label,
    'filePath': font.filePath,
  });

  ImportedFont? _decode(String entry) {
    try {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return ImportedFont(
        id: map['id'] as String,
        family: map['family'] as String,
        label: map['label'] as String,
        filePath: map['filePath'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
