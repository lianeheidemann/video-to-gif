/// De onde veio a arte de um sticker — mesmo espírito de `ImageFrameSource`
/// em `image_frame.dart`.
enum CollageStickerSource { bundledSvg, importedSvg, importedImage }

/// Um sticker posicionado sobre a montagem: arrastável, redimensionável e
/// rotacionável livremente (ao contrário da rotação em passos de 90° das
/// fotos de célula), com ordem de empilhamento própria.
class CollageSticker {
  const CollageSticker({
    required this.id,
    required this.source,
    this.assetPath,
    this.imageFilePath,
    this.label = '',
    required this.centerX,
    required this.centerY,
    this.scale = 1.0,
    this.rotation = 0.0,
    required this.zIndex,
  }) : assert(
         (source == CollageStickerSource.bundledSvg && assetPath != null) ||
             ((source == CollageStickerSource.importedSvg ||
                     source == CollageStickerSource.importedImage) &&
                 imageFilePath != null),
         'assetPath é obrigatório para bundledSvg; '
         'imageFilePath é obrigatório para importedSvg/importedImage.',
       );

  final String id;
  final CollageStickerSource source;

  /// Caminho do asset (`assets/sticker/...`), quando [source] é
  /// [CollageStickerSource.bundledSvg].
  final String? assetPath;

  /// Caminho do arquivo importado copiado localmente, quando [source] é
  /// [CollageStickerSource.importedSvg] ou [CollageStickerSource.importedImage].
  final String? imageFilePath;

  final String label;

  /// Centro do sticker, normalizado ao tamanho do canvas da montagem
  /// (`0..1`) — pode ficar parcial ou totalmente fora de `[0,1]`, já que um
  /// sticker pode sangrar para fora da moldura por escolha do usuário.
  final double centerX;
  final double centerY;

  /// Escala relativa a um tamanho de referência do sticker (uma fração do
  /// menor lado do canvas) — nunca pixels fixos, mesmo espírito proporcional
  /// do resto do app.
  final double scale;

  /// Rotação livre, em radianos.
  final double rotation;

  /// Ordem de desenho entre stickers/textos: maior valor desenha por cima.
  final int zIndex;

  static const referenceSizeRatio = 0.28;
  static const minScale = 0.2;
  static const maxScale = 3.0;

  CollageSticker copyWith({
    double? centerX,
    double? centerY,
    double? scale,
    double? rotation,
    int? zIndex,
  }) {
    return CollageSticker(
      id: id,
      source: source,
      assetPath: assetPath,
      imageFilePath: imageFilePath,
      label: label,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}
