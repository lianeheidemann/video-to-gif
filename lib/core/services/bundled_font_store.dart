import 'package:flutter/services.dart';

import 'bundled_assets.dart';

/// Uma fonte que veio empacotada em `assets/fonts`.
class BundledFont {
  const BundledFont({required this.family, required this.label});

  final String family;
  final String label;
}

/// Descobre e registra as fontes de `assets/fonts` ao abrir o app.
///
/// Antes as fontes eram declaradas uma a uma no `pubspec.yaml` e repetidas
/// numa lista fixa no código: soltar um `.ttf` na pasta não fazia nada, nem
/// entrava no APK. Agora a pasta inteira é empacotada e lida aqui, e o nome
/// da família sai do nome do arquivo — `PlayfairDisplay-Regular.ttf` vira a
/// família "Playfair Display", igual ao que era declarado à mão.
///
/// O registro usa [FontLoader], o mesmo caminho que [ImportedFontStore] já
/// usa para fonte que o usuário traz do aparelho.
class BundledFontStore {
  const BundledFontStore();

  static const _directory = 'assets/fonts/';
  static const _extensions = {'ttf', 'otf'};

  /// Sufixos de peso/estilo que não fazem parte do nome da família.
  static final _weightSuffix = RegExp(
    r'[ ](regular|book|normal)$',
    caseSensitive: false,
  );

  /// Carrega todas as fontes da pasta e devolve as que o engine aceitou, em
  /// ordem alfabética. Uma fonte ilegível é pulada sem derrubar as outras:
  /// um arquivo quebrado na pasta não pode tirar as demais do app.
  Future<List<BundledFont>> loadAll() async {
    final paths = await BundledAssets.list(_directory, extensions: _extensions);

    final fonts = <BundledFont>[];
    for (final path in paths) {
      final family = familyOf(path);
      if (fonts.any((f) => f.family == family)) continue;
      if (await _register(family, path)) {
        fonts.add(BundledFont(family: family, label: family));
      }
    }
    return fonts;
  }

  /// Nome da família a partir do arquivo, sem o sufixo de peso: de
  /// `assets/fonts/BebasNeue-Regular.ttf` sai "Bebas Neue".
  static String familyOf(String assetPath) =>
      labelFromFileName(assetPath).replaceFirst(_weightSuffix, '').trim();

  /// `false` quando o engine não soube ler o arquivo. Não dá para
  /// "desregistrar" uma família depois, então validar é registrar — mesma
  /// abordagem de `ImportedFontStore._register`.
  Future<bool> _register(String family, String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final loader = FontLoader(family)..addFont(Future.value(data));
      await loader.load();
      return true;
    } catch (_) {
      return false;
    }
  }
}
