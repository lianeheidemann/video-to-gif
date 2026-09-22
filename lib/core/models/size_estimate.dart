/// Quão confiável é o número mostrado ao usuário.
enum EstimateConfidence {
  /// Ainda não medimos nada deste vídeo: o número vem de um valor médio.
  rough,

  /// Ajustado pelo bitrate do arquivo original — melhor que nada.
  fromSource,

  /// Medido de verdade, codificando uma amostra curta com estas mesmas
  /// configurações. É o número em que dá para confiar.
  calibrated,
}

extension EstimateConfidenceLabel on EstimateConfidence {
  String get label => switch (this) {
    EstimateConfidence.rough => 'Estimativa aproximada',
    EstimateConfidence.fromSource => 'Estimativa aproximada',
    EstimateConfidence.calibrated => 'Estimativa medida',
  };

  /// Margem de erro aplicada para montar a faixa mínimo–máximo.
  double get relativeMargin => switch (this) {
    EstimateConfidence.rough => 0.55,
    EstimateConfidence.fromSource => 0.40,
    EstimateConfidence.calibrated => 0.15,
  };
}

/// Classificação do peso, para o usuário não precisar saber o que é "muito".
enum SizeVerdict {
  light('Leve', 'Envia em qualquer lugar sem problema'),
  good('Bom', 'Tamanho confortável para redes sociais e WhatsApp'),
  heavy('Pesado', 'Pode demorar para carregar e alguns apps vão recomprimir'),
  tooHeavy('Muito pesado', 'Vários apps vão recusar ou destruir a qualidade');

  const SizeVerdict(this.label, this.advice);

  final String label;
  final String advice;

  static SizeVerdict forBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes <= 15 * mb) return SizeVerdict.light;
    if (bytes < 25 * mb) return SizeVerdict.good;
    if (bytes < 50 * mb) return SizeVerdict.heavy;
    return SizeVerdict.tooHeavy;
  }
}

/// Limites práticos de destinos comuns, para dar contexto ao número.
class ShareTarget {
  const ShareTarget(this.name, this.limitBytes);

  final String name;
  final int limitBytes;

  static const targets = <ShareTarget>[
    ShareTarget('WhatsApp', 16 * 1024 * 1024),
    ShareTarget('X / Twitter', 15 * 1024 * 1024),
    ShareTarget('Discord (grátis)', 10 * 1024 * 1024),
    ShareTarget('E-mail', 25 * 1024 * 1024),
    ShareTarget('Web rápida', 5 * 1024 * 1024),
  ];
}

/// Resultado de uma estimativa de peso.
class SizeEstimate {
  const SizeEstimate({
    required this.bytes,
    required this.frames,
    required this.width,
    required this.height,
    required this.bytesPerPixel,
    required this.confidence,
    required this.durationSeconds,
  });

  final int bytes;
  final int frames;
  final int width;
  final int height;

  /// Bytes por pixel por quadro efetivamente usados no cálculo.
  final double bytesPerPixel;

  final EstimateConfidence confidence;
  final double durationSeconds;

  /// Extremo inferior da faixa mínimo–máximo mostrada ao usuário.
  int get lowBytes =>
      (bytes * (1 - confidence.relativeMargin)).round().clamp(0, bytes).toInt();

  /// Extremo superior da faixa mínimo–máximo mostrada ao usuário.
  int get highBytes => (bytes * (1 + confidence.relativeMargin)).round();

  SizeVerdict get verdict => SizeVerdict.forBytes(bytes);

  double get megabytes => bytes / (1024 * 1024);

  /// Peso por segundo de GIF — útil para o usuário perceber que cortar
  /// a duração é a alavanca mais forte que existe.
  double get bytesPerSecond =>
      durationSeconds <= 0 ? 0 : bytes / durationSeconds;

  /// Se o extremo superior da estimativa cabe no limite de [target].
  bool fitsIn(ShareTarget target) => highBytes <= target.limitBytes;

  /// Formata bytes como B, KB ou MB, com uma casa decimal só abaixo de 10MB.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  String get formatted => formatBytes(bytes);
  String get formattedRange =>
      '${formatBytes(lowBytes)} – ${formatBytes(highBytes)}';
}
