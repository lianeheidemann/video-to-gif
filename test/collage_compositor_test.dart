import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dart:math' as math;

import 'package:flutter/material.dart' show Canvas, Color, Paint, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_background.dart';
import 'package:video_to_gif/models/collage_cell.dart';
import 'package:video_to_gif/models/collage_layout.dart';
import 'package:video_to_gif/models/collage_settings.dart';
import 'package:video_to_gif/models/collage_text.dart';
import 'package:video_to_gif/services/collage_compositor.dart';

/// Grava um PNG sólido de [width]x[height] na cor [color] em [path] — usado
/// para ter fotos "de verdade" em disco para o compositor decodificar, sem
/// depender de nenhum asset do repositório.
Future<void> _writeSolidPng(
  String path,
  int width,
  int height,
  Color color,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Grava um PNG de [width]x[height] vermelho com uma faixa vertical verde em
/// `x` dentro de `[bandStart, bandEnd)` — usado para saber exatamente qual
/// pedaço da imagem de fundo entrou no recorte "cover".
Future<void> _writeBandedPng(
  String path,
  int width,
  int height,
  int bandStart,
  int bandEnd,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    Rect.fromLTWH(
      bandStart.toDouble(),
      0,
      (bandEnd - bandStart).toDouble(),
      height.toDouble(),
    ),
    Paint()..color = const Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Lê o pixel (R,G,B,A) em (x,y) de um PNG já em memória, decodificando com
/// `dart:ui` — mesma técnica de `frame_painter_test.dart`.
Future<List<int>> _decodePixel(
  Uint8List pngBytes,
  int width,
  int x,
  int y,
) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final offset = (y * width + x) * 4;
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

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('collage_compositor_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'PNG de saída tem exatamente a largura pedida e a altura pela proporção',
    () async {
      final photoPath = '${tempDir.path}/foto.png';
      await _writeSolidPng(photoPath, 100, 100, const Color(0xFFFF0000));

      final settings = CollageSettings(
        layout: CollageLayout.row(1),
        aspectRatio: 2.0,
        cells: [
          CollageCellSettings(
            photoPath: photoPath,
            photoWidth: 100,
            photoHeight: 100,
          ),
        ],
      );

      final bytes = await composeCollage(settings: settings, outputWidth: 300);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      try {
        expect(frame.image.width, 300);
        expect(frame.image.height, 150);
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    },
  );

  test(
    'duas fotos lado a lado com fundo sólido: pixels batem com cada foto e o fundo',
    () async {
      final redPath = '${tempDir.path}/vermelho.png';
      final bluePath = '${tempDir.path}/azul.png';
      await _writeSolidPng(redPath, 50, 50, const Color(0xFFFF0000));
      await _writeSolidPng(bluePath, 50, 50, const Color(0xFF0000FF));

      final settings = CollageSettings(
        layout: CollageLayout.row(2),
        aspectRatio: 2.0,
        outerMarginRatio: 0.1,
        innerMarginRatio: 0.1,
        background: const CollageBackground(
          mode: CollageBackgroundMode.color,
          color: Color(0xFF00FF00),
        ),
        cells: [
          CollageCellSettings(
            photoPath: redPath,
            photoWidth: 50,
            photoHeight: 50,
          ),
          CollageCellSettings(
            photoPath: bluePath,
            photoWidth: 50,
            photoHeight: 50,
          ),
        ],
      );

      const outputWidth = 200;
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: outputWidth,
      );

      // canvas 200x100 (aspectRatio 2.0), margem = shortestSide(100)*0.1 = 10.
      // célula 0: x em [10,95], y em [10,90] — amostra bem no meio dela.
      final leftPixel = await _decodePixel(bytes, outputWidth, 50, 50);
      expect(leftPixel[0], greaterThan(200)); // R alto
      expect(leftPixel[2], lessThan(50)); // B baixo

      // célula 1: x em [105,190], y em [10,90].
      final rightPixel = await _decodePixel(bytes, outputWidth, 150, 50);
      expect(rightPixel[2], greaterThan(200)); // B alto (foto azul)
      expect(rightPixel[0], lessThan(50)); // R baixo

      // Canto (2,2): fora das duas células, dentro da margem — mostra o fundo.
      final cornerPixel = await _decodePixel(bytes, outputWidth, 2, 2);
      expect(cornerPixel[1], greaterThan(200)); // G alto (fundo verde)
    },
  );

  test(
    'borda com fundo transparente não vaza para dentro da montagem',
    () async {
      final photoPath = '${tempDir.path}/foto.png';
      await _writeSolidPng(photoPath, 50, 50, const Color(0xFFFF0000));

      final settings = CollageSettings(
        layout: CollageLayout.row(2),
        aspectRatio: 2.0,
        outerMarginRatio: 0.1,
        innerMarginRatio: 0.1,
        borderThicknessAtReference: 24,
        borderColor: const Color(0xFF00FF00),
        cells: [
          CollageCellSettings(
            photoPath: photoPath,
            photoWidth: 50,
            photoHeight: 50,
          ),
          CollageCellSettings(
            photoPath: photoPath,
            photoWidth: 50,
            photoHeight: 50,
          ),
        ],
      );

      const outputWidth = 480;
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: outputWidth,
      );

      // Canvas 480x240, borda de 24px: o anel é verde...
      final ringPixel = await _decodePixel(bytes, outputWidth, 4, 120);
      expect(ringPixel[1], greaterThan(200));
      expect(ringPixel[3], 255);

      // ...mas a margem entre as duas fotos continua transparente, como pede
      // o modo "Fundo transparente" (antes a borda pintava o canvas inteiro).
      final gapPixel = await _decodePixel(bytes, outputWidth, 240, 120);
      expect(gapPixel[3], 0);
    },
  );

  test(
    'fundo de imagem é enquadrado pela área interna, como na prévia',
    () async {
      // Faixa verde estreita perto da esquerda de uma imagem bem larga: ela só
      // entra no recorte "cover" se ele for calculado contra a área interna
      // (dentro da borda), que é o que a prévia mostra. Calculado contra o
      // canvas inteiro, o recorte é mais apertado e a faixa fica de fora.
      final backgroundPath = '${tempDir.path}/fundo.png';
      await _writeBandedPng(backgroundPath, 400, 100, 90, 105);

      final settings = CollageSettings(
        layout: CollageLayout.row(1),
        aspectRatio: 2.0,
        outerMarginRatio: 0,
        innerMarginRatio: 0,
        borderThicknessAtReference: 24,
        borderColor: const Color(0xFF000000),
        background: CollageBackground(
          mode: CollageBackgroundMode.image,
          imagePath: backgroundPath,
        ),
        cells: const [CollageCellSettings()],
      );

      const outputWidth = 480;
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: outputWidth,
      );

      final bandPixel = await _decodePixel(bytes, outputWidth, 44, 120);
      expect(bandPixel[1], greaterThan(200)); // G alto: a faixa está visível
      expect(bandPixel[0], lessThan(60));

      // Fora da faixa o fundo é vermelho, nos dois enquadramentos — confirma
      // que a imagem foi mesmo desenhada.
      final outsidePixel = await _decodePixel(bytes, outputWidth, 240, 120);
      expect(outsidePixel[0], greaterThan(200));
    },
  );

  test(
    'arquivo que sumiu do aparelho não derruba a exportação inteira',
    () async {
      final presentPath = '${tempDir.path}/presente.png';
      await _writeSolidPng(presentPath, 50, 50, const Color(0xFFFF0000));

      final settings = CollageSettings(
        layout: CollageLayout.row(2),
        aspectRatio: 2.0,
        outerMarginRatio: 0.1,
        innerMarginRatio: 0.1,
        background: const CollageBackground(
          mode: CollageBackgroundMode.color,
          color: Color(0xFF00FF00),
        ),
        cells: [
          CollageCellSettings(
            photoPath: presentPath,
            photoWidth: 50,
            photoHeight: 50,
          ),
          CollageCellSettings(
            photoPath: '${tempDir.path}/apagada.png',
            photoWidth: 50,
            photoHeight: 50,
          ),
        ],
      );

      const outputWidth = 200;
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: outputWidth,
      );

      // A foto que ainda existe sai normalmente...
      final leftPixel = await _decodePixel(bytes, outputWidth, 50, 50);
      expect(leftPixel[0], greaterThan(200));
      // ...e o lugar da que sumiu fica com o fundo, sem exceção nenhuma.
      final rightPixel = await _decodePixel(bytes, outputWidth, 150, 50);
      expect(rightPixel[1], greaterThan(200));
    },
  );

  test(
    'modo "ajustar" mostra o fundo da montagem na sobra, não um vazio',
    () async {
      // Foto quadrada numa célula bem mais larga que alta: em "contain" ela
      // fica menor que a célula nos dois eixos que sobram, e a sobra
      // (esquerda/direita) precisa mostrar o fundo da montagem.
      final photoPath = '${tempDir.path}/quadrada.png';
      await _writeSolidPng(photoPath, 100, 100, const Color(0xFFFF0000));

      final settings = CollageSettings(
        layout: CollageLayout.row(1),
        aspectRatio: 4.0,
        outerMarginRatio: 0,
        innerMarginRatio: 0,
        background: const CollageBackground(
          mode: CollageBackgroundMode.color,
          color: Color(0xFF00FF00),
        ),
        cells: [
          CollageCellSettings(
            photoPath: photoPath,
            photoWidth: 100,
            photoHeight: 100,
            fitMode: CollageCellFitMode.contain,
          ),
        ],
      );

      const outputWidth = 400;
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: outputWidth,
      );

      // Canvas 400x100: a foto quadrada em "ajustar" vira 100x100 centralizada
      // (x em [150,250]). Fora dela, nas laterais, é o fundo verde.
      final centerPixel = await _decodePixel(bytes, outputWidth, 200, 50);
      expect(centerPixel[0], greaterThan(200)); // foto vermelha no centro

      final sidePixel = await _decodePixel(bytes, outputWidth, 20, 50);
      expect(sidePixel[1], greaterThan(200)); // fundo verde na lateral
      expect(sidePixel[0], lessThan(50));
    },
  );

  test('borda própria da foto forma um anel ao redor dela', () async {
    final photoPath = '${tempDir.path}/foto.png';
    await _writeSolidPng(photoPath, 100, 100, const Color(0xFFFF0000));

    final settings = CollageSettings(
      layout: CollageLayout.row(1),
      aspectRatio: 1.0,
      outerMarginRatio: 0,
      innerMarginRatio: 0,
      background: const CollageBackground(
        mode: CollageBackgroundMode.color,
        color: Color(0xFF0000FF),
      ),
      cells: [
        CollageCellSettings(
          photoPath: photoPath,
          photoWidth: 100,
          photoHeight: 100,
          borderThicknessAtReference: 40,
          borderColor: const Color(0xFF00FF00),
        ),
      ],
    );

    const outputWidth = 480;
    final bytes = await composeCollage(
      settings: settings,
      outputWidth: outputWidth,
    );

    // Espessura efetiva na largura 480: 40 * (480/480) = 40px.
    final ringPixel = await _decodePixel(bytes, outputWidth, 10, 240);
    expect(ringPixel[1], greaterThan(200)); // anel verde
    expect(ringPixel[0], lessThan(50));

    final centerPixel = await _decodePixel(bytes, outputWidth, 240, 240);
    expect(centerPixel[0], greaterThan(200)); // foto vermelha no centro
  });

  test(
    'foto girada livremente (não só 90°) continua cobrindo a célula inteira',
    () async {
      final photoPath = '${tempDir.path}/foto.png';
      await _writeSolidPng(photoPath, 100, 100, const Color(0xFFFF0000));

      final settings = CollageSettings(
        layout: CollageLayout.row(1),
        aspectRatio: 1.0,
        outerMarginRatio: 0,
        innerMarginRatio: 0,
        background: const CollageBackground(
          mode: CollageBackgroundMode.color,
          color: Color(0xFF0000FF),
        ),
        cells: [
          CollageCellSettings(
            photoPath: photoPath,
            photoWidth: 100,
            photoHeight: 100,
            rotation: 30 * math.pi / 180,
          ),
        ],
      );

      const outputWidth = 200;
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: outputWidth,
      );

      // Amostra os 4 cantos e o centro da célula (canvas 200x200 sem borda):
      // nenhum ponto pode mostrar o fundo azul vazando por baixo da foto
      // girada — é exatamente o que `rotatedFootprint` existe para evitar.
      for (final point in [
        (4, 4),
        (196, 4),
        (4, 196),
        (196, 196),
        (100, 100),
      ]) {
        final pixel = await _decodePixel(
          bytes,
          outputWidth,
          point.$1,
          point.$2,
        );
        expect(
          pixel[0],
          greaterThan(200),
          reason: 'ponto ${point.$1},${point.$2} deveria ser a foto vermelha',
        );
      }
    },
  );

  test(
    'fundo próprio da foto preenche só a célula, não a montagem inteira',
    () async {
      // Duas células lado a lado numa montagem com margem: só a primeira tem
      // fundo próprio (azul). Em "ajustar", a sobra DENTRO dela sai azul, a
      // sobra da outra continua no fundo verde da montagem, e a margem entre
      // as duas também continua verde — o fundo da foto não vaza.
      final photoPath = '${tempDir.path}/quadrada.png';
      await _writeSolidPng(photoPath, 100, 100, const Color(0xFFFF0000));

      final photo = CollageCellSettings(
        photoPath: photoPath,
        photoWidth: 100,
        photoHeight: 100,
        fitMode: CollageCellFitMode.contain,
      );
      final settings = CollageSettings(
        layout: CollageLayout.row(2),
        aspectRatio: 4.0,
        outerMarginRatio: 0.05,
        innerMarginRatio: 0.05,
        background: const CollageBackground(
          mode: CollageBackgroundMode.color,
          color: Color(0xFF00FF00),
        ),
        cells: [
          photo.copyWith(
            background: const CollageBackground(
              mode: CollageBackgroundMode.color,
              color: Color(0xFF0000FF),
            ),
          ),
          photo,
        ],
      );

      const outputWidth = 400;
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: outputWidth,
      );

      // Canvas 400x100, margem de 5px (0.05 do menor lado): células em
      // x=[5,197] e x=[203,395]; cada foto quadrada "ajustada" ocupa ~90px no
      // centro da sua célula, então x=20 e x=380 são sobra.
      final leftGap = await _decodePixel(bytes, outputWidth, 20, 50);
      expect(leftGap[2], greaterThan(200)); // sobra azul: fundo da foto
      expect(leftGap[1], lessThan(60));

      final rightGap = await _decodePixel(bytes, outputWidth, 380, 50);
      expect(rightGap[1], greaterThan(200)); // sobra verde: fundo da montagem

      final marginPixel = await _decodePixel(bytes, outputWidth, 200, 50);
      expect(marginPixel[1], greaterThan(200)); // margem entre as células
      expect(marginPixel[2], lessThan(60));

      final photoPixel = await _decodePixel(bytes, outputWidth, 100, 50);
      expect(photoPixel[0], greaterThan(200)); // a foto continua por cima
    },
  );

  test('borda da foto é um anel: não pinta a sobra do "encaixar"', () async {
    // Foto quadrada numa célula bem mais larga, em "encaixar", com borda
    // própria grossa e fundo transparente na foto e na montagem: a sobra ao
    // lado da foto tem que sair TRANSPARENTE. Antes a borda era um retângulo
    // preenchendo a célula inteira por baixo da foto, então a sobra saía com
    // a cor da borda — não havia como ter borda e fundo transparente juntos.
    final photoPath = '${tempDir.path}/quadrada.png';
    await _writeSolidPng(photoPath, 100, 100, const Color(0xFFFF0000));

    final settings = CollageSettings(
      layout: CollageLayout.row(1),
      aspectRatio: 4.0,
      outerMarginRatio: 0,
      innerMarginRatio: 0,
      cells: [
        CollageCellSettings(
          photoPath: photoPath,
          photoWidth: 100,
          photoHeight: 100,
          fitMode: CollageCellFitMode.contain,
          borderThicknessAtReference: 20,
          borderColor: const Color(0xFF00FF00),
        ),
      ],
    );

    const outputWidth = 480;
    final bytes = await composeCollage(
      settings: settings,
      outputWidth: outputWidth,
    );

    // Canvas 480x120: anel de 20px, foto "ajustada" de 80x80 no centro.
    final ringPixel = await _decodePixel(bytes, outputWidth, 5, 60);
    expect(ringPixel[1], greaterThan(200)); // o anel continua verde
    expect(ringPixel[3], greaterThan(200));

    final gapPixel = await _decodePixel(bytes, outputWidth, 80, 60);
    expect(
      gapPixel[3],
      0,
      reason: 'a sobra dentro da borda tem que sair vazia',
    );

    final photoPixel = await _decodePixel(bytes, outputWidth, 240, 60);
    expect(photoPixel[0], greaterThan(200)); // a foto no centro
  });

  test('fundo próprio da foto fica atrás da borda própria dela', () async {
    // Fundo da foto (azul) dentro do anel da borda (verde): a borda continua
    // sendo a moldura externa e o fundo só preenche a área de conteúdo.
    final photoPath = '${tempDir.path}/quadrada.png';
    await _writeSolidPng(photoPath, 100, 100, const Color(0xFFFF0000));

    final settings = CollageSettings(
      layout: CollageLayout.row(1),
      aspectRatio: 4.0,
      outerMarginRatio: 0,
      innerMarginRatio: 0,
      cells: [
        CollageCellSettings(
          photoPath: photoPath,
          photoWidth: 100,
          photoHeight: 100,
          fitMode: CollageCellFitMode.contain,
          borderThicknessAtReference: 20,
          borderColor: const Color(0xFF00FF00),
          background: const CollageBackground(
            mode: CollageBackgroundMode.color,
            color: Color(0xFF0000FF),
          ),
        ),
      ],
    );

    const outputWidth = 480;
    final bytes = await composeCollage(
      settings: settings,
      outputWidth: outputWidth,
    );

    final borderPixel = await _decodePixel(bytes, outputWidth, 5, 60);
    expect(borderPixel[1], greaterThan(200)); // anel verde na borda

    final gapPixel = await _decodePixel(bytes, outputWidth, 60, 60);
    expect(gapPixel[2], greaterThan(200)); // fundo azul já dentro da borda
    expect(gapPixel[1], lessThan(60));
  });

  test('fundo do texto é desenhado atrás dele, na exportação', () async {
    // Texto branco com fundo azul sobre montagem transparente: o pixel
    // logo ao lado do texto (dentro do respiro da caixa) tem que estar azul
    // e opaco, e um ponto bem fora da caixa, vazio.
    final settings =
        CollageSettings(
          layout: CollageLayout.row(1),
          aspectRatio: 1.0,
          cells: const [CollageCellSettings()],
        ).addingText(
          const CollageTextItem(
            id: 't1',
            text: 'AA',
            color: Color(0xFFFFFFFF),
            backgroundColor: Color(0xFF0000FF),
            backgroundCornerRatio: 0,
            fontSizeRatio: 0.2,
            centerX: 0.5,
            centerY: 0.5,
            zIndex: 1,
          ),
        );

    const outputWidth = 300;
    final bytes = await composeCollage(
      settings: settings,
      outputWidth: outputWidth,
    );

    final besideText = await _decodePixel(bytes, outputWidth, 150, 118);
    expect(besideText[2], greaterThan(200), reason: 'a caixa azul do texto');
    expect(besideText[3], 255);

    final outside = await _decodePixel(bytes, outputWidth, 10, 10);
    expect(outside[3], 0, reason: 'fora da caixa segue transparente');
  });

  test('sem cor de fundo, o texto continua sem caixa nenhuma', () async {
    final settings =
        CollageSettings(
          layout: CollageLayout.row(1),
          aspectRatio: 1.0,
          cells: const [CollageCellSettings()],
        ).addingText(
          const CollageTextItem(
            id: 't1',
            text: 'AA',
            color: Color(0xFFFFFFFF),
            fontSizeRatio: 0.2,
            centerX: 0.5,
            centerY: 0.5,
            zIndex: 1,
          ),
        );

    const outputWidth = 300;
    final bytes = await composeCollage(
      settings: settings,
      outputWidth: outputWidth,
    );
    final besideText = await _decodePixel(bytes, outputWidth, 150, 118);
    expect(besideText[3], 0);
  });

  test(
    'texto com fonte embutida (fontFamily) é desenhado na exportação',
    () async {
      // Sem foto/aba de fundo nenhuma: só um texto branco grande sobre fundo
      // preto, com uma das fontes embutidas — protege a fiação de
      // `item.fontFamily` até o `TextStyle` de `_TextOverlay.paint` (se o
      // parâmetro se perdesse no caminho, o texto ainda apareceria, só que
      // sem essa cobertura não haveria como notar a regressão).
      final settings =
          CollageSettings(
            layout: CollageLayout.row(1),
            aspectRatio: 1.0,
            background: const CollageBackground(
              mode: CollageBackgroundMode.color,
              color: Color(0xFF000000),
            ),
            cells: const [CollageCellSettings()],
          ).addingText(
            const CollageTextItem(
              id: 't1',
              text: 'AAAA',
              color: Color(0xFFFFFFFF),
              fontSizeRatio: 0.4,
              centerX: 0.5,
              centerY: 0.5,
              zIndex: 1,
              fontFamily: 'Bebas Neue',
            ),
          );

      const outputWidth = 200;
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: outputWidth,
      );

      final centerPixel = await _decodePixel(bytes, outputWidth, 100, 100);
      expect(
        centerPixel[0],
        greaterThan(200),
        reason: 'o texto branco deveria cobrir o centro do canvas',
      );
    },
  );
}
