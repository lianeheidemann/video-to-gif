// Leitura da rotação de um vídeo MP4/MOV direto do container, sem FFmpeg.
//
// Serve de desempate no `probe()`: existe vídeo de celular cuja rotação só
// está na matriz de exibição do `tkhd`, sem a tag legada `rotate`, e que o
// FFprobe pode não expor. Sem isso, um vídeo gravado em pé é tratado como
// deitado e sai achatado na prévia e na exportação.
//
// Dart puro, sem Flutter nem FFmpeg, para poder ser testado sem emulador —
// mesmo espírito de `size_estimator.dart`.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Rotação em graus (0, 90, 180 ou 270) da faixa de vídeo de [path].
///
/// Devolve `null` quando não dá para afirmar nada: o arquivo não é MP4/MOV,
/// não tem `moov`, está truncado ou não tem faixa de vídeo. Quem chama trata
/// `null` como "não sei", e não como "sem rotação".
Future<int?> readMp4Rotation(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final moov = await _readMoov(file, await file.length());
    if (moov == null) return null;
    return _rotationFromMoov(moov);
  } catch (_) {
    // Arquivo ilegível, truncado ou com caixa malformada: seguir sem palpite
    // é melhor que derrubar a abertura do vídeo.
    return null;
  } finally {
    await file?.close();
  }
}

/// Uma caixa do MP4: onde o conteúdo começa e onde a caixa acaba.
class _Box {
  const _Box(this.type, this.start, this.end);

  final String type;

  /// Primeiro byte do conteúdo, já depois do cabeçalho.
  final int start;

  /// Primeiro byte depois da caixa.
  final int end;
}

/// Acha o `moov` percorrendo só os cabeçalhos do nível de cima e lê apenas
/// ele.
///
/// O `moov` costuma vir depois do `mdat`, que carrega o vídeo inteiro — num
/// arquivo de 8 MB o `moov` são os últimos 5 KB. Ler o arquivo todo para
/// chegar nele estouraria a memória num vídeo longo.
Future<Uint8List?> _readMoov(RandomAccessFile file, int length) async {
  var offset = 0;
  while (offset + 8 <= length) {
    await file.setPosition(offset);
    final header = await file.read(8);
    if (header.length < 8) return null;

    final view = ByteData.sublistView(header);
    var size = view.getUint32(0);
    final type = String.fromCharCodes(header.sublist(4, 8));
    var contentStart = offset + 8;

    if (size == 1) {
      // Tamanho de 64 bits, guardado logo depois do tipo.
      final large = await file.read(8);
      if (large.length < 8) return null;
      size = ByteData.sublistView(large).getUint64(0);
      contentStart = offset + 16;
    } else if (size == 0) {
      // "Vai até o fim do arquivo" — só é válido na última caixa.
      size = length - offset;
    }

    // Caixa menor que o próprio cabeçalho faria o laço andar para trás e
    // nunca terminar.
    if (size < 8) return null;

    if (type == 'moov') {
      await file.setPosition(contentStart);
      final bytes = await file.read(offset + size - contentStart);
      return bytes.isEmpty ? null : bytes;
    }
    offset += size;
  }
  return null;
}

/// Caixas filhas dentro de [bytes], entre [start] e [end].
List<_Box> _children(Uint8List bytes, int start, int end) {
  final boxes = <_Box>[];
  final view = ByteData.sublistView(bytes);
  var offset = start;

  while (offset + 8 <= end) {
    var size = view.getUint32(offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    var contentStart = offset + 8;

    if (size == 1) {
      if (offset + 16 > end) break;
      size = view.getUint64(offset + 8);
      contentStart = offset + 16;
    } else if (size == 0) {
      size = end - offset;
    }
    if (size < 8 || offset + size > end) break;

    boxes.add(_Box(type, contentStart, offset + size));
    offset += size;
  }
  return boxes;
}

_Box? _find(List<_Box> boxes, String type) {
  for (final box in boxes) {
    if (box.type == type) return box;
  }
  return null;
}

/// Rotação da faixa de vídeo, ou `null` quando o `moov` não tem uma.
int? _rotationFromMoov(Uint8List moov) {
  for (final trak in _children(moov, 0, moov.length)) {
    if (trak.type != 'trak') continue;

    final filhos = _children(moov, trak.start, trak.end);
    // A faixa certa é a de vídeo: um MP4 com áudio tem outro `tkhd`, com
    // matriz identidade, que responderia 0 e mascararia a rotação.
    if (!_isVideoTrack(moov, filhos)) continue;

    final tkhd = _find(filhos, 'tkhd');
    if (tkhd == null) continue;
    return _rotationFromTkhd(moov, tkhd);
  }
  return null;
}

bool _isVideoTrack(Uint8List moov, List<_Box> trakChildren) {
  final mdia = _find(trakChildren, 'mdia');
  if (mdia == null) return false;

  final hdlr = _find(_children(moov, mdia.start, mdia.end), 'hdlr');
  if (hdlr == null) return false;

  // hdlr: versão+flags (4) + pre_defined (4) + handler_type (4).
  final handlerAt = hdlr.start + 8;
  if (handlerAt + 4 > hdlr.end) return false;
  return String.fromCharCodes(moov.sublist(handlerAt, handlerAt + 4)) == 'vide';
}

/// Ângulo tirado da matriz de exibição do `tkhd`.
///
/// Os campos antes da matriz mudam de tamanho entre a versão 0 e a 1 da
/// caixa, daí a conta do deslocamento em vez de um número fixo.
int? _rotationFromTkhd(Uint8List moov, _Box tkhd) {
  final version = moov[tkhd.start];

  var offset = tkhd.start + 4; // versão + flags
  offset += version == 1 ? 16 : 8; // criação + modificação
  offset += 4; // track_id
  offset += 4; // reservado
  offset += version == 1 ? 8 : 4; // duração
  offset += 8; // reservado
  offset += 8; // layer, alternate_group, volume, reservado

  if (offset + 36 > tkhd.end) return null;

  final view = ByteData.sublistView(moov);
  // Os dois primeiros valores da matriz, em ponto fixo 16.16.
  final a = view.getInt32(offset) / 65536.0;
  final b = view.getInt32(offset + 4) / 65536.0;
  if (a == 0 && b == 0) return null;

  final degrees = math.atan2(b, a) * 180 / math.pi;
  return _normalize(degrees.round());
}

/// Arredonda para o múltiplo de 90 mais próximo e traz para 0..359.
int _normalize(int degrees) {
  final quarter = ((degrees / 90).round() * 90) % 360;
  return (quarter + 360) % 360;
}
