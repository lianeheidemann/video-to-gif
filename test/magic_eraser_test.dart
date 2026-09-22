import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/features/photo/models/eraser_mask.dart';
import 'package:video_to_gif/core/models/photo_info.dart';
import 'package:video_to_gif/features/photo/services/magic_eraser.dart';

/// Escreve um PNG de fundo listrado com um quadrado vermelho no meio — o
/// "objeto" a ser apagado. Listras porque cor chapada esconderia um
/// preenchimento ruim: com textura dá para ver se o fundo foi realmente
/// reconstruído.
Future<void> _writePhoto(String path, int size, Rect blob) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var x = 0; x < size; x += 16) {
    canvas.drawRect(
      Rect.fromLTWH(x.toDouble(), 0, 8, size.toDouble()),
      Paint()..color = const Color(0xFF204060),
    );
    canvas.drawRect(
      Rect.fromLTWH(x + 8.0, 0, 8, size.toDouble()),
      Paint()..color = const Color(0xFF80A0C0),
    );
  }
  canvas.drawRect(blob, Paint()..color = const Color(0xFFFF0000));

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Ruído colorido: um fundo sem nenhuma estrutura repetida, onde a escolha
/// aleatória de patches realmente muda o resultado.
Future<void> _writeNoisyPhoto(String path, int size) async {
  final random = math.Random(3);
  final rgba = Uint8List(size * size * 4);
  for (var i = 0; i < size * size; i++) {
    rgba[i * 4] = random.nextInt(256);
    rgba[i * 4 + 1] = random.nextInt(256);
    rgba[i * 4 + 2] = random.nextInt(256);
    rgba[i * 4 + 3] = 255;
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    size,
    size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<({int width, int height, Uint8List rgba})> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (
      width: image.width,
      height: image.height,
      rgba: data!.buffer.asUint8List(),
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

({int r, int g, int b}) _pixel(
  ({int width, int height, Uint8List rgba}) img,
  int x,
  int y,
) {
  final i = (y * img.width + x) * 4;
  return (r: img.rgba[i], g: img.rgba[i + 1], b: img.rgba[i + 2]);
}

void main() {
  // O caminho inteiro (decodificar, recortar, Isolate, recompor, PNG) precisa
  // da engine — e de tempo real, por causa do Isolate. Daí `test`, não
  // `testWidgets`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PhotoInfo photo;
  const size = 200;
  const blob = Rect.fromLTWH(80, 80, 40, 40);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('magic_eraser_test');
    final path = '${tempDir.path}/foto.png';
    await _writePhoto(path, size, blob);
    photo = PhotoInfo(path: path, width: size, height: size);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  EraserMask maskOverBlob() => EraserMask.empty.add(
    const EraserStroke(
      points: [
        Offset(78, 78),
        Offset(122, 78),
        Offset(122, 122),
        Offset(78, 122),
      ],
      closed: true,
    ),
  );

  test('apaga o objeto e devolve a foto no tamanho original', () async {
    final png = await startMagicErase(
      photo: photo,
      mask: maskOverBlob(),
      quality: EraserQuality.fast,
    ).done;

    final out = await _decode(png);

    // O tamanho não pode mudar: o recorte da aba "Recorte" está em pixels da
    // foto e ficaria desalinhado.
    expect(out.width, size);
    expect(out.height, size);

    // O quadrado vermelho sumiu. "Vermelho" aqui é o canal R dominando com
    // folga — o fundo listrado é azulado dos dois lados.
    final centre = _pixel(out, 100, 100);
    expect(
      centre.r,
      lessThan(centre.b),
      reason: 'o centro ainda parece vermelho: $centre',
    );
  });

  test('nada fora da seleção é alterado', () async {
    final before = await _decode(await File(photo.path).readAsBytes());
    final png = await startMagicErase(
      photo: photo,
      mask: maskOverBlob(),
      quality: EraserQuality.fast,
    ).done;
    final after = await _decode(png);

    // Longe da máscara (o pedaço apagado fica em 78..122) a foto tem que sair
    // byte a byte igual: a recomposição desenha o original inteiro e só
    // recorta o preenchimento dentro da máscara.
    for (final point in [
      const Offset(10, 10),
      const Offset(190, 10),
      const Offset(10, 190),
      const Offset(190, 190),
      const Offset(100, 20),
      const Offset(20, 100),
    ]) {
      final x = point.dx.toInt();
      final y = point.dy.toInt();
      expect(
        _pixel(after, x, y),
        _pixel(before, x, y),
        reason: 'pixel ($x, $y) mudou fora da seleção',
      );
    }
  });

  test('a semente chega até o algoritmo', () async {
    // Precisa de um fundo sem padrão: sobre as listras do resto deste
    // arquivo, qualquer semente converge para a mesma resposta exata (a
    // listra continua onde tem que continuar, e todo patch que casa perfeito
    // dá a mesma cor) — o que é ótimo sinal de qualidade, mas não testaria
    // nada aqui.
    final noisyPath = '${tempDir.path}/ruido.png';
    await _writeNoisyPhoto(noisyPath, 160);
    final noisy = PhotoInfo(path: noisyPath, width: 160, height: 160);

    Future<Uint8List> run(int seed) => startMagicErase(
      photo: noisy,
      mask: EraserMask.empty.add(
        const EraserStroke(
          points: [
            Offset(60, 60),
            Offset(100, 60),
            Offset(100, 100),
            Offset(60, 100),
          ],
          closed: true,
        ),
      ),
      quality: EraserQuality.fast,
      seed: seed,
    ).done;

    // É disso que o botão "Tentar de novo" depende: se a semente não mudasse
    // nada, o botão seria uma mentira.
    expect(await run(1), isNot(equals(await run(2))));
  });

  test('o progresso chega até o fim', () async {
    final seen = <double>[];
    await startMagicErase(
      photo: photo,
      mask: maskOverBlob(),
      quality: EraserQuality.fast,
      onProgress: seen.add,
    ).done;

    expect(seen, isNotEmpty);
    expect(seen.every((v) => v >= 0 && v <= 1), isTrue);
    expect(seen.last, closeTo(1, 1e-9));
  });

  test('seleção vazia falha com mensagem, em vez de gerar lixo', () async {
    expect(
      startMagicErase(
        photo: photo,
        mask: EraserMask.empty,
        quality: EraserQuality.fast,
      ).done,
      throwsA(isA<MagicEraserException>()),
    );
  });

  test('cancelar interrompe com MagicEraserCancelled', () async {
    final task = startMagicErase(
      photo: photo,
      mask: maskOverBlob(),
      quality: EraserQuality.high,
    );
    task.cancel();

    expect(task.isCancelled, isTrue);
    await expectLater(task.done, throwsA(isA<MagicEraserCancelled>()));
  });
}
