import 'dart:ui' show Color;

/// Uma caixa de texto sobreposta à montagem — mesma forma de posicionamento/
/// escala/rotação/z-order de [CollageSticker] (ver `collage_sticker.dart`),
/// para as duas entrarem na mesma lista ordenada de sobreposições ao
/// desenhar.
class CollageTextItem {
  const CollageTextItem({
    required this.id,
    required this.text,
    this.color = const Color(0xFFFFFFFF),
    this.fontSizeRatio = defaultFontSizeRatio,
    this.bold = true,
    required this.centerX,
    required this.centerY,
    this.scale = 1.0,
    this.rotation = 0.0,
    required this.zIndex,
  });

  final String id;
  final String text;
  final Color color;

  /// Tamanho da fonte como fração do menor lado do canvas — proporcional,
  /// nunca pixels fixos, mesmo princípio do resto do app.
  final double fontSizeRatio;

  final bool bold;

  /// Centro do texto, normalizado ao tamanho do canvas (`0..1`).
  final double centerX;
  final double centerY;

  /// Escala adicional sobre [fontSizeRatio], aplicada pelo gesto de pinça.
  final double scale;

  /// Rotação livre, em radianos.
  final double rotation;

  final int zIndex;

  static const defaultFontSizeRatio = 0.07;
  static const minScale = 0.3;
  static const maxScale = 4.0;

  CollageTextItem copyWith({
    String? text,
    Color? color,
    double? fontSizeRatio,
    bool? bold,
    double? centerX,
    double? centerY,
    double? scale,
    double? rotation,
    int? zIndex,
  }) {
    return CollageTextItem(
      id: id,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSizeRatio: fontSizeRatio ?? this.fontSizeRatio,
      bold: bold ?? this.bold,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
    );
  }
}
