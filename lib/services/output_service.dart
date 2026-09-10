import 'dart:io';

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// Salvar na galeria e compartilhar o GIF pronto.
class OutputService {
  const OutputService();

  static const _albumName = 'Video to GIF';

  /// Salva na galeria do aparelho, pedindo permissão se ainda não tiver.
  ///
  /// [asVideo] usa `Gal.putVideo` em vez de `Gal.putImage` — necessário para
  /// os formatos de vídeo de verdade (MP4/WebM/MOV) que "Converter formato"
  /// também gera, além do GIF/WebP animados de sempre.
  ///
  /// Lança [OutputException] com uma mensagem em português quando o usuário
  /// nega o acesso — é o erro que mais aparece na prática.
  Future<void> saveToGallery(File gif, {bool asVideo = false}) async {
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw OutputException(
          'Sem permissão para salvar na galeria. Você pode liberar em '
          'Ajustes > Apps > Video to GIF > Permissões.',
        );
      }
    }

    try {
      if (asVideo) {
        await Gal.putVideo(gif.path, album: _albumName);
      } else {
        await Gal.putImage(gif.path, album: _albumName);
      }
    } on GalException catch (e) {
      throw OutputException(
        'Não foi possível salvar na galeria: ${e.type.message}',
      );
    }
  }

  /// Abre a folha de compartilhamento do sistema com o arquivo anexado.
  /// [mimeType]/[text] têm o padrão do GIF de vídeo; a tela de moldura em
  /// foto passa os equivalentes para PNG.
  Future<void> share(
    File file, {
    String mimeType = 'image/gif',
    String text = 'GIF feito com o app Video to GIF',
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        text: text,
      ),
    );
  }
}

class OutputException implements Exception {
  OutputException(this.message);

  final String message;

  @override
  String toString() => message;
}
