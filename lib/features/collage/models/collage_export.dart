/// Em que formato a montagem é exportada. [png] é a montagem parada (o único
/// formato que existia antes); [gif] e [webp] só fazem sentido quando alguma
/// foto da montagem é animada — aí a montagem inteira vira animação, com as
/// fotos paradas servindo de "pano de fundo" imóvel.
enum CollageExportFormat {
  png('PNG', 'Imagem parada', 'png', 'image/png'),
  gif('GIF', 'Animado, compatível com tudo', 'gif', 'image/gif'),
  webp('WebP', 'Animado, arquivo menor', 'webp', 'image/webp');

  const CollageExportFormat(
    this.label,
    this.subtitle,
    this.extension,
    this.mimeType,
  );

  final String label;
  final String subtitle;
  final String extension;
  final String mimeType;

  bool get isAnimated => this != CollageExportFormat.png;
}

/// Tamanho da exportação, como multiplicador da largura calculada
/// automaticamente a partir das fotos e do layout ([standard] é essa largura
/// sem nenhuma mudança — o comportamento de antes de existir essa escolha).
enum CollageExportSize {
  small('Pequeno', 0.5),
  mediumSmall('Médio', 0.75),
  standard('Padrão', 1),
  large('Grande', 1.5),
  extraLarge('Extra grande', 2);

  const CollageExportSize(this.label, this.multiplier);

  final String label;
  final double multiplier;
}

/// Como resolver durações diferentes entre as fotos animadas da montagem.
/// Em [longest] a montagem dura o tempo da animação mais longa e as que
/// acabam antes **seguram o último quadro** (não somem nem piscam); em
/// [shortest] a montagem termina junto com a animação mais curta.
enum CollageDurationRule {
  longest('A mais longa', 'Quem acabar antes segura o último quadro'),
  shortest('A mais curta', 'A montagem termina com a animação mais curta');

  const CollageDurationRule(this.label, this.subtitle);

  final String label;
  final String subtitle;
}
