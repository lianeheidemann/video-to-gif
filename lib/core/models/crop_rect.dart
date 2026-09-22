/// Recorte em pixels de uma mídia (vídeo ou foto) já na orientação de
/// exibição — retângulo simples, sem nenhuma dependência de vídeo, para
/// poder ser reaproveitado tanto pelo recorte de vídeo (`ConversionSettings`)
/// quanto pelo recorte de uma foto individual da montagem (`PhotoCropPage`).
class CropRect {
  const CropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;

  /// Maior recorte centralizado com a proporção [ratio] que cabe num
  /// conteúdo de [contentWidth]x[contentHeight], arredondado para dimensões
  /// pares (exigência do FFmpeg para recorte/escala de vídeo — inofensivo
  /// para fotos).
  factory CropRect.centeredIn(
    int contentWidth,
    int contentHeight,
    double ratio,
  ) {
    // Tenta usar a largura inteira do conteúdo e calcula a altura
    // correspondente; se não couber, faz o caminho inverso a partir da
    // altura.
    var w = contentWidth;
    var h = (w / ratio).round();
    if (h > contentHeight) {
      h = contentHeight;
      w = (h * ratio).round();
    }
    w = w - (w % 2);
    h = h - (h % 2);
    return CropRect(
      x: ((contentWidth - w) / 2).round(),
      y: ((contentHeight - h) / 2).round(),
      width: w,
      height: h,
    );
  }

  /// Cria uma cópia substituindo apenas os campos informados.
  CropRect copyWith({int? x, int? y, int? width, int? height}) => CropRect(
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
  );
}
