import '../../../core/services/bundled_assets.dart';
import '../../../core/services/bundled_sticker_store.dart';

/// Pastas da seção "Stickers": as temáticas com os stickers embutidos do
/// app, mais "Importados" para os que o usuário trouxe do aparelho.
///
/// "Black" ainda não tem sticker embutido — a arte vem depois —, então por
/// enquanto ela vale como pasta de importados: o botão "Importar" aparece
/// dentro e o que entrar ali fica marcado com o id dela. "GitHub" tem arte
/// embutida e também aceita importados.
enum BundledStickerFolder {
  reactions,
  symbols,
  effects,
  github,
  black,
  novos,
  imported,
}

extension BundledStickerFolderInfo on BundledStickerFolder {
  /// `true` nas pastas que recebem stickers importados — "Importados" e as
  /// que ainda estão sem arte embutida.
  bool get acceptsImports =>
      this == BundledStickerFolder.imported ||
      this == BundledStickerFolder.github ||
      this == BundledStickerFolder.black;

  /// Id da pasta embutida na barra — o próprio nome do enum. As pastas
  /// criadas pelo usuário usam ids com prefixo `f_` (ver
  /// `StickerFolderStore.create`), então os dois conjuntos convivem na mesma
  /// barra sem risco de colisão.
  String get id => name;

  String get label => switch (this) {
    BundledStickerFolder.reactions => 'Reações',
    BundledStickerFolder.symbols => 'Símbolos',
    BundledStickerFolder.effects => 'Efeitos',
    BundledStickerFolder.github => 'GitHub',
    BundledStickerFolder.black => 'Black',
    BundledStickerFolder.novos => 'Novos',
    BundledStickerFolder.imported => 'Importados',
  };
}

/// Tela do editor de montagem de fotos: agrupa [photos] num layout (linha,
/// coluna ou grade), com margem/proporção/borda/cantos configuráveis (da
/// montagem inteira e de cada foto), fundo transparente/cor/imagem, stickers
/// e texto sobrepostos, reposicionamento/rotação/zoom por toque de cada
/// foto, recorte de uma foto específica e opções de trocar/substituir/
/// ajustar cor/espelhar/recentralizar cada célula. Prévia fixa em cima,
/// abas de edição fixas no rodapé (estilo CapCut/Canva).

/// Stickers prontos, embutidos no app (`assets/sticker/`), agrupados por
/// pasta temática na seção "Stickers" — ver [BundledStickerFolder].
const _stickerFolderReactions = <(String path, String label)>[
  ('assets/sticker/thumbs_up.svg', 'Joinha'),
  ('assets/sticker/thumbs_down.svg', 'Joinha para baixo'),
  ('assets/sticker/smiley.svg', 'Sorriso'),
  ('assets/sticker/laughing.svg', 'Risada'),
  ('assets/sticker/surprised.svg', 'Surpresa'),
  ('assets/sticker/sad.svg', 'Triste'),
];
const _stickerFolderSymbols = <(String path, String label)>[
  ('assets/sticker/heart.svg', 'Coração'),
  ('assets/sticker/star.svg', 'Estrela'),
  ('assets/sticker/lightning.svg', 'Raio'),
  ('assets/sticker/sun.svg', 'Sol'),
  ('assets/sticker/moon.svg', 'Lua'),
  ('assets/sticker/check.svg', 'Confirmado'),
];
const _stickerFolderEffects = <(String path, String label)>[
  ('assets/sticker/sparkle.svg', 'Brilho'),
  ('assets/sticker/boom.svg', 'Explosão'),
  ('assets/sticker/confetti.svg', 'Confete'),
  ('assets/sticker/whoosh.svg', 'Rastro de velocidade'),
  ('assets/sticker/rainbow.svg', 'Arco-íris'),
];

/// Pasta "GitHub": arte enviada pela Liane, guardada em
/// `assets/sticker/github/`. Os nomes de arquivo começam com um número
/// que define a ordem em que aparecem na fileira.
const _stickerFolderGithub = <(String path, String label)>[
  ('assets/sticker/github/01-robot-android.svg', 'Robô Android'),
  ('assets/sticker/github/10-wordmark-github-bold.svg', 'Marca GitHub negrito'),
  (
    'assets/sticker/github/11-wordmark-github-compact.svg',
    'Marca GitHub compacto',
  ),
  ('assets/sticker/github/20-octocat-colorido.svg', 'Octocat colorido'),
  ('assets/sticker/github/21-octopus-com-bigodes.svg', 'Polvo com bigodes'),
  ('assets/sticker/github/22-octopus-silhueta.svg', 'Polvo silhueta'),
  (
    'assets/sticker/github/23-octopus-silhueta-pernas.svg',
    'Polvo silhueta pernas',
  ),
  (
    'assets/sticker/github/24-octopus-contorno-grosso.svg',
    'Polvo contorno grosso',
  ),
  (
    'assets/sticker/github/25-octopus-contorno-duotone.svg',
    'Polvo contorno duotone',
  ),
  ('assets/sticker/github/26-octopus-contorno-fino.svg', 'Polvo contorno fino'),
  ('assets/sticker/github/30-gato-contorno-fino.svg', 'Gato contorno fino'),
  ('assets/sticker/github/31-gato-contorno-medio.svg', 'Gato contorno médio'),
  ('assets/sticker/github/32-gato-contorno-grosso.svg', 'Gato contorno grosso'),
  (
    'assets/sticker/github/33-gato-silhueta-azul-marinho.svg',
    'Gato silhueta azul marinho',
  ),
  (
    'assets/sticker/github/40-gato-circulo-contorno.svg',
    'Gato círculo contorno',
  ),
  (
    'assets/sticker/github/41-gato-circulo-preto-grande.svg',
    'Gato círculo preto grande',
  ),
  (
    'assets/sticker/github/42-gato-circulo-preto-medio.svg',
    'Gato círculo preto médio',
  ),
  (
    'assets/sticker/github/43-gato-circulo-preto-classico.svg',
    'Gato círculo preto clássico',
  ),
  (
    'assets/sticker/github/44-gato-circulo-preto-pequeno.svg',
    'Gato círculo preto pequeno',
  ),
  (
    'assets/sticker/github/45-gato-circulo-preto-cauda.svg',
    'Gato círculo preto cauda',
  ),
  (
    'assets/sticker/github/46-gato-circulo-preto-logo.svg',
    'Gato círculo preto logo',
  ),
  (
    'assets/sticker/github/47-gato-circulo-preto-sticker.svg',
    'Gato círculo preto sticker',
  ),
  ('assets/sticker/github/48-gato-circulo-azul.svg', 'Gato círculo azul'),
  (
    'assets/sticker/github/49-gato-circulo-azul-cinza.svg',
    'Gato círculo azul cinza',
  ),
  (
    'assets/sticker/github/50-gato-circulo-azul-petroleo.svg',
    'Gato círculo azul petróleo',
  ),
  (
    'assets/sticker/github/51-gato-circulo-azul-degrade.svg',
    'Gato círculo azul degradê',
  ),
  (
    'assets/sticker/github/60-gato-oval-contorno-fino.svg',
    'Gato oval contorno fino',
  ),
  (
    'assets/sticker/github/61-gato-oval-contorno-preenchido.svg',
    'Gato oval contorno preenchido',
  ),
  (
    'assets/sticker/github/62-gato-oval-contorno-grosso.svg',
    'Gato oval contorno grosso',
  ),
  ('assets/sticker/github/63-octopus-oval-contorno.svg', 'Polvo oval contorno'),
  ('assets/sticker/github/64-gato-oval-ciano.svg', 'Gato oval ciano'),
  (
    'assets/sticker/github/65-gato-oval-preto-pequeno.svg',
    'Gato oval preto pequeno',
  ),
  (
    'assets/sticker/github/70-gato-quadrado-arredondado-01.svg',
    'Gato quadrado arredondado',
  ),
  (
    'assets/sticker/github/71-gato-quadrado-arredondado-02.svg',
    'Gato quadrado arredondado 2',
  ),
  (
    'assets/sticker/github/72-gato-quadrado-arredondado-03.svg',
    'Gato quadrado arredondado 3',
  ),
  ('assets/sticker/github/73-gato-quadrado-reto.svg', 'Gato quadrado reto'),
  ('assets/sticker/github/74-gato-quadrado-duplo.svg', 'Gato quadrado duplo'),
  ('assets/sticker/github/80-gato-badge-cinza.svg', 'Gato selo cinza'),
];

/// Stickers embutidos da pasta [folder] — vazio para
/// [BundledStickerFolder.imported], que mostra os importados pelo usuário em vez
/// disso (ver [_stickersPanelContent]).
List<(String path, String label)> bundledStickersFor(
  BundledStickerFolder folder,
) {
  final curados = switch (folder) {
    BundledStickerFolder.reactions => _stickerFolderReactions,
    BundledStickerFolder.symbols => _stickerFolderSymbols,
    BundledStickerFolder.effects => _stickerFolderEffects,
    BundledStickerFolder.github => _stickerFolderGithub,
    // Sem arte embutida ainda: se comporta como pasta de importados até os
    // arquivos chegarem.
    BundledStickerFolder.black => const <(String, String)>[],
    BundledStickerFolder.novos => const <(String, String)>[],
    BundledStickerFolder.imported => const <(String, String)>[],
  };
  return [...curados, ...descobertosFor(folder)];
}

/// Todo caminho que aparece em alguma das listas curadas — o que estiver
/// fora daqui foi solto na pasta depois e entra por descoberta.
final Set<String> _curatedStickerPaths = {
  for (final lista in [
    _stickerFolderReactions,
    _stickerFolderSymbols,
    _stickerFolderEffects,
    _stickerFolderGithub,
  ])
    for (final (path, _) in lista) path,
};

/// Stickers achados em `assets/sticker` que nenhuma lista curada cita.
///
/// A pasta do arquivo decide onde ele aparece: `assets/sticker/github/` e
/// `assets/sticker/black/` caem nas abas de mesmo nome, e todo o resto vai
/// para "Novos" — inclusive arquivo solto na raiz e subpasta que ainda não
/// tem aba própria. Assim, soltar um SVG na pasta e gerar o APK basta para
/// ele aparecer, sem passar por aqui.
List<(String path, String label)> descobertosFor(BundledStickerFolder folder) {
  bool pertence(String path) => switch (folder) {
    BundledStickerFolder.github => path.startsWith('assets/sticker/github/'),
    BundledStickerFolder.black => path.startsWith('assets/sticker/black/'),
    BundledStickerFolder.novos =>
      !path.startsWith('assets/sticker/github/') &&
          !path.startsWith('assets/sticker/black/'),
    _ => false,
  };

  return [
    for (final path in bundledStickerAssets)
      if (!_curatedStickerPaths.contains(path) && pertence(path))
        (path, labelFromFileName(path)),
  ];
}
