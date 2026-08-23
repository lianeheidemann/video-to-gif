/// Retângulo fracionário (0..1) relativo ao tamanho da própria arte de uma
/// moldura de imagem — independe de `dart:ui`, no mesmo espírito minimalista
/// dos outros modelos deste diretório.
class NormalizedRect {
  const NormalizedRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}

/// De onde veio a arte de uma [ImageFrameAsset].
enum ImageFrameSource {
  /// Um dos SVGs empacotados com o app, em `assets/frame`.
  bundledSvg,

  /// Uma imagem escolhida pelo usuário na galeria, copiada para a pasta de
  /// dados do app.
  importedImage,
}

/// Uma moldura de imagem: um mockup (ex.: silhueta de celular) desenhado ao
/// redor do vídeo, com uma "janela" onde o conteúdo aparece. Ao contrário do
/// [FrameStyle] procedural, aqui a cor, a espessura, os cantos e a
/// transparência das quinas já vêm embutidos na própria arte — este modelo
/// só precisa saber onde fica a janela ([contentRect]) e a proporção nativa
/// da arte, para nunca distorcê-la.
class ImageFrameAsset {
  const ImageFrameAsset({
    required this.id,
    required this.label,
    required this.source,
    required this.contentRect,
    required this.nativeAspectRatio,
    required this.nativeReferenceWidth,
    this.svgAssetPath,
    this.imageFilePath,
  }) : assert(
         (source == ImageFrameSource.bundledSvg && svgAssetPath != null) ||
             (source == ImageFrameSource.importedImage &&
                 imageFilePath != null),
         'svgAssetPath é obrigatório para bundledSvg; '
         'imageFilePath é obrigatório para importedImage.',
       );

  /// Estável entre execuções para as artes empacotadas; gerado a partir do
  /// timestamp da importação para as artes do usuário.
  final String id;
  final String label;
  final ImageFrameSource source;

  /// Onde o vídeo deve aparecer, como fração do tamanho da própria arte.
  final NormalizedRect contentRect;

  /// Largura/altura nativa da arte — usada para nunca distorcê-la ao
  /// desenhar em qualquer tamanho de tela ou de exportação.
  final double nativeAspectRatio;

  /// Largura de referência (px) do canvas nativo/original da arte — o
  /// design canvas do SVG para artes empacotadas, ou a largura real do
  /// arquivo para PNGs importados. Usado por
  /// [ConversionSettings.imageFrameCanvasDimensions] quando
  /// [ImageFrameResolutionMode.nativeMax] está ativo, para gerar a moldura
  /// no maior tamanho nítido possível em vez de depender da resolução
  /// escolhida em "Ajustar".
  final int nativeReferenceWidth;

  /// Caminho do asset (`assets/frame/...`), quando [source] é [ImageFrameSource.bundledSvg].
  final String? svgAssetPath;

  /// Caminho absoluto do PNG copiado localmente, quando [source] é
  /// [ImageFrameSource.importedImage].
  final String? imageFilePath;
}

/// As molduras de imagem que vêm prontas com o app — SVGs em `assets/frame`
/// com uma janela de conteúdo transparente de verdade (geometria vetorial
/// com buraco, não apenas um traço), extraída manualmente de cada arquivo.
class ImageFrameLibrary {
  const ImageFrameLibrary._();

  static const bundled = <ImageFrameAsset>[
    ImageFrameAsset(
      id: 'bundled_transparente',
      label: 'Transparente',
      source: ImageFrameSource.bundledSvg,
      svgAssetPath: 'assets/frame/moldura-celular-transparente.svg',
      nativeAspectRatio: 760 / 1520,
      nativeReferenceWidth: 760,
      contentRect: NormalizedRect(0.1066, 0.0441, 0.7868, 0.9118),
    ),
    ImageFrameAsset(
      id: 'bundled_graphite',
      label: 'Grafite',
      source: ImageFrameSource.bundledSvg,
      svgAssetPath: 'assets/frame/moldura_01_graphite_dynamic_island.svg',
      nativeAspectRatio: 1080 / 1920,
      nativeReferenceWidth: 1080,
      contentRect: NormalizedRect(0.0935, 0.0302, 0.8130, 0.9396),
    ),
    ImageFrameAsset(
      id: 'bundled_titanio',
      label: 'Titânio',
      source: ImageFrameSource.bundledSvg,
      svgAssetPath: 'assets/frame/moldura_02_titanio_flat.svg',
      nativeAspectRatio: 1080 / 1920,
      nativeReferenceWidth: 1080,
      contentRect: NormalizedRect(0.0954, 0.0318, 0.8093, 0.9365),
    ),
    ImageFrameAsset(
      id: 'bundled_ceramica',
      label: 'Cerâmica',
      source: ImageFrameSource.bundledSvg,
      svgAssetPath: 'assets/frame/moldura_03_ceramica_branca.svg',
      nativeAspectRatio: 1080 / 1920,
      nativeReferenceWidth: 1080,
      contentRect: NormalizedRect(0.0944, 0.03125, 0.8111, 0.9375),
    ),
    ImageFrameAsset(
      id: 'bundled_neon',
      label: 'Neon Gamer',
      source: ImageFrameSource.bundledSvg,
      svgAssetPath: 'assets/frame/moldura_04_azul_neon_gamer.svg',
      nativeAspectRatio: 1080 / 1920,
      nativeReferenceWidth: 1080,
      // Cantos cortados na diagonal (octógono, não arredondado): retângulo
      // inscrito conservador, com margem extra contra o antialiasing do
      // corte — ver plano de implementação para a dedução dessa margem.
      contentRect: NormalizedRect(0.16, 0.075, 0.68, 0.85),
    ),
    ImageFrameAsset(
      id: 'bundled_rose_gold',
      label: 'Rose Gold',
      source: ImageFrameSource.bundledSvg,
      svgAssetPath: 'assets/frame/moldura_05_rose_gold_minimal.svg',
      nativeAspectRatio: 1080 / 1920,
      nativeReferenceWidth: 1080,
      contentRect: NormalizedRect(0.0935, 0.0318, 0.8130, 0.9365),
    ),
  ];
}
