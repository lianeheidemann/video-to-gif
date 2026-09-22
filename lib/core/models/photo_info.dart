/// Metadados mínimos de uma foto escolhida para receber uma moldura: só o
/// caminho e as dimensões nativas, lidas localmente com
/// `ui.instantiateImageCodec` — ao contrário de `VideoInfo`, não há nada
/// para "sondar" com FFprobe, então este modelo não precisa de codec,
/// bitrate ou duração.
class PhotoInfo {
  const PhotoInfo({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;
}
