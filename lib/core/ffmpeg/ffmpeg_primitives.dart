import 'package:flutter/painting.dart' show Color;

/// Peças pequenas que toda montagem de linha de comando do FFmpeg usa.

int evenRound(num value) {
  final rounded = value.round();
  return rounded - (rounded % 2);
}

int evenAtLeast2(num value) {
  final even = evenRound(value);
  return even < 2 ? 2 : even;
}

String ffmpegColor(Color color) {
  final rgb = (color.toARGB32() & 0x00FFFFFF).toRadixString(16);
  return '0x${rgb.padLeft(6, '0')}';
}

String ffmpegSeconds(double value) => value.toStringAsFixed(3);

String filterNumber(double value) => value.toStringAsFixed(4);

/// Grafo de filtro completo pronto para `-lavfi`: [input] (ex.: `0:v`) até
/// [output], já com a moldura aplicada — conteúdo ([buildConversionVideoFilter])
/// ajustado à área da moldura conforme [ConversionSettings.frame]'s
/// modo de ajuste, recortado pelos cantos internos e composto sobre o
/// fundo colorido no tamanho final ([ConversionSettings.outputDimensions]).
/// Só deve ser chamado quando há moldura ativa
/// (`frame.style != FrameStyle.none`).
