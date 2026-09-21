import 'dart:math' as math;

/// Metadados do vídeo de entrada, lidos com o FFprobe.
class VideoInfo {
  const VideoInfo({
    required this.path,
    required this.fileName,
    required this.rawWidth,
    required this.rawHeight,
    required this.durationSeconds,
    required this.frameRate,
    required this.bitrateBps,
    required this.fileSizeBytes,
    required this.codec,
    this.rotationDegrees = 0,
  });

  final String path;
  final String fileName;

  /// Dimensões como estão gravadas no arquivo, sem aplicar rotação.
  final int rawWidth;
  final int rawHeight;

  final double durationSeconds;
  final double frameRate;
  final int bitrateBps;
  final int fileSizeBytes;
  final String codec;

  /// Vídeos de celular costumam vir com metadado de rotação (90/180/270).
  /// O FFmpeg já aplica essa rotação ao decodificar, então as dimensões que
  /// interessam para recorte e escala são as de exibição, não as brutas.
  final int rotationDegrees;

  bool get _isSideways =>
      rotationDegrees == 90 || rotationDegrees == 270 || rotationDegrees == -90;

  int get width => _isSideways ? rawHeight : rawWidth;
  int get height => _isSideways ? rawWidth : rawHeight;

  double get aspectRatio => height == 0 ? 1 : width / height;

  bool get isPortrait => height > width;

  /// Bits por pixel por quadro do vídeo original. Serve como pista grosseira
  /// de "quanta informação" a cena tem, usada quando ainda não houve
  /// calibração real (ver [SizeEstimator.profileFromSource]).
  double get sourceBitsPerPixel {
    final pixelsPerSecond = width * height * math.max(frameRate, 1.0);
    if (pixelsPerSecond <= 0 || bitrateBps <= 0) return 0;
    return bitrateBps / pixelsPerSecond;
  }
}
