import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/ffmpeg/ffmpeg_service.dart';
import 'package:video_to_gif/core/ffmpeg/filter_graph.dart';
import 'package:video_to_gif/core/ffmpeg/gif_args.dart';
import 'package:video_to_gif/core/models/conversion_settings.dart';
import 'package:video_to_gif/core/models/frame_settings.dart';
import 'package:video_to_gif/core/models/image_frame.dart';
import 'package:video_to_gif/core/models/output_transform.dart';
import 'package:video_to_gif/core/models/video_info.dart';

// A aba "Girar" do vídeo e da foto é um passo de saída: ela gira o
// resultado já composto, sem mexer em recorte, moldura ou estimativa. Dois
// pontos são fáceis de quebrar sem perceber, e é neles que este arquivo
// insiste:
//
//  * sem giro nenhum (o caso de longe mais comum) a linha de comando tem
//    que sair exatamente como saía antes, senão qualquer regressão some no
//    meio de um grafo novo;
//  * com giro, o `transpose` tem que vir DEPOIS do `alphamerge` que aplica
//    a máscara de cantos arredondados. A máscara é um PNG do tamanho do
//    canvas: girar antes dela deixaria os dois fora de esquadro.

const _video = VideoInfo(
  path: '/tmp/exemplo.mp4',
  fileName: 'exemplo.mp4',
  rawWidth: 640,
  rawHeight: 360,
  durationSeconds: 5,
  frameRate: 30,
  bitrateBps: 3000000,
  fileSizeBytes: 2000000,
  codec: 'h264',
);

ConversionSettings _settings({
  OutputTransform transform = OutputTransform.identity,
  FrameStyle style = FrameStyle.none,
  bool transparent = true,
  bool imageFrame = false,
  OutputFormat format = OutputFormat.gif,
}) => ConversionSettings(
  startSeconds: 0,
  endSeconds: 5,
  format: format,
  frame: FrameSettings(
    style: style,
    thicknessAtReference: style == FrameStyle.none ? 0 : 10,
    cornerRatio: style == FrameStyle.none ? 0 : 0.12,
    transparentBackground: transparent,
    imageFrame: imageFrame ? ImageFrameLibrary.bundled.first : null,
    outputTransform: transform,
  ),
);

String _lavfiOf(List<String> args) => args[args.indexOf('-lavfi') + 1];

/// O grafo tem mais de um `alphamerge` (a máscara do canto interno do vídeo
/// vem bem antes da máscara do canvas), então comparar com o primeiro deles
/// deixaria passar um giro colado cedo demais. O que importa é o último.
void _expectRotatesAfterEveryMask(String lavfi) {
  expect(
    'transpose'.allMatches(lavfi).length,
    1,
    reason: 'o giro tem que acontecer num lugar só',
  );
  expect(
    lavfi.indexOf('transpose'),
    greaterThan(lavfi.lastIndexOf('alphamerge')),
    reason: 'girar antes da máscara deixaria os dois fora de esquadro',
  );
}

void main() {
  const quarterTurn = OutputTransform(quarterTurns: 1);
  final ffmpeg = FfmpegService();

  group('OutputTransform', () {
    test('girar para a esquerda a partir do zero dá três quartos', () {
      expect(OutputTransform.identity.rotatedBy(-1).quarterTurns, 3);
    });

    test('girar para a direita a partir de três volta para zero', () {
      expect(
        const OutputTransform(quarterTurns: 3).rotatedBy(1).quarterTurns,
        0,
      );
    });

    test('quatro giros para a esquerda voltam ao começo', () {
      var transform = OutputTransform.identity;
      for (var i = 0; i < 4; i++) {
        transform = transform.rotatedBy(-1);
      }
      expect(transform, OutputTransform.identity);
      expect(transform.isIdentity, isTrue);
    });

    test('só 90° e 270° trocam os lados', () {
      expect(OutputTransform.identity.swapsAxes, isFalse);
      expect(const OutputTransform(quarterTurns: 1).swapsAxes, isTrue);
      expect(const OutputTransform(quarterTurns: 2).swapsAxes, isFalse);
      expect(const OutputTransform(quarterTurns: 3).swapsAxes, isTrue);
    });

    test('espelhar não desfaz o giro guardado', () {
      final transform = quarterTurn.copyWith(flipHorizontal: true);
      expect(transform.quarterTurns, 1);
      expect(transform.flipHorizontal, isTrue);
      expect(transform.isIdentity, isFalse);
    });

    test('o rótulo resume os três campos', () {
      expect(OutputTransform.identity.label, 'Original');
      expect(const OutputTransform(quarterTurns: 2).label, '180°');
      expect(
        const OutputTransform(
          quarterTurns: 1,
          flipHorizontal: true,
          flipVertical: true,
        ).label,
        '90° · Espelho H · Espelho V',
      );
    });

    test('o canvas só troca de lados nos giros de um quarto', () {
      expect(transformedCanvasSize(OutputTransform.identity, 400, 200), (
        400,
        200,
      ));
      expect(transformedCanvasSize(quarterTurn, 400, 200), (200, 400));
      expect(
        transformedCanvasSize(const OutputTransform(quarterTurns: 2), 400, 200),
        (400, 200),
      );
    });
  });

  group('filtros do FFmpeg', () {
    test('sem transformação não gera filtro nenhum', () {
      expect(outputTransformFilters(OutputTransform.identity), isEmpty);
    });

    test('um quarto de volta à direita é transpose=1', () {
      expect(outputTransformFilters(quarterTurn), ['transpose=1']);
    });

    test('um quarto à esquerda é transpose=2, não transpose=1 repetido', () {
      expect(outputTransformFilters(OutputTransform.identity.rotatedBy(-1)), [
        'transpose=2',
      ]);
    });

    test('meia volta são dois quartos no mesmo sentido', () {
      expect(outputTransformFilters(const OutputTransform(quarterTurns: 2)), [
        'transpose=1,transpose=1',
      ]);
    });

    test('espelhar vem depois de girar, como na prévia', () {
      expect(
        outputTransformFilters(
          const OutputTransform(
            quarterTurns: 1,
            flipHorizontal: true,
            flipVertical: true,
          ),
        ),
        ['transpose=1', 'hflip', 'vflip'],
      );
    });

    test('só espelhar não gira nada', () {
      expect(
        outputTransformFilters(const OutputTransform(flipVertical: true)),
        ['vflip'],
      );
    });
  });

  group('sem giro, a linha de comando não muda', () {
    // Cada caminho de exportação recebeu um estágio novo; estes casos
    // travam o fato de que ele desaparece por completo quando a aba está em
    // "Original", em vez de deixar um `copy` ou um rótulo extra para trás.
    test('GIF sem moldura', () {
      final lavfi = _lavfiOf(
        paletteUseArgs(
          video: _video,
          settings: _settings(),
          palettePath: '/tmp/p.png',
          outputPath: '/tmp/s.gif',
        ),
      );
      expect(lavfi, isNot(contains('transpose')));
      expect(lavfi, isNot(contains('_girado')));
      expect(lavfi, startsWith('[0:v]'));
      expect(lavfi, contains('[v];[v][1:v]paletteuse='));
    });

    test('GIF com moldura transparente', () {
      final lavfi = _lavfiOf(
        transparentGifArgs(
          video: _video,
          settings: _settings(style: FrameStyle.medium),
          maskPath: '/tmp/m.png',
          outputPath: '/tmp/s.gif',
        ),
      );
      expect(lavfi, isNot(contains('_girado')));
      expect(lavfi, contains('[alpha]split=2'));
    });

    test('WebP sem moldura termina no rótulo que o -map espera', () {
      final args = ffmpeg.webpArgs(
        video: _video,
        settings: _settings(format: OutputFormat.webp),
        outputPath: '/tmp/s.webp',
      );
      expect(_lavfiOf(args), isNot(contains('_bruto')));
      expect(args[args.indexOf('-map') + 1], '[out]');
    });
  });

  group('com giro, o transpose entra por último', () {
    test('GIF sem moldura gira entre a cadeia e o paletteuse', () {
      final lavfi = _lavfiOf(
        paletteUseArgs(
          video: _video,
          settings: _settings(transform: quarterTurn),
          palettePath: '/tmp/p.png',
          outputPath: '/tmp/s.gif',
        ),
      );
      expect(lavfi, contains('[v];[v]transpose=1[v_girado];'));
      expect(lavfi, contains('[v_girado][1:v]paletteuse='));
      // O `scale` é a cadeia de conteúdo: o giro nunca pode vir antes dele.
      expect(
        lavfi.indexOf('transpose=1'),
        greaterThan(lavfi.indexOf('scale=')),
      );
    });

    test('a paleta não é girada — girar não muda cor nenhuma', () {
      final lavfi = paletteGenArgs(
        video: _video,
        settings: _settings(transform: quarterTurn),
        palettePath: '/tmp/p.png',
      ).join(' ');
      expect(lavfi, isNot(contains('transpose')));
    });

    test('GIF com moldura transparente gira depois da máscara', () {
      final lavfi = _lavfiOf(
        transparentGifArgs(
          video: _video,
          settings: _settings(transform: quarterTurn, style: FrameStyle.medium),
          maskPath: '/tmp/m.png',
          outputPath: '/tmp/s.gif',
        ),
      );
      _expectRotatesAfterEveryMask(lavfi);
      expect(lavfi, contains('[alpha_girado]split=2'));
    });

    test('GIF com moldura e paleta pronta gira depois da máscara', () {
      final lavfi = _lavfiOf(
        paletteUseArgs(
          video: _video,
          settings: _settings(transform: quarterTurn, style: FrameStyle.medium),
          palettePath: '/tmp/p.png',
          outputPath: '/tmp/s.gif',
          maskPath: '/tmp/m.png',
        ),
      );
      _expectRotatesAfterEveryMask(lavfi);
      expect(lavfi, contains('[alpha_girado][1:v]paletteuse='));
    });

    test('WebP mantém o rótulo [out] que o -map exige', () {
      final args = ffmpeg.webpArgs(
        video: _video,
        settings: _settings(transform: quarterTurn, format: OutputFormat.webp),
        outputPath: '/tmp/s.webp',
      );
      final lavfi = _lavfiOf(args);
      expect(lavfi, endsWith('[out_bruto]transpose=1[out]'));
      expect(args[args.indexOf('-map') + 1], '[out]');
    });

    test('WebP com moldura transparente gira depois da máscara', () {
      final args = ffmpeg.webpArgs(
        video: _video,
        settings: _settings(
          transform: quarterTurn,
          style: FrameStyle.medium,
          format: OutputFormat.webp,
        ),
        outputPath: '/tmp/s.webp',
        maskPath: '/tmp/m.png',
      );
      final lavfi = _lavfiOf(args);
      _expectRotatesAfterEveryMask(lavfi);
      expect(lavfi, endsWith('[out_bruto]transpose=1[out]'));
      expect(args[args.indexOf('-map') + 1], '[out]');
    });

    test('WebP com moldura de imagem gira no fim do grafo', () {
      final args = ffmpeg.webpImageFramedArgs(
        video: _video,
        settings: _settings(
          transform: quarterTurn,
          imageFrame: true,
          format: OutputFormat.webp,
        ),
        artPath: '/tmp/arte.png',
        outputPath: '/tmp/s.webp',
      );
      expect(_lavfiOf(args), endsWith('[out_bruto]transpose=1[out]'));
      expect(args[args.indexOf('-map') + 1], '[out]');
    });

    test('GIF com moldura de imagem gira antes do split da paleta', () {
      final lavfi = _lavfiOf(
        ffmpeg.imageFramedGifArgs(
          video: _video,
          settings: _settings(transform: quarterTurn, imageFrame: true),
          artPath: '/tmp/arte.png',
          outputPath: '/tmp/s.gif',
        ),
      );
      _expectRotatesAfterEveryMask(lavfi);
      expect(lavfi, contains('[framed]transpose=1[framed_girado];'));
      expect(lavfi, contains('[framed_girado]split=2'));
    });
  });

  group('transformação do canvas', () {
    // O compositor da foto desenha na orientação original e deixa o canvas
    // girado dar conta do resto. Um erro de sinal aí só aparece como uma
    // imagem em branco ou de cabeça para baixo, então vale conferir onde um
    // ponto conhecido vai parar.
    Future<ui.Image> paint(OutputTransform transform) async {
      const size = Size(40, 20);
      final (width, height) = transformedCanvasSize(transform, 40, 20);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      applyCanvasOutputTransform(canvas, transform, size);
      // Fundo branco inteiro, e um quadrado preto no canto superior
      // esquerdo do desenho original.
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 8, 8),
        Paint()..color = const Color(0xFF000000),
      );
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
    }

    Future<bool> isBlackAt(ui.Image image, int x, int y) async {
      final data = await image.toByteData();
      final offset = (y * image.width + x) * 4;
      return data!.getUint8(offset) < 64;
    }

    test('sem transformação o quadrado fica onde foi desenhado', () async {
      final image = await paint(OutputTransform.identity);
      expect(image.width, 40);
      expect(image.height, 20);
      expect(await isBlackAt(image, 2, 2), isTrue);
      expect(await isBlackAt(image, 37, 2), isFalse);
      image.dispose();
    });

    test('90° à direita leva o canto para o alto à direita', () async {
      final image = await paint(quarterTurn);
      expect(image.width, 20);
      expect(image.height, 40);
      expect(await isBlackAt(image, 17, 2), isTrue);
      expect(await isBlackAt(image, 2, 2), isFalse);
      image.dispose();
    });

    test('90° à esquerda leva o canto para baixo à esquerda', () async {
      final image = await paint(OutputTransform.identity.rotatedBy(-1));
      expect(image.width, 20);
      expect(image.height, 40);
      expect(await isBlackAt(image, 2, 37), isTrue);
      expect(await isBlackAt(image, 17, 2), isFalse);
      image.dispose();
    });

    test('espelhar na horizontal joga o canto para a direita', () async {
      final image = await paint(const OutputTransform(flipHorizontal: true));
      expect(image.width, 40);
      expect(image.height, 20);
      expect(await isBlackAt(image, 37, 2), isTrue);
      expect(await isBlackAt(image, 2, 2), isFalse);
      image.dispose();
    });

    test('espelhar age sobre o resultado já girado', () async {
      // 90° à direita leva o canto para o alto à direita; o espelho
      // horizontal o traz de volta para o alto à esquerda. Se o espelho
      // fosse aplicado antes do giro, ele desceria em vez disso.
      final image = await paint(
        const OutputTransform(quarterTurns: 1, flipHorizontal: true),
      );
      expect(await isBlackAt(image, 2, 2), isTrue);
      expect(await isBlackAt(image, 17, 2), isFalse);
      image.dispose();
    });
  });
}
