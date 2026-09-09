import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Uma pasta de stickers criada pelo usuário na aba "Stickers", ao lado das
/// embutidas ("Reações", "Símbolos", "Efeitos") e de "Importados". Guarda só
/// o nome: quais stickers estão dentro dela é decidido pelo `folderId` de
/// cada `ImportedAsset`, não por uma lista aqui — assim importar ou remover
/// um sticker não precisa mexer em dois lugares.
class StickerFolder {
  const StickerFolder({required this.id, required this.name});

  final String id;
  final String name;
}

/// Persiste as pastas criadas pelo usuário em `SharedPreferences`, no mesmo
/// padrão de `ImportedAssetStore` (lista de JSON, decodificação tolerante a
/// entrada estragada — uma linha inválida some em vez de derrubar a lista
/// inteira).
class StickerFolderStore {
  const StickerFolderStore();

  static const _prefsKey = 'stickerFolders';

  Future<List<StickerFolder>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final folders = <StickerFolder>[];
    for (final entry in raw) {
      final folder = _decode(entry);
      if (folder == null) continue;
      folders.add(folder);
    }
    return folders;
  }

  /// Cria a pasta no fim da lista e devolve o que foi gravado. O id leva o
  /// prefixo `f_` para nunca colidir com os ids das pastas embutidas, que são
  /// os próprios nomes do enum (`reactions`, `imported`, …).
  Future<StickerFolder> create(String name) async {
    final folder = StickerFolder(
      id: 'f_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Nova pasta' : name.trim(),
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    await prefs.setStringList(_prefsKey, [...raw, _encode(folder)]);
    return folder;
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final updated = <String>[];
    for (final entry in raw) {
      final folder = _decode(entry);
      if (folder == null) continue;
      updated.add(
        folder.id == id
            ? _encode(StickerFolder(id: folder.id, name: trimmed))
            : entry,
      );
    }
    await prefs.setStringList(_prefsKey, updated);
  }

  /// Só apaga a pasta. Os stickers que estavam nela continuam existindo —
  /// quem os devolve para "Importados" é
  /// `ImportedAssetStore.moveFolderToRoot`, chamado junto.
  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final kept = <String>[];
    for (final entry in raw) {
      final folder = _decode(entry);
      if (folder == null || folder.id == id) continue;
      kept.add(entry);
    }
    await prefs.setStringList(_prefsKey, kept);
  }

  String _encode(StickerFolder folder) =>
      jsonEncode({'id': folder.id, 'name': folder.name});

  StickerFolder? _decode(String entry) {
    try {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return StickerFolder(
        id: map['id'] as String,
        name: map['name'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
