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

void main() {
  test(
    '720 px está disponível para preservar a resolução de vídeos HD',
    () {
      expect(ConversionSettings.widthOptions, contains(720));
    },
  );

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
        CropRect.centered(_video, 1),
        CropRect.centered(_video, 4 / 5),
        CropRect.centered(_video, 16 / 9),
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
        crop: CropRect.centered(_video, 9 / 16),
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
}
