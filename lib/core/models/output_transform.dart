import 'dart:math' as math;
import 'dart:ui' show Canvas, Size;

/// Giro e espelhamento aplicados **no fim**, ao resultado já pronto.
///
/// Diferente da tela de SVG, onde girar gira o espaço de trabalho inteiro e o
/// recorte passa a ser medido já girado, aqui a transformação é o último
/// passo antes de exportar: recorte, moldura, proporções prontas e estimativa
/// de tamanho continuam trabalhando na orientação original da mídia.
///
/// A ordem é girar e depois espelhar — a mesma que a prévia do SVG usa
/// (`RotatedBox` por dentro, `Transform` de espelho por fora), para as telas
/// não divergirem entre si.
class OutputTransform {
  const OutputTransform({
    this.quarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
  });

  /// Quartos de volta no sentido horário, de 0 a 3.
  final int quarterTurns;

  final bool flipHorizontal;
  final bool flipVertical;

  static const identity = OutputTransform();

  /// `true` quando não há nada a aplicar — quem exporta pode pular o passo
  /// inteiro, e a aba mostra "Original".
  bool get isIdentity => quarterTurns == 0 && !flipHorizontal && !flipVertical;

  /// `true` em 90° e 270°, que trocam largura por altura no resultado.
  bool get swapsAxes => quarterTurns.isOdd;

  /// Gira [turns] quartos de volta a partir do estado atual. Girar para a
  /// esquerda a partir de 0 dá 3, não -1: o `%` do Dart já devolve resultado
  /// não-negativo para divisor positivo, ao contrário de C e Java.
  OutputTransform rotatedBy(int turns) =>
      copyWith(quarterTurns: quarterTurns + turns);

  OutputTransform copyWith({
    int? quarterTurns,
    bool? flipHorizontal,
    bool? flipVertical,
  }) => OutputTransform(
    quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
    flipHorizontal: flipHorizontal ?? this.flipHorizontal,
    flipVertical: flipVertical ?? this.flipVertical,
  );

  /// Resumo curto para o cabeçalho da aba.
  String get label {
    if (isIdentity) return 'Original';
    return [
      if (quarterTurns != 0) '${quarterTurns * 90}°',
      if (flipHorizontal) 'Espelho H',
      if (flipVertical) 'Espelho V',
    ].join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is OutputTransform &&
      other.quarterTurns == quarterTurns &&
      other.flipHorizontal == flipHorizontal &&
      other.flipVertical == flipVertical;

  @override
  int get hashCode => Object.hash(quarterTurns, flipHorizontal, flipVertical);
}

/// Tamanho do canvas final depois de [transform] — largura e altura
/// trocadas em 90° e 270°, iguais nos outros casos.
(int, int) transformedCanvasSize(
  OutputTransform transform,
  int width,
  int height,
) => transform.swapsAxes ? (height, width) : (width, height);

/// Prepara [canvas] para receber um desenho de [size] já girado e
/// espelhado: depois desta chamada, desenhar nas coordenadas originais
/// (`0..size.width` por `0..size.height`) cai no lugar certo de um canvas
/// de [transformedCanvasSize].
///
/// A ordem das chamadas é o inverso da ordem em que elas agem — a última
/// aplicada é a mais interna. Por isso o espelho vem primeiro aqui: ele
/// precisa agir sobre o resultado já girado, como na prévia, onde o
/// `Transform` de espelho envolve o `RotatedBox`.
void applyCanvasOutputTransform(
  Canvas canvas,
  OutputTransform transform,
  Size size,
) {
  if (transform.isIdentity) return;
  final (canvasWidth, canvasHeight) = transformedCanvasSize(
    transform,
    size.width.round(),
    size.height.round(),
  );

  if (transform.flipHorizontal) {
    canvas.translate(canvasWidth.toDouble(), 0);
    canvas.scale(-1, 1);
  }
  if (transform.flipVertical) {
    canvas.translate(0, canvasHeight.toDouble());
    canvas.scale(1, -1);
  }

  switch (transform.quarterTurns) {
    case 1:
      canvas.translate(size.height, 0);
      canvas.rotate(math.pi / 2);
    case 2:
      canvas.translate(size.width, size.height);
      canvas.rotate(math.pi);
    case 3:
      canvas.translate(0, size.width);
      canvas.rotate(-math.pi / 2);
  }
}
