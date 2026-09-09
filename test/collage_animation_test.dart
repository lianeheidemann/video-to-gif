import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Canvas, Color, Paint, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_cell.dart';
import 'package:video_to_gif/models/collage_export.dart';
import 'package:video_to_gif/models/collage_layout.dart';
import 'package:video_to_gif/models/collage_settings.dart';
import 'package:video_to_gif/services/collage_animation.dart';

/// PNG sólido: uma foto parada de verdade em disco.
Future<void> _writeSolidPng(String path, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 40, 40), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 40);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// GIF animado mínimo, montado à mão: [frames] quadros de 40x40, cada um de
/// uma cor da tabela global, com [delayCentiseconds] de atraso por quadro.
/// Escrever os bytes na mão evita depender de qualquer encoder no teste.
Future<void> _writeAnimatedGif(
  String path, {
  required int frames,
  required int delayCentiseconds,
}) async {
  final bytes = BytesBuilder();
  void byte(int value) => bytes.addByte(value);
  void short(int value) {
    bytes.addByte(value & 0xFF);
    bytes.addByte((value >> 8) & 0xFF);
  }

  bytes.add('GIF89a'.codeUnits);
  short(40); // largura
  short(40); // altura
  byte(0x80 | 0x01); // tabela global de 4 cores
  byte(0); // índice de fundo
  byte(0); // proporção do pixel
  // 4 cores: vermelho, verde, azul, branco.
  for (final color in [
    [255, 0, 0],
    [0, 255, 0],
    [0, 0, 255],
    [255, 255, 255],
  ]) {
    for (final channel in color) {
      byte(channel);
    }
  }

  bytes.add([0x21, 0xFF, 0x0B]); // extensão de aplicação (loop infinito)
  bytes.add('NETSCAPE2.0'.codeUnits);
  bytes.add([0x03, 0x01]);
  short(0);
  byte(0);

  for (var i = 0; i < frames; i++) {
    bytes.add([0x21, 0xF9, 0x04, 0x00]); // controle gráfico
    short(delayCentiseconds);
    bytes.add([0x00, 0x00]);

    byte(0x2C); // descritor de imagem
    short(0);
    short(0);
    short(40);
    short(40);
    byte(0);

    // Bloco LZW sem compressão de verdade: com o código mínimo de 2 bits, os
    // códigos têm 3 bits e a tabela cresce a cada par de literais — mandar um
    // "clear" (4) a cada 2 pixels reseta a tabela antes de o código precisar
    // de 4 bits, então a largura fica fixa em 3 bits o arquivo inteiro. É a
    // saída legal mais simples possível, e todo decodificador aceita.
    byte(2); // tamanho mínimo do código LZW
    final codes = <int>[];
    for (var p = 0; p < 1600; p += 2) {
      codes.add(4); // clear
      codes.add(i % 4);
      codes.add(i % 4);
    }
    codes.add(5); // fim da informação
    final bits = <int>[];
    for (final code in codes) {
      for (var b = 0; b < 3; b++) {
        bits.add((code >> b) & 1);
      }
    }
    final data = <int>[];
    for (var b = 0; b < bits.length; b += 8) {
      var value = 0;
      for (var k = 0; k < 8 && b + k < bits.length; k++) {
        value |= bits[b + k] << k;
      }
      data.add(value);
    }
    for (var offset = 0; offset < data.length; offset += 255) {
      final chunk = data.sublist(
        offset,
        offset + 255 > data.length ? data.length : offset + 255,
      );
      byte(chunk.length);
      bytes.add(chunk);
    }
    byte(0); // fim dos blocos
  }

  byte(0x3B); // fim do GIF
  await File(path).writeAsBytes(bytes.toBytes());
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('collage_animation_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  CollageSettings settingsWith(List<String> paths) => CollageSettings(
    layout: CollageLayout.row(paths.length),
    aspectRatio: paths.length.toDouble(),
    outerMarginRatio: 0,
    innerMarginRatio: 0,
    cells: [
      for (final path in paths)
        CollageCellSettings(photoPath: path, photoWidth: 40, photoHeight: 40),
    ],
  );

  test('montagem só com fotos paradas não tem animação nenhuma', () async {
    final path = '${tempDir.path}/parada.png';
    await _writeSolidPng(path, const Color(0xFFFF0000));

    final info = await inspectCollageAnimation(settingsWith([path]));
    expect(info.hasAnimation, isFalse);
    expect(info.animatedCount, 0);
  });

  test('reconhece o GIF animado e mede a duração', () async {
    final gif = '${tempDir.path}/curto.gif';
    await _writeAnimatedGif(gif, frames: 4, delayCentiseconds: 10);

    final info = await inspectCollageAnimation(settingsWith([gif]));
    expect(info.hasAnimation, isTrue);
    expect(info.animatedCount, 1);
    // 4 quadros de 100ms.
    expect(info.longest.inMilliseconds, 400);
    expect(info.shortest.inMilliseconds, 400);
    expect(info.hasDifferentDurations, isFalse);
  });

  test(
    'durações diferentes: a mais longa e a mais curta são separadas',
    () async {
      final curto = '${tempDir.path}/curto.gif';
      final longo = '${tempDir.path}/longo.gif';
      await _writeAnimatedGif(curto, frames: 2, delayCentiseconds: 10);
      await _writeAnimatedGif(longo, frames: 6, delayCentiseconds: 10);

      final info = await inspectCollageAnimation(settingsWith([curto, longo]));
      expect(info.animatedCount, 2);
      expect(info.shortest.inMilliseconds, 200);
      expect(info.longest.inMilliseconds, 600);
      expect(info.hasDifferentDurations, isTrue);
      expect(
        info.durationFor(CollageDurationRule.shortest).inMilliseconds,
        200,
      );
      expect(info.durationFor(CollageDurationRule.longest).inMilliseconds, 600);
    },
  );

  test('"a mais longa" rende mais quadros que "a mais curta"', () async {
    final curto = '${tempDir.path}/curto.gif';
    final longo = '${tempDir.path}/longo.gif';
    await _writeAnimatedGif(curto, frames: 2, delayCentiseconds: 10);
    await _writeAnimatedGif(longo, frames: 8, delayCentiseconds: 10);
    final settings = settingsWith([curto, longo]);

    final longDir = await Directory('${tempDir.path}/longa').create();
    final longSeq = await renderCollageFrames(
      settings: settings,
      outputWidth: 40,
      rule: CollageDurationRule.longest,
      workDir: longDir,
    );

    final shortDir = await Directory('${tempDir.path}/curta').create();
    final shortSeq = await renderCollageFrames(
      settings: settings,
      outputWidth: 40,
      rule: CollageDurationRule.shortest,
      workDir: shortDir,
    );

    expect(longSeq.frameCount, greaterThan(shortSeq.frameCount));
    // Os PNGs saíram mesmo em disco, numerados para o FFmpeg.
    expect(longDir.listSync().whereType<File>().length, longSeq.frameCount);
    expect(longSeq.pattern, endsWith('quadro_%05d.png'));
    expect(longSeq.fps, greaterThanOrEqualTo(5));
  });

  test('a animação curta segura o último quadro em vez de sumir', () async {
    // Curto (2 quadros = 200ms) ao lado de longo (8 quadros = 800ms): depois
    // dos 200ms, os quadros da montagem continuam mostrando o ÚLTIMO quadro
    // do curto — nada de sumir, piscar ou reiniciar. Comparando o pedaço da
    // esquerda (foto curta) do primeiro quadro depois do fim com o do último
    // quadro da montagem, os dois têm que ser idênticos.
    final curto = '${tempDir.path}/curto.gif';
    final longo = '${tempDir.path}/longo.gif';
    await _writeAnimatedGif(curto, frames: 2, delayCentiseconds: 10);
    await _writeAnimatedGif(longo, frames: 8, delayCentiseconds: 10);

    final workDir = await Directory('${tempDir.path}/quadros').create();
    final sequence = await renderCollageFrames(
      settings: settingsWith([curto, longo]),
      outputWidth: 80,
      rule: CollageDurationRule.longest,
      workDir: workDir,
    );

    final files = workDir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, sequence.frameCount);

    Future<List<int>> leftPixel(File file) async {
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        // Metade esquerda do canvas = a foto curta.
        final offset = (10 * frame.image.width + 10) * 4;
        return [
          data!.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
          data.getUint8(offset + 3),
        ];
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    }

    final afterEnd = await leftPixel(files[files.length ~/ 2]);
    final last = await leftPixel(files.last);
    expect(afterEnd[3], 255, reason: 'a foto curta não pode sumir no fim');
    expect(last, afterEnd);
  });
}
