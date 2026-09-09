import 'dart:ui' show Color;

import 'default_colors.dart';

/// Como o espaço fora/entre as células da montagem é preenchido.
enum CollageBackgroundMode { transparent, color, image }

/// Fundo da montagem: transparente (padrão), cor sólida (escolhida por
/// swatches, roda HSV ou conta-gotas na própria prévia) ou uma imagem
/// importada pelo usuário.
class CollageBackground {
  const CollageBackground({
    this.mode = CollageBackgroundMode.transparent,
    this.color = defaultBackgroundColor,
    this.imagePath,
  });

  final CollageBackgroundMode mode;
  final Color color;

  /// Caminho do arquivo copiado localmente — só definido quando [mode] é
  /// [CollageBackgroundMode.image].
  final String? imagePath;

  CollageBackground copyWith({
    CollageBackgroundMode? mode,
    Color? color,
    String? imagePath,
    bool clearImagePath = false,
  }) {
    return CollageBackground(
      mode: mode ?? this.mode,
      color: color ?? this.color,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
    );
  }

  factory CollageBackground.transparent() => const CollageBackground();
}
