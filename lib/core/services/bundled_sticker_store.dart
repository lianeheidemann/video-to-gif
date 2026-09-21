import 'bundled_assets.dart';

/// Todo SVG empacotado em `assets/sticker`, incluindo subpastas.
///
/// Preenchido no `main()`. A tela da montagem cruza esta lista com os nomes
/// curados que ela já tinha: sticker conhecido mantém o nome escolhido a
/// dedo ("Joinha", "Coração"), e o que for solto na pasta depois aparece
/// sozinho, com o nome tirado do arquivo.
var bundledStickerAssets = const <String>[];

Future<List<String>> loadBundledStickerAssets() =>
    BundledAssets.list('assets/sticker/', extensions: {'svg'});
