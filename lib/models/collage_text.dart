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
    this.backgroundColor,
    this.backgroundCornerRatio = defaultBackgroundCornerRatio,
    this.fontSizeRatio = defaultFontSizeRatio,
    this.bold = true,
    required this.centerX,
    required this.centerY,
    this.scale = 1.0,
    this.rotation = 0.0,
    required this.zIndex,
    this.fontFamily,
  });

  final String id;
  final String text;
  final Color color;

  /// Cor da caixa desenhada atrás do texto. `null` (padrão) é sem fundo
  /// nenhum — o texto fica direto sobre a montagem, como sempre foi.
  final Color? backgroundColor;

  /// Arredondamento dos cantos dessa caixa, como razão do menor lado dela
  /// (mesma unidade proporcional de `CollageCellSettings.cornerRatio`):
  /// `0` é canto reto e [maxBackgroundCornerRatio] é a cápsula completa.
  final double backgroundCornerRatio;

  bool get hasBackground => backgroundColor != null;

  /// Respiro entre o texto e a borda da caixa de fundo, proporcional ao
  /// tamanho da fonte — a mesma conta na prévia e na exportação, para as
  /// duas desenharem a mesma caixa.
  static (double horizontal, double vertical) backgroundPaddingFor(
    double fontSize,
  ) => (fontSize * 0.34, fontSize * 0.16);

  /// `null` = fonte padrão do tema (nenhum asset embutido para carregar).
  /// Um dos nomes de família registrados no bloco `fonts:` do `pubspec.yaml`
  /// (ver [bundledCollageFonts]) quando o usuário escolhe uma fonte
  /// embutida.
  final String? fontFamily;

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
  static const defaultBackgroundCornerRatio = 0.3;
  static const maxBackgroundCornerRatio = 0.5;

  CollageTextItem copyWith({
    String? text,
    Color? color,
    Color? backgroundColor,
    bool clearBackgroundColor = false,
    double? backgroundCornerRatio,
    double? fontSizeRatio,
    bool? bold,
    double? centerX,
    double? centerY,
    double? scale,
    double? rotation,
    int? zIndex,
    String? fontFamily,
    bool clearFontFamily = false,
  }) {
    return CollageTextItem(
      id: id,
      text: text ?? this.text,
      color: color ?? this.color,
      backgroundColor: clearBackgroundColor
          ? null
          : (backgroundColor ?? this.backgroundColor),
      backgroundCornerRatio:
          backgroundCornerRatio ?? this.backgroundCornerRatio,
      fontSizeRatio: fontSizeRatio ?? this.fontSizeRatio,
      bold: bold ?? this.bold,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
    );
  }
}

/// Fontes embutidas no app (offline, sem baixar nada em tempo de execução —
/// mesmo espírito dos 5 stickers embutidos em `assets/sticker/`), oferecidas
/// como opção para o texto da montagem. `null` é "Padrão" (a fonte do tema).
const bundledCollageFonts = <(String? family, String label)>[
  (null, 'Padrão'),
  ('Poppins', 'Poppins'),
  ('Playfair Display', 'Playfair Display'),
  ('Pacifico', 'Pacifico'),
  ('Bebas Neue', 'Bebas Neue'),
  ('Space Mono', 'Space Mono'),
];
