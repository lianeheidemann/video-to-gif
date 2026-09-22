/// Metadados mínimos de um SVG escolhido para edição: só o caminho e o
/// tamanho intrínseco, lido do próprio `flutter_svg`
/// (`PictureInfo.size`) — nunca reparseado na mão a partir dos atributos
/// `width`/`height` do XML, que podem ser ausentes, percentuais ou não
/// coincidir com o `viewBox`. Mesmo espírito de `PhotoInfo`, mas com
/// dimensões em `double` (um SVG não tem "pixels" nativos).
class SvgInfo {
  const SvgInfo({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final double width;
  final double height;

  double get aspectRatio => height == 0 ? 1 : width / height;
}
