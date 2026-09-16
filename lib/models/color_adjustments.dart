import 'dart:math' as math;
import 'dart:ui' show ColorFilter;

/// Os oito ajustes de cor do app num objeto só, para as três telas
/// (montagem, moldura e edição de GIF) falarem a mesma língua. Todos valem
/// de `-1` a `1`, com `0` no neutro.
///
/// A montagem guarda os mesmos oito valores dentro de cada célula (uma foto
/// pode ter o ajuste dela), então lá eles moram em `CollageCellSettings`; nas
/// outras duas telas o ajuste é um só para a imagem inteira e cabe aqui.
class ColorAdjustments {
  const ColorAdjustments({
    this.brightness = 0,
    this.exposure = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.saturation = 0,
    this.hue = 0,
    this.temperature = 0,
  });

  final double brightness;
  final double exposure;
  final double contrast;
  final double highlights;
  final double shadows;
  final double saturation;
  final double hue;
  final double temperature;

  static const neutral = ColorAdjustments();

  /// `true` quando algum ajuste saiu do neutro — atalho para a tela
  /// mostrar/esconder o "Redefinir" e para o pipeline pular o filtro quando
  /// não há nada a fazer.
  bool get hasAdjustments =>
      brightness != 0 ||
      exposure != 0 ||
      contrast != 0 ||
      highlights != 0 ||
      shadows != 0 ||
      saturation != 0 ||
      hue != 0 ||
      temperature != 0;

  ColorFilter get filter => buildAdjustmentColorFilter(
    brightness: brightness,
    exposure: exposure,
    contrast: contrast,
    highlights: highlights,
    shadows: shadows,
    saturation: saturation,
    hue: hue,
    temperature: temperature,
  );

  /// A parte dos ajustes que trata os três canais igual: `saída = ganho *
  /// entrada + deslocamento`, com a entrada e o deslocamento na escala
  /// 0–255. São exposição, realces, sombras, brilho e contraste, compostos
  /// na mesma ordem de [buildAdjustmentColorFilter].
  ///
  /// Existe para o FFmpeg poder reproduzir o mesmo resultado da prévia: o
  /// filtro `eq` dele é exatamente um ganho com deslocamento, e sair da
  /// mesma conta das matrizes é o que impede a exportação de divergir do que
  /// a tela mostrou.
  (double gain, double shift) get toneTransfer {
    var gain = 1.0;
    var shift = 0.0;
    void compose(double g, double s) {
      gain = g * gain;
      shift = g * shift + s;
    }

    compose(math.pow(2, exposure.clamp(-1.0, 1.0)).toDouble(), 0);
    final h = highlights.clamp(-1.0, 1.0);
    compose(1 + h * 0.5, -h * 0.5 * 96);
    final sh = shadows.clamp(-1.0, 1.0);
    compose(1 - sh * 0.35, sh * 0.35 * 190);
    compose(1, brightness.clamp(-1.0, 1.0) * 100);
    final c = (contrast + 1).clamp(0.0, 2.0);
    compose(c, 127.5 * (1 - c));
    return (gain, shift);
  }

  /// A parte que mistura canais — saturação, matiz e temperatura — como uma
  /// matriz 4x5 (as três não têm deslocamento, então a 5ª coluna é zero).
  /// É o que o `colorchannelmixer` do FFmpeg sabe aplicar.
  List<double> get channelMixMatrix {
    var m = _identity4x5();
    m = _multiply4x5(_saturationMatrix(saturation), m);
    m = _multiply4x5(_hueMatrix(hue), m);
    m = _multiply4x5(_temperatureMatrix(temperature), m);
    return m;
  }

  ColorAdjustments copyWith({
    double? brightness,
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? saturation,
    double? hue,
    double? temperature,
  }) => ColorAdjustments(
    brightness: brightness ?? this.brightness,
    exposure: exposure ?? this.exposure,
    contrast: contrast ?? this.contrast,
    highlights: highlights ?? this.highlights,
    shadows: shadows ?? this.shadows,
    saturation: saturation ?? this.saturation,
    hue: hue ?? this.hue,
    temperature: temperature ?? this.temperature,
  );
}

/// Uma única matriz 4x5 (`ColorFilter.matrix`) compondo todos os ajustes de
/// cor — só uma composição pode ser aplicada por [Paint], então todos
/// precisam virar uma conta só em vez de vários [ColorFilter]s encadeados.
/// Todos os parâmetros em `[-1, 1]` (0 = neutro), e a ordem de composição é
/// a mesma de um editor de foto comum: primeiro o que mexe na exposição da
/// cena (exposição/realces/sombras/brilho), depois contraste, depois cor
/// (saturação/matiz/temperatura).
///
/// Realces e sombras são aproximações por matriz: puxam a imagem inteira
/// para cima ou para baixo com um peso maior na ponta correspondente da
/// faixa. Um ajuste tonal "de verdade" precisaria de curva por pixel (um
/// shader), fora do que uma matriz 4x5 consegue expressar.
ColorFilter buildAdjustmentColorFilter({
  required double brightness,
  double exposure = 0,
  required double contrast,
  double highlights = 0,
  double shadows = 0,
  required double saturation,
  double hue = 0,
  double temperature = 0,
}) {
  var m = _identity4x5();
  m = _multiply4x5(_exposureMatrix(exposure), m);
  m = _multiply4x5(_highlightsMatrix(highlights), m);
  m = _multiply4x5(_shadowsMatrix(shadows), m);
  m = _multiply4x5(_brightnessMatrix(brightness), m);
  m = _multiply4x5(_contrastMatrix(contrast), m);
  m = _multiply4x5(_saturationMatrix(saturation), m);
  m = _multiply4x5(_hueMatrix(hue), m);
  m = _multiply4x5(_temperatureMatrix(temperature), m);
  return ColorFilter.matrix(m);
}

List<double> _identity4x5() => [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Exposição: multiplica a cena (como abrir/fechar o diafragma), então o
/// preto continua preto e o efeito cresce nas partes claras — ao contrário
/// do brilho, que soma um valor fixo em tudo. `+1` dobra a luz; `-1` corta
/// pela metade.
List<double> _exposureMatrix(double exposure) {
  final e = math.pow(2, exposure.clamp(-1.0, 1.0)).toDouble();
  return [
    e, 0, 0, 0, 0, //
    0, e, 0, 0, 0, //
    0, 0, e, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// Realces: mexe mais na parte alta da faixa. Multiplicar por um ganho e
/// compensar com uma translação negativa mantém os tons escuros quase
/// parados enquanto os claros sobem (ou descem, com valor negativo).
List<double> _highlightsMatrix(double highlights) {
  final h = highlights.clamp(-1.0, 1.0);
  if (h == 0) return _identity4x5();
  final gain = 1 + h * 0.5;
  final shift = -h * 0.5 * 96;
  return [
    gain, 0, 0, 0, shift, //
    0, gain, 0, 0, shift, //
    0, 0, gain, 0, shift, //
    0, 0, 0, 1, 0, //
  ];
}

/// Sombras: o espelho de [_highlightsMatrix] — levanta (ou afunda) a parte
/// baixa da faixa, deixando os tons claros praticamente onde estavam.
List<double> _shadowsMatrix(double shadows) {
  final s = shadows.clamp(-1.0, 1.0);
  if (s == 0) return _identity4x5();
  final gain = 1 - s * 0.35;
  final shift = s * 0.35 * 190;
  return [
    gain, 0, 0, 0, shift, //
    0, gain, 0, 0, shift, //
    0, 0, gain, 0, shift, //
    0, 0, 0, 1, 0, //
  ];
}

/// Matiz: gira a roda de cores em até 180° para cada lado, mantendo a luma
/// (a fórmula clássica de rotação de hue em espaço RGB, com os pesos de
/// [_lumR]/[_lumG]/[_lumB]).
List<double> _hueMatrix(double hue) {
  final angle = hue.clamp(-1.0, 1.0) * math.pi;
  if (angle == 0) return _identity4x5();
  final c = math.cos(angle);
  final s = math.sin(angle);
  double m(double weight, double cosPart, double sinPart) =>
      weight + c * cosPart + s * sinPart;
  return [
    m(_lumR, 1 - _lumR, -_lumR),
    m(_lumG, -_lumG, -_lumG),
    m(_lumB, -_lumB, 1 - _lumB),
    0, 0, //
    m(_lumR, -_lumR, 0.143),
    m(_lumG, 1 - _lumG, 0.140),
    m(_lumB, -_lumB, -0.283),
    0, 0, //
    m(_lumR, -_lumR, -(1 - _lumR)),
    m(_lumG, -_lumG, _lumG),
    m(_lumB, 1 - _lumB, _lumB),
    0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// Temperatura: positivo esquenta (mais vermelho, menos azul), negativo
/// esfria. O verde fica de fora, como na maioria dos editores.
List<double> _temperatureMatrix(double temperature) {
  final t = temperature.clamp(-1.0, 1.0);
  if (t == 0) return _identity4x5();
  final warm = 1 + t * 0.25;
  final cool = 1 - t * 0.25;
  return [
    warm, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, cool, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
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
