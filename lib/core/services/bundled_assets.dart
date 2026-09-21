import 'package:flutter/services.dart';

/// Lê o que foi empacotado no APK, para o app montar as listas de fontes,
/// stickers e molduras a partir das pastas em vez de uma lista fixa no
/// código.
///
/// Soltar um arquivo em `assets/fonts`, `assets/sticker` ou `assets/frame` e
/// gerar o APK passa a bastar: o arquivo aparece no app sem precisar editar
/// nada. O que ainda precisa de um passo manual é uma **subpasta** nova, que
/// o `pubspec.yaml` tem que declarar para o arquivo entrar no APK — daí o
/// `tool/sincronizar_assets.py`, que o CI confere a cada push.
class BundledAssets {
  const BundledAssets._();

  /// Caminhos empacotados dentro de [directory] (com barra no fim), filtrados
  /// por extensão e em ordem alfabética, que é a ordem em que aparecem na
  /// interface. Subpastas entram também.
  static Future<List<String>> list(
    String directory, {
    required Set<String> extensions,
  }) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths =
        manifest
            .listAssets()
            .where(
              (path) =>
                  path.startsWith(directory) &&
                  extensions.contains(_extensionOf(path)),
            )
            .toList()
          ..sort();
    return paths;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }
}

/// Nome de exibição derivado do nome do arquivo, para o que foi solto numa
/// pasta sem passar por uma lista curada.
///
/// Tira a pasta e a extensão, descarta um prefixo só de dígitos (os stickers
/// do GitHub usam `01-`, `10-` etc. para ordenar), troca `_`, `-` e `.` por
/// espaço, separa palavras grudadas em maiúscula (`PlayfairDisplay` vira
/// `Playfair Display`) e deixa a primeira letra maiúscula.
String labelFromFileName(String path) {
  var name = path.split('/').last;

  // `>= 0` e não `> 0`: um arquivo oculto como `.svg` é só extensão, e
  // sobraria o rótulo "Svg" se o ponto na posição 0 fosse ignorado.
  final dot = name.lastIndexOf('.');
  if (dot >= 0) name = name.substring(0, dot);

  name = name.replaceFirst(RegExp(r'^\d+[-_]'), '');
  name = name.replaceAll(RegExp(r'[_\-.]+'), ' ');
  // Só onde uma minúscula (ou dígito) encosta numa maiúscula: sem isto,
  // "GitHub" viraria "Git Hub".
  name = name.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (name.isEmpty) return 'Sem nome';
  return name[0].toUpperCase() + name.substring(1);
}
