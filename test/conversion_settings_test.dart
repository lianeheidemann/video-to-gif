import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/frame_settings.dart';
import 'package:video_to_gif/models/image_frame.dart';
import 'package:video_to_gif/models/video_info.dart';

const _video = VideoInfo(
  path: '/tmp/exemplo.mp4',
  fileName: 'exemplo.mp4',
  rawWidth: 1080,
  rawHeight: 1920,
  durationSeconds: 5,
  frameRate: 30,
  bitrateBps: 6000000,
  fileSizeBytes: 3000000,
  codec: 'h264',
);

// Vídeo bem menor que a largura escolhida em "Resolução" — o caso em que a
// moldura procedural precisa ampliar o conteúdo para acompanhar a
// Resolução, em vez de ficar presa ao tamanho do recorte.
const _smallVideo = VideoInfo(
  path: '/tmp/pequeno.mp4',
  fileName: 'pequeno.mp4',
  rawWidth: 350,
  rawHeight: 320,
  durationSeconds: 5,
  frameRate: 30,
  bitrateBps: 1000000,
  fileSizeBytes: 500000,
  codec: 'h264',
);

void main() {
  test('720 px está disponível para preservar a resolução de vídeos HD', () {
    expect(ConversionSettings.widthOptions, contains(720));
  });

  group('formato de saída', () {
    test('o padrão continua sendo GIF, com a qualidade padrão do WebP', () {
      final settings = ConversionSettings(startSeconds: 0, endSeconds: 5);
      expect(settings.format, OutputFormat.gif);
      expect(settings.webpQuality, ConversionSettings.defaultWebpQuality);
    });

    test('recommendedFor também parte de GIF — WebP é escolha explícita', () {
      final settings = ConversionSettings.recommendedFor(_video);
      expect(settings.format, OutputFormat.gif);
    });

    test('recommendedFor mantém a largura original — 100%, não uma sugestão '
        'menor', () {
      // Antes escolhia a maior largura de até 720px; agora o padrão é o
      // tamanho do vídeo, e reduzir é uma escolha explícita no slider.
      final settings = ConversionSettings.recommendedFor(_video);
      expect(settings.targetWidth, _video.width);
    });
  });

  group('slider de resolução (porcentagem ↔ pixels)', () {
    test('100% devolve a largura e a altura originais', () {
      final (width, height) = ConversionSettings.dimensionsForPercent(
        _video,
        100,
      );
      expect(width, _video.width);
      expect(height, _video.height);
    });

    test('50% é a metade, arredondada para um número par', () {
      final (width, _) = ConversionSettings.dimensionsForPercent(_video, 50);
      expect(width, _video.width ~/ 2);
      expect(width.isEven, isTrue);
    });

    test('nunca deixa a largura cair a zero no piso do slider', () {
      const estreito = VideoInfo(
        path: '/tmp/estreito.mp4',
        fileName: 'estreito.mp4',
        rawWidth: 12,
        rawHeight: 40,
        durationSeconds: 5,
        frameRate: 30,
        bitrateBps: 500000,
        fileSizeBytes: 100000,
        codec: 'h264',
      );
      final (width, height) = ConversionSettings.dimensionsForPercent(
        estreito,
        ConversionSettings.minResolutionPercent,
      );
      expect(width, greaterThanOrEqualTo(2));
      expect(height, greaterThanOrEqualTo(2));
    });

    test('percentForWidth é o inverso de dimensionsForPercent', () {
      for (final percent in [10, 25, 50, 75, 100]) {
        final (width, _) = ConversionSettings.dimensionsForPercent(
          _video,
          percent,
        );
        expect(
          ConversionSettings.percentForWidth(_video, width),
          percent,
          reason: 'percent=$percent',
        );
      }
    });

    test('percentForWidth nunca sai do intervalo do slider', () {
      expect(ConversionSettings.percentForWidth(_video, _video.width * 2), 100);
      expect(
        ConversionSettings.percentForWidth(_video, 1),
        ConversionSettings.minResolutionPercent,
      );
    });
  });

  group('formato de saída (continuação)', () {
    test('copyWith(format: ...) só muda o formato', () {
      final base = ConversionSettings(startSeconds: 0, endSeconds: 5);
      final webp = base.copyWith(format: OutputFormat.webp);

      expect(webp.format, OutputFormat.webp);
      expect(webp.webpQuality, base.webpQuality);
      expect(webp.fps, base.fps);
      expect(webp.colors, base.colors);
    });

    test('copyWith(webpQuality: ...) só muda a qualidade do WebP', () {
      final base = ConversionSettings(startSeconds: 0, endSeconds: 5);
      final higherQuality = base.copyWith(webpQuality: 95);

      expect(higherQuality.webpQuality, 95);
      expect(higherQuality.format, base.format);
    });

    test('cada formato carrega a extensão e o mimeType corretos', () {
      expect(OutputFormat.gif.extension, 'gif');
      expect(OutputFormat.gif.mimeType, 'image/gif');
      expect(OutputFormat.webp.extension, 'webp');
      expect(OutputFormat.webp.mimeType, 'image/webp');
    });
  });

  group('moldura procedural: canvas segue a Resolução em vídeos pequenos', () {
    const framedSettings = FrameSettings(
      style: FrameStyle.medium,
      thicknessAtReference: 10,
      cornerRatio: 0.12,
    );

    test('vídeo menor que a Resolução sobe até targetWidth com moldura', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 1920,
        frame: framedSettings,
      );

      final (w, _) = settings.contentDimensions(_smallVideo);
      expect(w, 1920);
    });

    test('o canvas nunca ultrapassa a largura escolhida em "Resolução"', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 400,
        frame: framedSettings,
      );

      final (w, _) = settings.contentDimensions(_smallVideo);
      expect(w, 400);
    });

    test('sem moldura, vídeo pequeno continua sem nenhum upscaling', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 720,
      );

      final (w, _) = settings.contentDimensions(_smallVideo);
      expect(w, 350);
    });

    test('moldura de imagem não recebe upscale — contorno já é vetorial', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 720,
        frame: FrameSettings(imageFrame: ImageFrameLibrary.bundled.first),
      );

      final (w, _) = settings.contentDimensions(_smallVideo);
      expect(w, 350);
    });
  });

  group('moldura: espessura e canvas', () {
    test(
      'o deslocamento do pad nunca ultrapassa o canvas, em qualquer largura',
      () {
        // Regressão: com moldura + fundo transparente, o FFmpeg monta o
        // quadro posicionando o vídeo no offset `thicknessPx:thicknessPx`.
        // Se o offset mais a área de conteúdo passar do canvas, o overlay
        // do FFmpeg deixa a borda assimétrica. Isso
        // acontecia quando a espessura era arredondada de formas
        // diferentes em [ConversionSettings.frameAreaDimensions] (para o
        // canvas) e em `FfmpegService._framedGraph` (para o offset do
        // pad) — ver histórico desta constante.
        for (final style in [
          FrameStyle.thin,
          FrameStyle.medium,
          FrameStyle.thick,
        ]) {
          // Do canto reto ao completamente arredondado, incluindo os
          // extremos do slider.
          for (final cornerRatio in const [
            0.0,
            0.12,
            0.25,
            FrameSettings.maxCornerRatio,
          ]) {
            for (var w = 2; w <= 2000; w += 2) {
              final settings = ConversionSettings(
                startSeconds: 0,
                endSeconds: 5,
                targetWidth: w,
                frame: FrameSettings(
                  style: style,
                  thicknessAtReference: style.defaultThickness,
                  cornerRatio: cornerRatio,
                  transparentBackground: true,
                ),
              );

              final (areaWidth, areaHeight, thickness) = settings
                  .frameAreaDimensions(_video);
              final (canvasWidth, canvasHeight) = settings.outputDimensions(
                _video,
              );
              final thicknessPx = thickness.round();

              expect(
                thicknessPx + areaWidth,
                lessThanOrEqualTo(canvasWidth),
                reason: 'largura: style=$style canto=$cornerRatio w=$w',
              );
              expect(
                thicknessPx + areaHeight,
                lessThanOrEqualTo(canvasHeight),
                reason: 'altura: style=$style canto=$cornerRatio w=$w',
              );

              // A borda deve sair sempre simétrica (mesma espessura dos
              // dois lados), não só "não estourar".
              expect(
                canvasWidth - thicknessPx - areaWidth,
                thicknessPx,
                reason: 'assimetria horizontal: style=$style w=$w',
              );
              expect(
                canvasHeight - thicknessPx - areaHeight,
                thicknessPx,
                reason: 'assimetria vertical: style=$style w=$w',
              );
            }
          }
        }
      },
    );

    test('moldura procedural preserva o formato e o tamanho escolhidos', () {
      final formats = <CropRect?>[
        null,
        CropRect.centeredIn(_video.width, _video.height, 1),
        CropRect.centeredIn(_video.width, _video.height, 4 / 5),
        CropRect.centeredIn(_video.width, _video.height, 16 / 9),
      ];

      for (final crop in formats) {
        for (final style in FrameStyle.values.where(
          (style) => style != FrameStyle.none,
        )) {
          final settings = ConversionSettings(
            startSeconds: 0,
            endSeconds: 5,
            targetWidth: 480,
            crop: crop,
            frame: FrameSettings(
              style: style,
              thicknessAtReference: style.defaultThickness,
            ),
          );

          expect(
            settings.outputDimensions(_video),
            settings.contentDimensions(_video),
            reason: 'style=$style crop=$crop',
          );
        }
      }
    });

    test('moldura procedural 9:16 é exportada exatamente em 720×1280', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 720,
        crop: CropRect.centeredIn(_video.width, _video.height, 9 / 16),
        frame: const FrameSettings(
          style: FrameStyle.medium,
          thicknessAtReference: 10,
          cornerRatio: 0.12,
          transparentBackground: true,
        ),
      );

      expect(settings.contentDimensions(_video), (720, 1280));
      expect(settings.outputDimensions(_video), (720, 1280));
    });
  });

  group('moldura de imagem: resolução e zoom', () {
    final art = ImageFrameLibrary.bundled.first;

    test(
      'valores padrão de FrameSettings não têm zoom nem resolução nativa',
      () {
        const frame = FrameSettings();
        expect(frame.contentZoom, FrameSettings.defaultContentZoom);
        expect(
          frame.frameResolutionMode,
          ImageFrameResolutionMode.matchAjustar,
        );
      },
    );

    test('contentZoom só é efetivo em Expandir sem cortar', () {
      for (final mode in [
        ContentFitMode.auto,
        ContentFitMode.fill,
        ContentFitMode.fit,
      ]) {
        final frame = FrameSettings(
          imageFrame: art,
          contentFit: mode,
          contentZoom: FrameSettings.maxContentZoom,
        );
        expect(
          frame.effectiveContentZoom,
          FrameSettings.defaultContentZoom,
          reason: 'mode=$mode',
        );
      }

      final reduced = FrameSettings(
        imageFrame: art,
        contentFit: ContentFitMode.expand,
        contentZoom: FrameSettings.minContentZoom,
      );
      final enlarged = FrameSettings(
        imageFrame: art,
        contentFit: ContentFitMode.expand,
        contentZoom: FrameSettings.maxContentZoom,
      );
      expect(reduced.effectiveContentZoom, 0.1);
      expect(enlarged.effectiveContentZoom, 3.0);
    });

    test('imageFrameCanvasDimensions usa a largura de Ajustar por padrão', () {
      for (final targetWidth in [160, 320, 480, 800]) {
        final settings = ConversionSettings(
          startSeconds: 0,
          endSeconds: 5,
          targetWidth: targetWidth,
          frame: FrameSettings(imageFrame: art),
        );

        final (contentWidth, _) = settings.contentDimensions(_video);
        final expectedWidth = contentWidth / art.contentRect.width;
        final (canvasWidth, _) = settings.imageFrameCanvasDimensions(_video);

        expect(
          canvasWidth,
          closeTo(expectedWidth, 2),
          reason: 'targetWidth=$targetWidth',
        );
      }
    });

    test(
      'imageFrameCanvasDimensions usa a resolução nativa da arte quando pedido',
      () {
        final canvases = <int>{};
        for (final targetWidth in [160, 320, 480, 800]) {
          final settings = ConversionSettings(
            startSeconds: 0,
            endSeconds: 5,
            targetWidth: targetWidth,
            frame: FrameSettings(
              imageFrame: art,
              frameResolutionMode: ImageFrameResolutionMode.nativeMax,
            ),
          );

          final (canvasWidth, _) = settings.imageFrameCanvasDimensions(_video);
          canvases.add(canvasWidth);
        }

        expect(
          canvases.length,
          1,
          reason: 'o canvas no modo nativeMax não deve variar com targetWidth',
        );
      },
    );

    test('resolução nativa é limitada por maxImageFrameNativeWidth', () {
      final hugeArt = ImageFrameAsset(
        id: 'teste_gigante',
        label: 'Foto gigante',
        source: ImageFrameSource.importedImage,
        imageFilePath: '/tmp/foto-gigante-inexistente.png',
        nativeAspectRatio: art.nativeAspectRatio,
        nativeReferenceWidth: 6000,
        contentRect: art.contentRect,
      );
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: FrameSettings(
          imageFrame: hugeArt,
          frameResolutionMode: ImageFrameResolutionMode.nativeMax,
        ),
      );

      final (canvasWidth, _) = settings.imageFrameCanvasDimensions(_video);
      expect(
        canvasWidth,
        lessThanOrEqualTo(ConversionSettings.maxImageFrameNativeWidth),
      );
    });

    test('contentZoom não altera a geometria compartilhada com o FFmpeg', () {
      final base = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: FrameSettings(imageFrame: art),
      );
      final zoomed = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: FrameSettings(
          imageFrame: art,
          contentZoom: FrameSettings.maxContentZoom,
        ),
      );

      expect(
        zoomed.imageFrameCanvasDimensions(_video),
        base.imageFrameCanvasDimensions(_video),
      );
      expect(
        zoomed.imageFrameContentAreaPx(_video),
        base.imageFrameContentAreaPx(_video),
      );
    });
  });

  group('aba "Girar": rotação do conteúdo', () {
    test('valores padrão: sem rotação nem espelhamento', () {
      final settings = ConversionSettings(startSeconds: 0, endSeconds: 5);
      expect(settings.rotationQuarterTurns, 0);
      expect(settings.flipHorizontal, isFalse);
      expect(settings.flipVertical, isFalse);
    });

    test('copyWith muda cada campo independentemente', () {
      final base = ConversionSettings(startSeconds: 0, endSeconds: 5);
      final rotated = base.copyWith(rotationQuarterTurns: 1);
      expect(rotated.rotationQuarterTurns, 1);
      expect(rotated.flipHorizontal, isFalse);

      final flipped = base.copyWith(flipHorizontal: true, flipVertical: true);
      expect(flipped.flipHorizontal, isTrue);
      expect(flipped.flipVertical, isTrue);
      expect(flipped.rotationQuarterTurns, 0);
    });

    test('contentDimensions troca largura/altura só em giros ímpares', () {
      // targetWidth bem acima de largura e altura do vídeo, para nenhum
      // giro esbarrar no teto de "Resolução" e disfarçar a troca.
      final base = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 4000,
      );
      final (baseW, baseH) = base.contentDimensions(_video);

      for (final turns in [0, 1, 2, 3]) {
        final rotated = base.copyWith(rotationQuarterTurns: turns);
        final (w, h) = rotated.contentDimensions(_video);
        if (turns.isOdd) {
          expect(w, baseH, reason: 'turns=$turns largura');
          expect(h, baseW, reason: 'turns=$turns altura');
        } else {
          expect(w, baseW, reason: 'turns=$turns largura');
          expect(h, baseH, reason: 'turns=$turns altura');
        }
      }
    });

    test('outputDimensions/frameAreaDimensions herdam a troca (via '
        'contentDimensions)', () {
      // Sem moldura procedural de propósito: seu upscale até targetWidth
      // (ver "moldura procedural: canvas segue a Resolução em vídeos
      // pequenos" acima) já não depende da orientação, então misturar os
      // dois comportamentos aqui só disfarçaria a troca sob teste. O que
      // importa é que outputDimensions/frameAreaDimensions DERIVAM de
      // contentDimensions (já coberto para giros ímpares), não que a
      // moldura procedural também rode nesta conta.
      final base = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 4000,
      );
      final rotated = base.copyWith(rotationQuarterTurns: 1);

      final (baseW, baseH) = base.outputDimensions(_video);
      final (rotW, rotH) = rotated.outputDimensions(_video);
      expect(rotW, baseH);
      expect(rotH, baseW);
      expect(
        rotated.outputDimensions(_video),
        rotated.contentDimensions(_video),
      );

      final (baseAreaW, baseAreaH, _) = base.frameAreaDimensions(_video);
      final (rotAreaW, rotAreaH, _) = rotated.frameAreaDimensions(_video);
      expect(rotAreaW, baseAreaH);
      expect(rotAreaH, baseAreaW);
    });

    test('imageFrameCanvasDimensions: a arte nunca é distorcida pela rotação '
        'do conteúdo', () {
      final art = ImageFrameLibrary.bundled.first;
      final base = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 4000,
        frame: FrameSettings(imageFrame: art),
      );
      final rotated = base.copyWith(rotationQuarterTurns: 1);

      for (final settings in [base, rotated]) {
        final (canvasWidth, canvasHeight) = settings.imageFrameCanvasDimensions(
          _video,
        );
        expect(
          canvasWidth / canvasHeight,
          closeTo(art.nativeAspectRatio, 0.01),
          reason: 'rotationQuarterTurns=${settings.rotationQuarterTurns}',
        );
      }

      // A largura do CANVAS (não a proporção da arte) muda: o conteúdo
      // girado é mais estreito, então a arte encolhe para caber nele.
      final (baseCanvasW, _) = base.imageFrameCanvasDimensions(_video);
      final (rotCanvasW, _) = rotated.imageFrameCanvasDimensions(_video);
      expect(rotCanvasW, isNot(baseCanvasW));
    });
  });

  group('aba "Moldura": girar resultado inteiro', () {
    test('FrameSettings: valor padrão é zero', () {
      const frame = FrameSettings();
      expect(frame.groupRotationQuarterTurns, 0);
    });

    test('FrameSettings.copyWith muda só o campo pedido', () {
      const base = FrameSettings(style: FrameStyle.thin);
      final rotated = base.copyWith(groupRotationQuarterTurns: 2);
      expect(rotated.groupRotationQuarterTurns, 2);
      expect(rotated.style, FrameStyle.thin);
    });

    test('finalOutputDimensions troca largura/altura só em giros ímpares', () {
      final base = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: _video.width,
      );
      final (baseW, baseH) = base.outputDimensions(_video);

      for (final turns in [0, 1, 2, 3]) {
        final settings = base.copyWith(
          frame: base.frame.copyWith(groupRotationQuarterTurns: turns),
        );
        final (w, h) = settings.finalOutputDimensions(_video);
        if (turns.isOdd) {
          expect(w, baseH, reason: 'turns=$turns largura');
          expect(h, baseW, reason: 'turns=$turns altura');
        } else {
          expect(w, baseW, reason: 'turns=$turns largura');
          expect(h, baseH, reason: 'turns=$turns altura');
        }
      }
    });

    test('outputDimensions (o canvas que a exportação realmente monta) nunca '
        'muda com a rotação do resultado', () {
      final base = ConversionSettings(startSeconds: 0, endSeconds: 5);
      final rotated = base.copyWith(
        frame: base.frame.copyWith(groupRotationQuarterTurns: 1),
      );
      expect(rotated.outputDimensions(_video), base.outputDimensions(_video));
    });

    test('rotação de conteúdo e rotação do resultado são independentes e '
        'compõem sem se cancelar', () {
      final base = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 4000,
      );
      final (baseW, baseH) = base.outputDimensions(_video);

      // Só conteúdo girado (ímpar): outputDimensions já reflete a troca,
      // finalOutputDimensions é igual (groupRotation par).
      final onlyContent = base.copyWith(rotationQuarterTurns: 1);
      expect(onlyContent.finalOutputDimensions(_video), (baseH, baseW));

      // Só o resultado girado (ímpar): outputDimensions continua igual ao
      // caso base, finalOutputDimensions troca por cima dele.
      final onlyGroup = base.copyWith(
        frame: base.frame.copyWith(groupRotationQuarterTurns: 1),
      );
      expect(onlyGroup.outputDimensions(_video), (baseW, baseH));
      expect(onlyGroup.finalOutputDimensions(_video), (baseH, baseW));

      // As duas ímpares ao mesmo tempo: as trocas se aplicam em
      // sequência (conteúdo primeiro, resultado depois) e voltam à
      // orientação original — não se confundem numa só troca.
      final both = base.copyWith(
        rotationQuarterTurns: 1,
        frame: base.frame.copyWith(groupRotationQuarterTurns: 1),
      );
      expect(both.finalOutputDimensions(_video), (baseW, baseH));
    });
  });
}
