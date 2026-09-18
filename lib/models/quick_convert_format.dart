import 'package:flutter/material.dart' show IconData, Icons;

import 'conversion_settings.dart' show DitherMode;

/// Formatos oferecidos na tela "Converter formato" — um recurso à parte de
/// "Editar GIF" (ver [OutputFormat] em `conversion_settings.dart`), com uma
/// única configuração exposta além do arquivo de entrada: [QuickConvertQuality].
enum QuickConvertFormat {
  gif('gif', 'image/gif', 'GIF', Icons.gif_box_outlined),
  webp(
    'webp',
    'image/webp',
    'WebP animado',
    Icons.auto_awesome_motion_outlined,
  ),
  mp4('mp4', 'video/mp4', 'MP4', Icons.play_circle_outline_rounded);

  const QuickConvertFormat(
    this.extension,
    this.mimeType,
    this.label,
    this.icon,
  );

  /// Extensão do arquivo de saída, sem o ponto.
  final String extension;

  /// Tipo MIME usado ao compartilhar o arquivo.
  final String mimeType;

  /// Texto exibido no seletor de formato.
  final String label;

  /// Ícone exibido no cartão de seleção de formato.
  final IconData icon;

  /// Se este formato é uma imagem animada (GIF/WebP) — o MP4 sempre
  /// preserva áudio quando existir; os dois formatos de imagem nunca têm
  /// áudio.
  bool get isAnimatedImage =>
      this == QuickConvertFormat.gif || this == QuickConvertFormat.webp;
}

/// Nível de qualidade oferecido na tela "Converter formato" — reduz a um
/// seletor de 3 opções fixas os mesmos parâmetros que "Editar GIF" já expõe
/// em detalhe (cores/pontilhado do GIF, qualidade do WebP, bitrate do MP4).
enum QuickConvertQuality {
  low('Baixa', 'menor arquivo'),
  standard('Padrão', 'recomendado'),
  high('Alta', 'melhor qualidade');

  const QuickConvertQuality(this.label, this.hint);

  final String label;
  final String hint;

  /// Paleta de cores do GIF (ver [ConversionSettings.colors]).
  int get gifColors => switch (this) {
    QuickConvertQuality.low => 128,
    QuickConvertQuality.standard => 256,
    QuickConvertQuality.high => 256,
  };

  /// Pontilhado do GIF (ver [ConversionSettings.dither]) — mais difusão de
  /// erro na qualidade alta, ao custo de um arquivo mais pesado.
  DitherMode get gifDither => switch (this) {
    QuickConvertQuality.low => DitherMode.bayer3,
    QuickConvertQuality.standard => DitherMode.bayer5,
    QuickConvertQuality.high => DitherMode.sierra,
  };

  /// Qualidade do encoder `libwebp` (ver [ConversionSettings.webpQuality]).
  int get webpQuality => switch (this) {
    QuickConvertQuality.low => 50,
    QuickConvertQuality.standard => 75,
    QuickConvertQuality.high => 95,
  };

  /// Bitrate de vídeo (`-b:v`) usado na conversão para MP4.
  int get mp4BitrateKbps => switch (this) {
    QuickConvertQuality.low => 1500,
    QuickConvertQuality.standard => 3000,
    QuickConvertQuality.high => 6000,
  };
}
