import 'dart:math' as math;
import 'dart:ui';

/// Rotação de uma foto dentro de sua célula, sempre em passos de 90° — não
/// há necessidade de ângulo livre aqui (diferente dos stickers/texto, que
/// podem girar livremente com dois dedos).
enum CellRotation {
  none(0),
  quarter(90),
  half(180),
  threeQuarters(270);

  const CellRotation(this.degrees);

  final int degrees;

  double get radians => degrees * math.pi / 180;

  /// Equivalente para o parâmetro `quarterTurns` de [RotatedBox], usado na
  /// prévia ao vivo — [RotatedBox] gira em múltiplos de 90° trocando a
  /// própria caixa de layout (ao contrário de `Transform.rotate`), o que
  /// evita ter que compensar manualmente a troca de largura/altura.
  int get quarterTurns => degrees ~/ 90;

  /// Troca largura/altura ao desenhar: só acontece nos giros de 90°/270°.
  bool get swapsAxes => this == quarter || this == threeQuarters;

  /// Próximo giro no sentido horário — usado pelo botão "Girar 90°".
  CellRotation get next => switch (this) {
    CellRotation.none => CellRotation.quarter,
    CellRotation.quarter => CellRotation.half,
    CellRotation.half => CellRotation.threeQuarters,
    CellRotation.threeQuarters => CellRotation.none,
  };
}

/// Configuração de uma célula da montagem: qual foto ocupa esse espaço, como
/// ela é enquadrada (deslocamento/zoom em relação ao recorte "cover" que
/// preenche a célula), sua rotação/espelhamento, o arredondamento do canto
/// da própria célula e os ajustes de cor aplicados só a ela.
///
/// [offsetX]/[offsetY] variam sempre em `[-1, 1]` e representam a fração da
/// folga de recorte disponível no eixo — não pixels fixos —, então
/// [coverSrcRect] nunca deixa a foto menor que a célula (sem "buracos"),
/// qualquer que seja o valor dentro desse intervalo.
class CollageCellSettings {
  const CollageCellSettings({
    this.photoPath,
    this.photoWidth = 0,
    this.photoHeight = 0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.zoom = minZoom,
    this.rotation = CellRotation.none,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cornerRatio = 0.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
  });

  /// `null` representa uma célula ainda sem foto escolhida.
  final String? photoPath;
  final int photoWidth;
  final int photoHeight;

  final double offsetX;
  final double offsetY;

  /// De [minZoom] (recorte "cover" padrão, preenche a célula sem sobra) a
  /// [maxZoom].
  final double zoom;

  final CellRotation rotation;
  final bool flipHorizontal;
  final bool flipVertical;

  /// Arredondamento do canto desta célula, como razão do menor lado da
  /// célula — mesma unidade proporcional de [FrameSettings.cornerRatio].
  final double cornerRatio;

  /// Ajustes de cor, todos em `[-1, 1]` (0 = neutro).
  final double brightness;
  final double contrast;
  final double saturation;

  static const minZoom = 1.0;
  static const maxZoom = 4.0;
  static const maxCornerRatio = 0.5;

  bool get hasPhoto => photoPath != null;

  /// Proporção efetiva da foto já considerando a rotação (girada 90°/270°
  /// troca largura por altura).
  double get aspectRatio {
    if (photoWidth <= 0 || photoHeight <= 0) return 1;
    final w = rotation.swapsAxes ? photoHeight : photoWidth;
    final h = rotation.swapsAxes ? photoWidth : photoHeight;
    return w / h;
  }

  /// Retângulo de origem (em pixels da foto decodificada, na orientação
  /// nativa do arquivo) que cobre inteiramente uma célula de tamanho
  /// [cellSize] — o "cover" do `BoxFit.cover`, ciente de [zoom]/[offsetX]/
  /// [offsetY] e de [rotation] (que troca a orientação efetiva do destino
  /// antes do cálculo, já que o desenho gira o canvas depois).
  Rect coverSrcRect(Size cellSize) {
    if (photoWidth <= 0 || photoHeight <= 0 || cellSize.isEmpty) {
      return Rect.zero;
    }

    final destWidth = rotation.swapsAxes ? cellSize.height : cellSize.width;
    final destHeight = rotation.swapsAxes ? cellSize.width : cellSize.height;
    final srcAspect = photoWidth / photoHeight;
    final dstAspect = destWidth / destHeight;

    double baseWidth, baseHeight;
    if (srcAspect > dstAspect) {
      baseHeight = photoHeight.toDouble();
      baseWidth = baseHeight * dstAspect;
    } else {
      baseWidth = photoWidth.toDouble();
      baseHeight = baseWidth / dstAspect;
    }

    final z = zoom.clamp(minZoom, maxZoom);
    final cropWidth = (baseWidth / z).clamp(1.0, photoWidth.toDouble());
    final cropHeight = (baseHeight / z).clamp(1.0, photoHeight.toDouble());

    final maxOffsetX = (photoWidth - cropWidth) / 2;
    final maxOffsetY = (photoHeight - cropHeight) / 2;
    final ox = offsetX.clamp(-1.0, 1.0);
    final oy = offsetY.clamp(-1.0, 1.0);
    final centerX = photoWidth / 2 + ox * maxOffsetX;
    final centerY = photoHeight / 2 + oy * maxOffsetY;

    return Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: cropWidth,
      height: cropHeight,
    );
  }

  /// Converte um deslocamento em pixels de tela (ex.: [ScaleUpdateDetails.
  /// focalPointDelta] de um gesto sobre a célula) para o incremento
  /// correspondente de [offsetX]/[offsetY], levando em conta [zoom] atual e
  /// a orientação efetiva de [rotation]/[flipHorizontal]/[flipVertical] —
  /// arrastar sempre desloca a foto na direção intuitiva na tela, mesmo
  /// girada ou espelhada. Devolve `Offset.zero` quando não há folga naquele
  /// eixo (ex.: zoom no mínimo).
  Offset offsetDeltaForDrag(Offset screenDelta, Size cellSize) {
    final src = coverSrcRect(cellSize);
    if (src == Rect.zero) return Offset.zero;

    // Desfaz primeiro a rotação, depois o espelhamento — ordem inversa de
    // como o desenho aplica as duas (gira o canvas e só então espelha, tanto
    // aqui quanto em `paintCollageCell`/`RotatedBox`+`Transform` na prévia),
    // para o arrasto sempre mover a foto na direção em que o dedo se move na
    // tela, qualquer que seja a orientação atual.
    var local = switch (rotation) {
      CellRotation.none => screenDelta,
      CellRotation.quarter => Offset(screenDelta.dy, -screenDelta.dx),
      CellRotation.half => Offset(-screenDelta.dx, -screenDelta.dy),
      CellRotation.threeQuarters => Offset(-screenDelta.dy, screenDelta.dx),
    };
    if (flipHorizontal) local = Offset(-local.dx, local.dy);
    if (flipVertical) local = Offset(local.dx, -local.dy);

    final destWidth = rotation.swapsAxes ? cellSize.height : cellSize.width;
    final destHeight = rotation.swapsAxes ? cellSize.width : cellSize.height;
    if (destWidth <= 0 || destHeight <= 0) return Offset.zero;

    final scaleX = src.width / destWidth;
    final scaleY = src.height / destHeight;
    final maxOffsetX = (photoWidth - src.width) / 2;
    final maxOffsetY = (photoHeight - src.height) / 2;

    // Negativo: a janela de recorte se move para o lado OPOSTO ao dedo, que é
    // o que faz a própria foto parecer se mover JUNTO com o dedo (arrastar
    // para a direita revela mais do lado esquerdo da foto, como se ela
    // estivesse sendo empurrada para a direita) — a manipulação direta que o
    // usuário espera ao "arrastar a foto", não um pan de câmera/viewport.
    final dx = maxOffsetX > 0 ? -(local.dx * scaleX) / maxOffsetX : 0.0;
    final dy = maxOffsetY > 0 ? -(local.dy * scaleY) / maxOffsetY : 0.0;
    return Offset(dx, dy);
  }

  ColorFilter get colorFilter => buildAdjustmentColorFilter(
    brightness: brightness,
    contrast: contrast,
    saturation: saturation,
  );

  CollageCellSettings copyWith({
    String? photoPath,
    bool clearPhoto = false,
    int? photoWidth,
    int? photoHeight,
    double? offsetX,
    double? offsetY,
    double? zoom,
    CellRotation? rotation,
    bool? flipHorizontal,
    bool? flipVertical,
    double? cornerRatio,
    double? brightness,
    double? contrast,
    double? saturation,
  }) {
    return CollageCellSettings(
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      photoWidth: photoWidth ?? this.photoWidth,
      photoHeight: photoHeight ?? this.photoHeight,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      zoom: zoom ?? this.zoom,
      rotation: rotation ?? this.rotation,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      cornerRatio: cornerRatio ?? this.cornerRatio,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
    );
  }

  /// Reseta enquadramento (deslocamento/zoom/rotação/espelhamento) mantendo
  /// a foto e os ajustes de cor — usado no duplo toque "recentralizar" e ao
  /// substituir a foto de uma célula (o enquadramento antigo não faz
  /// sentido para outra foto, mas a cor escolhida para aquele espaço sim).
  CollageCellSettings resetFraming() => copyWith(
    offsetX: 0,
    offsetY: 0,
    zoom: minZoom,
    rotation: CellRotation.none,
    flipHorizontal: false,
    flipVertical: false,
  );
}

/// Uma única matriz 4x5 (`ColorFilter.matrix`) compondo saturação, contraste
/// e brilho — só uma composição pode ser aplicada por [Paint], então as três
/// precisam virar uma conta só em vez de três [ColorFilter]s encadeados.
/// Todos os parâmetros em `[-1, 1]` (0 = neutro).
ColorFilter buildAdjustmentColorFilter({
  required double brightness,
  required double contrast,
  required double saturation,
}) {
  final m = _multiply4x5(
    _contrastMatrix(contrast),
    _saturationMatrix(saturation),
  );
  final result = _multiply4x5(_brightnessMatrix(brightness), m);
  return ColorFilter.matrix(result);
}

// Pesos de luma do Rec. 709 (o espaço de cor de sRGB, que é o que a foto
// decodificada já está usando) — o comentário anterior dizia Rec. 601, mas os
// coeficientes sempre foram estes.
const _lumR = 0.2126;
const _lumG = 0.7152;
const _lumB = 0.0722;

List<double> _saturationMatrix(double saturation) {
  final s = (saturation + 1).clamp(0.0, 2.0);
  final sr = (1 - s) * _lumR;
  final sg = (1 - s) * _lumG;
  final sb = (1 - s) * _lumB;
  return [
    sr + s, sg, sb, 0, 0, //
    sr, sg + s, sb, 0, 0, //
    sr, sg, sb + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _contrastMatrix(double contrast) {
  final c = (contrast + 1).clamp(0.0, 2.0);
  final t = 127.5 * (1 - c);
  return [
    c, 0, 0, 0, t, //
    0, c, 0, 0, t, //
    0, 0, c, 0, t, //
    0, 0, 0, 1, 0, //
  ];
}

List<double> _brightnessMatrix(double brightness) {
  final b = (brightness.clamp(-1.0, 1.0)) * 100;
  return [
    1, 0, 0, 0, b, //
    0, 1, 0, 0, b, //
    0, 0, 1, 0, b, //
    0, 0, 0, 1, 0, //
  ];
}

/// Multiplica duas matrizes 4x5 no formato de [ColorFilter.matrix] (a 5ª
/// coluna é a translação, tratada como uma coluna homogênea extra que nunca
/// contribui de volta para as translações de [a], mesmo princípio de
/// composição de transformações afins 2D em uma dimensão a mais.
List<double> _multiply4x5(List<double> a, List<double> b) {
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[row * 5 + k] * b[k * 5 + col];
      }
      if (col == 4) sum += a[row * 5 + 4];
      result[row * 5 + col] = sum;
    }
  }
  return result;
}
