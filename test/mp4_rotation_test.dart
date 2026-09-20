import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/services/mp4_rotation.dart';

/// Monta uma caixa do MP4: tamanho de 32 bits, tipo e conteúdo.
Uint8List _box(String type, List<int> payload) {
  final size = 8 + payload.length;
  return Uint8List.fromList([
    (size >> 24) & 0xFF,
    (size >> 16) & 0xFF,
    (size >> 8) & 0xFF,
    size & 0xFF,
    ...type.codeUnits,
    ...payload,
  ]);
}

/// Caixa com tamanho de 64 bits: o campo de 32 bits vale 1 e o tamanho real
/// vem logo depois do tipo.
Uint8List _box64(String type, List<int> payload) {
  final size = 16 + payload.length;
  return Uint8List.fromList([
    0,
    0,
    0,
    1,
    ...type.codeUnits,
    0,
    0,
    0,
    0,
    (size >> 24) & 0xFF,
    (size >> 16) & 0xFF,
    (size >> 8) & 0xFF,
    size & 0xFF,
    ...payload,
  ]);
}

List<int> _int32(int value) {
  final data = ByteData(4)..setInt32(0, value);
  return data.buffer.asUint8List();
}

/// Matriz de exibição 3x3 em ponto fixo 16.16, para o ângulo pedido.
List<int> _matrix(int degrees) {
  const one = 65536;
  final (a, b, c, d) = switch (degrees) {
    90 => (0, one, -one, 0),
    180 => (-one, 0, 0, -one),
    270 => (0, -one, one, 0),
    _ => (one, 0, 0, one),
  };
  return [
    ..._int32(a),
    ..._int32(b),
    ..._int32(0),
    ..._int32(c),
    ..._int32(d),
    ..._int32(0),
    ..._int32(0),
    ..._int32(0),
    ..._int32(1 << 30),
  ];
}

/// `tkhd` versão 0 com a matriz do ângulo pedido.
Uint8List _tkhd(int degrees) => _box('tkhd', [
  0, 0, 0, 0, // versão 0 + flags
  ...List.filled(8, 0), // criação + modificação
  ...List.filled(4, 0), // track_id
  ...List.filled(4, 0), // reservado
  ...List.filled(4, 0), // duração
  ...List.filled(8, 0), // reservado
  ...List.filled(8, 0), // layer, grupo, volume, reservado
  ..._matrix(degrees),
  ...List.filled(8, 0), // largura + altura de exibição
]);

Uint8List _hdlr(String handler) => _box('hdlr', [
  0, 0, 0, 0, // versão + flags
  0, 0, 0, 0, // pre_defined
  ...handler.codeUnits,
  ...List.filled(12, 0), // reservado
  0, // nome vazio
]);

Uint8List _trak(String handler, int degrees) => _box('trak', [
  ..._tkhd(degrees),
  ..._box('mdia', [..._hdlr(handler)]),
]);

/// Arquivo completo. `moovNoFim` reproduz o caso real: o `moov` depois de um
/// `mdat` grande, que é onde um leitor ingênuo se perde.
Uint8List _mp4(List<Uint8List> traks, {bool moovNoFim = false, int mdat = 64}) {
  final ftyp = _box('ftyp', 'mp42'.codeUnits + List.filled(8, 0));
  final moov = _box('moov', [for (final t in traks) ...t]);
  final dados = _box('mdat', List.filled(mdat, 9));
  return Uint8List.fromList(
    moovNoFim ? [...ftyp, ...dados, ...moov] : [...ftyp, ...moov, ...dados],
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mp4_rotation');
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<int?> ler(Uint8List bytes) async {
    final file = File('${tempDir.path}/v.mp4');
    await file.writeAsBytes(bytes);
    return readMp4Rotation(file.path);
  }

  group('matriz de exibição', () {
    test('lê os quatro ângulos', () async {
      for (final graus in [0, 90, 180, 270]) {
        expect(
          await ler(_mp4([_trak('vide', graus)])),
          graus,
          reason: 'matriz de $graus°',
        );
      }
    });

    test('acha o moov quando ele vem depois do mdat', () async {
      // É o caso do arquivo que gerou o bug: 8,7 MB de mdat antes do moov.
      expect(
        await ler(_mp4([_trak('vide', 90)], moovNoFim: true, mdat: 5000)),
        90,
      );
    });

    test('atravessa caixa com tamanho de 64 bits', () async {
      final ftyp = _box('ftyp', 'mp42'.codeUnits + List.filled(8, 0));
      final mdat = _box64('mdat', List.filled(128, 9));
      final moov = _box('moov', [..._trak('vide', 270)]);
      expect(await ler(Uint8List.fromList([...ftyp, ...mdat, ...moov])), 270);
    });
  });

  group('escolha da faixa', () {
    test('usa a faixa de vídeo, não a de áudio que vem antes', () async {
      // A faixa de áudio tem matriz identidade: pegar a primeira faixa
      // responderia 0 e esconderia a rotação do vídeo.
      expect(await ler(_mp4([_trak('soun', 0), _trak('vide', 90)])), 90);
    });

    test('sem faixa de vídeo, não arrisca palpite', () async {
      expect(await ler(_mp4([_trak('soun', 0)])), isNull);
    });
  });

  group('arquivo que não serve', () {
    test('conteúdo que não é MP4', () async {
      expect(await ler(Uint8List.fromList(List.filled(4096, 7))), isNull);
    });

    test('arquivo vazio', () async {
      expect(await ler(Uint8List(0)), isNull);
    });

    test('moov truncado no meio', () async {
      // Com o moov no fim, cortar o fim corta o próprio moov. (Cortar um
      // arquivo cujo moov está no começo não é truncar o moov: ali a
      // rotação continua legível, e o leitor deve devolvê-la.)
      final inteiro = _mp4([_trak('vide', 90)], moovNoFim: true);
      expect(await ler(inteiro.sublist(0, inteiro.length - 40)), isNull);
    });

    test('corte que só atinge o mdat ainda devolve a rotação', () async {
      final inteiro = _mp4([_trak('vide', 90)], mdat: 200);
      expect(await ler(inteiro.sublist(0, inteiro.length - 40)), 90);
    });

    test('caixa com tamanho menor que o cabeçalho não trava', () async {
      // Tamanho 3 faria o laço andar para trás e nunca terminar.
      final quebrado = Uint8List.fromList([
        0,
        0,
        0,
        3,
        ...'ftyp'.codeUnits,
        ...List.filled(32, 0),
      ]);
      expect(await ler(quebrado), isNull);
    });

    test('arquivo que não existe', () async {
      expect(await readMp4Rotation('${tempDir.path}/nao_existe.mp4'), isNull);
    });
  });
}
