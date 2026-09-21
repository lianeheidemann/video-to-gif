import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_video/statistics.dart';
import 'package:ffmpeg_kit_flutter_new_video/stream_information.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../models/color_adjustments.dart';
import '../models/conversion_settings.dart';
import '../models/frame_settings.dart';
import '../models/image_frame.dart';
import '../models/quick_convert_format.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import 'ffmpeg_primitives.dart';
import 'filter_graph.dart';
import 'gif_args.dart';
import 'mp4_rotation.dart';
import 'probe_parsing.dart';
import 'webp_args.dart';
import '../painting/frame_painter.dart';
import '../services/size_estimator.dart';
import '../services/text_overlay_render.dart';

/// Resultado de uma conversão bem-sucedida: o arquivo GIF e seus metadados.
class ConversionResult {
  const ConversionResult({
    required this.file,
    required this.bytes,
    required this.width,
    required this.height,
    required this.frames,
    required this.elapsed,
    required this.format,
  });

  final File file;
  final int bytes;
  final int width;
  final int height;
  final int frames;
  final Duration elapsed;
  final OutputFormat format;

  String get formattedSize => SizeEstimate.formatBytes(bytes);
}

/// Erro de uma operação do FFmpeg/FFprobe, com mensagem amigável em
/// português e, opcionalmente, os logs brutos para depuração.
class FfmpegException implements Exception {
  FfmpegException(this.message, {this.logs = ''});

  final String message;
  final String logs;

  @override
  String toString() => 'FfmpegException: $message';
}

/// Envolve o FFmpeg: leitura de metadados, medição de amostra e conversão.
///
/// Toda a montagem de linha de comando vive aqui, para que a calibração e a
/// conversão final usem *exatamente* a mesma cadeia de filtros — é isso que
/// faz a estimativa medida bater com o resultado.
class FfmpegService {
  FfmpegService() {
    // Sem isso a saída do FFmpeg vai para o log do sistema e polui o Logcat.
    FFmpegKitConfig.enableLogCallback((_) {});
  }

  int? _activeSessionId;
  bool _cancelled = false;

  // ------------------------------------------------------------------
  // Metadados
  // ------------------------------------------------------------------

  /// Lê os metadados do vídeo em [path] (dimensões, duração, fps, bitrate,
  /// codec e rotação) usando o FFprobe. Lança [FfmpegException] se o
  /// arquivo não existir, não puder ser lido ou não tiver faixa de vídeo.
  Future<VideoInfo> probe(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FfmpegException('Arquivo não encontrado: $path');
    }

    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    if (info == null) {
      throw FfmpegException(
        'Não foi possível ler este arquivo. Ele pode estar corrompido ou em '
        'um formato não suportado.',
        logs: await session.getAllLogsAsString() ?? '',
      );
    }

    final streams = info.getStreams();
    final video = streams.cast<StreamInformation?>().firstWhere(
      (s) => s?.getType() == 'video',
      orElse: () => null,
    );
    if (video == null) {
      throw FfmpegException('Este arquivo não tem faixa de vídeo.');
    }

    final width = video.getWidth() ?? 0;
    final height = video.getHeight() ?? 0;
    if (width <= 0 || height <= 0) {
      throw FfmpegException('Não foi possível descobrir o tamanho do vídeo.');
    }

    final duration =
        double.tryParse(info.getDuration() ?? '') ?? durationFrom(video) ?? 0;
    if (duration <= 0) {
      throw FfmpegException('Não foi possível descobrir a duração do vídeo.');
    }

    // Desempate, não substituto: quando o FFprobe informa uma rotação, ela
    // vale. O leitor do container só entra quando o FFprobe não informou
    // nada — existe vídeo de celular cuja rotação está só na matriz de
    // exibição do MP4, e tratá-lo como sem rotação deixa um vídeo gravado
    // em pé achatado na prévia e na exportação.
    final probeRotation = rotationOf(video);
    final rotation = probeRotation != 0
        ? probeRotation
        : (await readMp4Rotation(path) ?? 0);

    return VideoInfo(
      path: path,
      fileName: path.split('/').last,
      rawWidth: width,
      rawHeight: height,
      durationSeconds: duration,
      frameRate: frameRateOf(video),
      bitrateBps: int.tryParse(info.getBitrate() ?? '') ?? 0,
      fileSizeBytes: file.lengthSync(),
      codec: video.getCodec() ?? 'desconhecido',
      rotationDegrees: rotation,
    );
  }

  /// Cadeia de filtros da conversão — ver `filter_graph.dart`.
  String buildVideoFilter(ConversionSettings settings, VideoInfo video) =>
      buildConversionVideoFilter(settings, video);

  /// Filtros de brilho/contraste/saturação/temperatura — ver
  /// `filter_graph.dart`.
  @visibleForTesting
  List<String> colorAdjustFilters(ColorAdjustments adjustments) =>
      buildColorAdjustFilters(adjustments);

  Future<String?> _prepareImageFrameArt({
    required ConversionSettings settings,
    required VideoInfo video,
    required Directory dir,
    required String stamp,
  }) async {
    final asset = settings.frame.imageFrame;
    if (asset == null) return null;

    final (canvasWidth, canvasHeight) = settings.imageFrameCanvasDimensions(
      video,
    );
    final bytes = switch (asset.source) {
      ImageFrameSource.bundledSvg => await rasterizeSvgAsset(
        asset.svgAssetPath!,
        canvasWidth,
        canvasHeight,
      ),
      ImageFrameSource.importedSvg => await rasterizeSvgFile(
        asset.imageFilePath!,
        canvasWidth,
        canvasHeight,
      ),
      ImageFrameSource.importedImage => await rasterizeImportedImage(
        asset.imageFilePath!,
        canvasWidth,
        canvasHeight,
      ),
    };

    final path = '${dir.path}/moldura_img_$stamp.png';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Sobrepõe `FrameSettings.texts` no arquivo já pronto em [outputPath] —
  /// um segundo passo simples por cima do resultado final (que já saiu com
  /// moldura/recorte/cor aplicados), em vez de acrescentar mais uma entrada/
  /// `overlay` dentro de cada grafo de composição (que já são vários e
  /// complexos o bastante — ver [_framedGraph]/[_imageFramedGraph]/
  /// [_paletteGenArgs]). Os textos não animam, então a camada é um único PNG
  /// estático (ver `text_overlay_render.dart`), sobreposto a cada quadro do
  /// arquivo de saída; para o GIF, a paleta é recalculada depois da mistura
  /// pelo mesmo motivo de [_paletteGenArgs]/[_paletteUseArgs] — os textos
  /// podem trazer cores que a paleta original não reservou. Sem efeito
  /// nenhum (nem um arquivo temporário criado) quando não há texto algum.
  Future<void> _applyTextOverlay({
    required String outputPath,
    required ConversionSettings settings,
    required VideoInfo video,
    required Directory dir,
    required String stamp,
  }) async {
    final texts = settings.frame.texts;
    if (texts.isEmpty) return;

    final (width, height) = settings.outputDimensions(video);
    final layerBytes = await renderTextOverlayLayer(texts, width, height);
    final layerPath = '${dir.path}/texto_$stamp.png';
    await File(layerPath).writeAsBytes(layerBytes);

    final isWebp = settings.format == OutputFormat.webp;
    final mergedPath =
        '${dir.path}/texto_merge_$stamp.${settings.format.extension}';
    // Só existe transparência de verdade a preservar com uma moldura
    // (procedural ou de imagem) que a deixou ligada — sem moldura nenhuma o
    // resultado já sai sempre opaco (mesma condição de [webpArgs]/
    // [_paletteGenArgs]).
    final transparent =
        settings.frame.transparentBackground &&
        (settings.frame.hasImageFrame ||
            settings.frame.style != FrameStyle.none);

    try {
      final args = isWebp
          ? [
              '-y',
              '-i',
              outputPath,
              '-loop',
              '1',
              '-i',
              layerPath,
              '-lavfi',
              '[0:v]format=rgba[base];'
                  '[base][1:v]overlay=0:0:shortest=1[out]',
              '-map',
              '[out]',
              '-c:v',
              'libwebp',
              '-quality',
              '${settings.webpQuality}',
              '-compression_level',
              '2',
              '-pix_fmt',
              transparent ? 'yuva420p' : 'yuv420p',
              '-loop',
              settings.loop ? '0' : '1',
              '-an',
              '-f',
              'webp',
              mergedPath,
            ]
          : [
              '-y',
              '-i',
              outputPath,
              '-loop',
              '1',
              '-i',
              layerPath,
              '-lavfi',
              '[0:v]format=rgba[base];'
                  '[base][1:v]overlay=0:0:shortest=1[merged];'
                  '[merged]split=2[palette_source][gif_source];'
                  '[palette_source]palettegen=max_colors=${settings.colors}'
                  ':stats_mode=${settings.palette.statsMode}'
                  '${transparent ? ':reserve_transparent=1' : ''}[palette];'
                  '[gif_source][palette]paletteuse='
                  'dither=${settings.dither.ffmpegValue}'
                  '${transparent ? ':alpha_threshold=128' : ''}[out]',
              '-map',
              '[out]',
              '-loop',
              settings.loop ? '0' : '-1',
              '-an',
              mergedPath,
            ];
      await _run(args, step: 'texto sobre o ${settings.format.shortLabel}');

      final merged = File(mergedPath);
      if (!merged.existsSync() || merged.lengthSync() == 0) {
        throw FfmpegException(
          'Não foi possível desenhar o texto sobre o resultado.',
        );
      }
      await merged.copy(outputPath);
    } finally {
      _deleteQuietly(layerPath);
      _deleteQuietly(mergedPath);
    }
  }

  /// Argumentos completos do FFmpeg para uma moldura de imagem.
  ///
  /// Com "Fundo transparente" ligado segue o caminho com alfa (paleta com
  /// `reserve_transparent=1` + `paletteuse ... alpha_threshold=128`, mesmo
  /// padrão de [_transparentGifArgs], mas a partir de [_imageFramedGraph],
  /// que gera a máscara da área de conteúdo como filtro dentro do próprio
  /// grafo). Desligado, o GIF é opaco: sem máscara nenhuma, e a paleta é a
  /// comum, sem cor reservada para transparência.
  ///
  /// Público (sem `_`) só para dar acesso direto aos testes de unidade —
  /// [convert] continua sendo o único ponto de entrada em uso normal.
  @visibleForTesting
  /// Argumentos do GIF dentro de moldura de imagem — ver `gif_args.dart`.
  @visibleForTesting
  List<String> imageFramedGifArgs({
    required VideoInfo video,
    required ConversionSettings settings,
    required String artPath,
    required String outputPath,
    int? frameLimit,
  }) => buildImageFramedGifArgs(
    video: video,
    settings: settings,
    artPath: artPath,
    outputPath: outputPath,
    frameLimit: frameLimit,
  );

  /// Argumentos do WebP animado — ver `webp_args.dart`.
  @visibleForTesting
  List<String> webpArgs({
    required VideoInfo video,
    required ConversionSettings settings,
    required String outputPath,
    String? maskPath,
    int? frameLimit,
  }) => buildWebpArgs(
    video: video,
    settings: settings,
    outputPath: outputPath,
    maskPath: maskPath,
    frameLimit: frameLimit,
  );

  /// Argumentos do WebP dentro de moldura de imagem — ver `webp_args.dart`.
  @visibleForTesting
  List<String> webpImageFramedArgs({
    required VideoInfo video,
    required ConversionSettings settings,
    required String artPath,
    required String outputPath,
    int? frameLimit,
  }) => buildWebpImageFramedArgs(
    video: video,
    settings: settings,
    artPath: artPath,
    outputPath: outputPath,
    frameLimit: frameLimit,
  );

  Future<String?> _prepareMaskFile({
    required ConversionSettings settings,
    required VideoInfo video,
    required Directory dir,
    required String stamp,
  }) async {
    final frame = settings.frame;
    if (frame.style == FrameStyle.none ||
        frame.imageFrame != null ||
        !frame.transparentBackground) {
      return null;
    }

    final (canvasWidth, canvasHeight) = settings.outputDimensions(video);
    final outerRadius = FrameGeometry.of(
      Size(canvasWidth.toDouble(), canvasHeight.toDouble()),
      frame,
    ).outerRadius;

    final bytes = await rasterizeCornerMask(
      canvasWidth,
      canvasHeight,
      outerRadius,
    );
    final path = '${dir.path}/mascara_$stamp.png';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  Future<ConversionResult> convert({
    required VideoInfo video,
    required ConversionSettings settings,
    void Function(double progress)? onProgress,
  }) async {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final palettePath = '${dir.path}/paleta_$stamp.png';
    final isWebp = settings.format == OutputFormat.webp;
    final outputPath =
        '${dir.path}/${settings.format.extension}_$stamp.${settings.format.extension}';

    final totalMs = settings.outputDurationSeconds * 1000;
    String? maskPath;
    String? frameArtPath;

    try {
      if (settings.frame.imageFrame != null) {
        frameArtPath = await _prepareImageFrameArt(
          settings: settings,
          video: video,
          dir: dir,
          stamp: '$stamp',
        );
        await _run(
          isWebp
              ? webpImageFramedArgs(
                  video: video,
                  settings: settings,
                  artPath: frameArtPath!,
                  outputPath: outputPath,
                )
              : imageFramedGifArgs(
                  video: video,
                  settings: settings,
                  artPath: frameArtPath!,
                  outputPath: outputPath,
                ),
          onTimeMs: (ms) => onProgress?.call(_ratio(ms, totalMs)),
          step:
              'montagem do ${settings.format.shortLabel} com moldura de imagem',
        );
        var output = File(outputPath);
        if (!output.existsSync() || output.lengthSync() == 0) {
          throw FfmpegException(
            'O arquivo saiu vazio. Tente outro trecho do vídeo.',
          );
        }
        await _applyTextOverlay(
          outputPath: outputPath,
          settings: settings,
          video: video,
          dir: dir,
          stamp: '$stamp',
        );
        output = File(outputPath);
        onProgress?.call(1.0);

        final (width, height) = settings.outputDimensions(video);
        return ConversionResult(
          file: output,
          bytes: output.lengthSync(),
          width: width,
          height: height,
          frames: settings.frameCount,
          elapsed: stopwatch.elapsed,
          format: settings.format,
        );
      }

      maskPath = await _prepareMaskFile(
        settings: settings,
        video: video,
        dir: dir,
        stamp: '$stamp',
      );

      if (isWebp) {
        await _run(
          webpArgs(
            video: video,
            settings: settings,
            outputPath: outputPath,
            maskPath: maskPath,
          ),
          onTimeMs: (ms) => onProgress?.call(_ratio(ms, totalMs)),
          step: 'montagem do WebP',
        );
      } else if (maskPath != null && settings.frame.transparentBackground) {
        await _run(
          transparentGifArgs(
            video: video,
            settings: settings,
            maskPath: maskPath,
            outputPath: outputPath,
          ),
          onTimeMs: (ms) => onProgress?.call(_ratio(ms, totalMs)),
          step: 'montagem do GIF transparente',
        );
      } else {
        await _run(
          paletteGenArgs(
            video: video,
            settings: settings,
            palettePath: palettePath,
            maskPath: maskPath,
          ),
          onTimeMs: (ms) => onProgress?.call(_ratio(ms, totalMs) * 0.35),
          step: 'geração da paleta',
        );

        if (_cancelled) throw FfmpegException('Conversão cancelada.');

        await _run(
          paletteUseArgs(
            video: video,
            settings: settings,
            palettePath: palettePath,
            outputPath: outputPath,
            maskPath: maskPath,
          ),
          onTimeMs: (ms) => onProgress?.call(0.35 + _ratio(ms, totalMs) * 0.65),
          step: 'montagem do GIF',
        );
      }

      var output = File(outputPath);
      if (!output.existsSync() || output.lengthSync() == 0) {
        throw FfmpegException(
          'O arquivo saiu vazio. Tente outro trecho do vídeo.',
        );
      }
      await _applyTextOverlay(
        outputPath: outputPath,
        settings: settings,
        video: video,
        dir: dir,
        stamp: '$stamp',
      );
      output = File(outputPath);
      onProgress?.call(1.0);

      final (width, height) = settings.outputDimensions(video);
      return ConversionResult(
        file: output,
        bytes: output.lengthSync(),
        width: width,
        height: height,
        frames: settings.frameCount,
        elapsed: stopwatch.elapsed,
        format: settings.format,
      );
    } finally {
      _activeSessionId = null;
      _deleteQuietly(palettePath);
      if (maskPath != null) _deleteQuietly(maskPath);
      if (frameArtPath != null) _deleteQuietly(frameArtPath);
    }
  }

  /// Converte [video] para [format], sem nenhuma configuração exposta —
  /// usado pela tela "Converter formato" (`quick_convert_*`), que é um
  /// recurso à parte de "Editar GIF": só troca de formato, arquivo inteiro,
  /// sem corte/moldura/qualidade.
  ///
  /// GIF/WebP: monta um [ConversionSettings] fixo (arquivo inteiro, largura
  /// escolhida do mesmo jeito que [ConversionSettings.recommendedFor], sem
  /// ampliar) e reaproveita [convert] — mesmo pipeline de paleta/WebP já
  /// usado por "Editar GIF" (com a mesma correção de velocidade do WebP).
  ///
  /// MP4: linha de comando própria e simples — só limita a largura (mesmo
  /// teto de [ConversionSettings.recommendedFor], nunca amplia) e codifica
  /// o áudio quando existir. Sem `-map` explícito, o FFmpeg já escolhe
  /// sozinho o melhor stream de vídeo e (se houver) de áudio — se a fonte
  /// não tiver áudio (ex.: veio de um GIF), as flags de áudio simplesmente
  /// não têm efeito, sem precisar detectar isso antes.
  Future<File> quickConvert({
    required VideoInfo video,
    required QuickConvertFormat format,
    required int targetWidth,
    void Function(double progress)? onProgress,
  }) async {
    if (format.isAnimatedImage) {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: video.durationSeconds,
        targetWidth: targetWidth,
        format: format == QuickConvertFormat.gif
            ? OutputFormat.gif
            : OutputFormat.webp,
      );
      final result = await convert(
        video: video,
        settings: settings,
        onProgress: onProgress,
      );
      return result.file;
    }

    _cancelled = false;
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath =
        '${dir.path}/${format.extension}_$stamp.${format.extension}';
    final width = targetWidth;
    final totalMs = video.durationSeconds * 1000;

    try {
      await _run(
        quickConvertVideoArgs(
          video: video,
          format: format,
          width: width,
          outputPath: outputPath,
        ),
        onTimeMs: (ms) => onProgress?.call(_ratio(ms, totalMs)),
        step: 'conversão para ${format.label}',
      );
      onProgress?.call(1.0);

      final output = File(outputPath);
      if (!output.existsSync() || output.lengthSync() == 0) {
        throw FfmpegException('O arquivo saiu vazio.');
      }
      return output;
    } finally {
      _activeSessionId = null;
    }
  }

  /// Linha de comando de conversão para MP4, usada por [quickConvert].
  /// Público (sem `_`) só para os testes de unidade.
  ///
  /// Usa `h264_mediacodec` (o encoder de hardware do Android) em vez de
  /// `libx264` — este app usa a variante LGPL do FFmpeg
  /// (`ffmpeg_kit_flutter_new_video`, ver `docs/pt-Br/LICENCAS.md`), que não
  /// traz nenhum codec H.264 por software (GPL). Por ser um encoder de
  /// hardware, não aceita `-preset`/`-crf` (específicos do `libx264`).
  @visibleForTesting
  List<String> quickConvertVideoArgs({
    required VideoInfo video,
    required QuickConvertFormat format, // só mp4 chega aqui hoje
    required int width,
    required String outputPath,
  }) {
    return [
      '-y',
      '-i',
      video.path,
      '-vf',
      'scale=$width:-2:flags=lanczos',
      '-c:v',
      'h264_mediacodec',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-movflags',
      '+faststart',
      '-f',
      'mp4',
      outputPath,
    ];
  }

  /// Teto abaixo de 100% enquanto a sessão do FFmpeg ainda não terminou de
  /// verdade — sobretudo no WebP, o `-f webp` do FFmpeg relata os quadros
  /// (o que move essa razão via `onTimeMs`) bem antes da compressão de
  /// verdade + montagem do contêiner (`WebPAnimEncoderAssemble`) acabarem,
  /// numa chamada só, bloqueante, no final. Sem este teto a barra parecia
  /// chegar em ~100% e travar/arrastar. O salto pra 100% de verdade
  /// acontece só depois, no `onProgress?.call(1.0)` que já existe logo após
  /// cada `_run` (ver `convert`) — este teto não muda o tempo real nenhum,
  /// só evita que a barra "minta" que já terminou antes de terminar.
  static const _inProgressCeiling = 0.92;

  double _ratio(double ms, double totalMs) => totalMs <= 0
      ? 0
      : (ms / totalMs).clamp(0.0, _inProgressCeiling).toDouble();

  Future<void> _run(
    List<String> arguments, {
    required String step,
    void Function(double ms)? onTimeMs,
  }) async {
    final completer = Completer<void>();

    final session = await FFmpegKit.executeWithArgumentsAsync(
      arguments,
      (session) async {
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          completer.complete();
        } else if (ReturnCode.isCancel(code)) {
          completer.completeError(FfmpegException('Conversão cancelada.'));
        } else {
          completer.completeError(
            FfmpegException(
              'O FFmpeg falhou durante a $step.',
              logs: await session.getAllLogsAsString() ?? '',
            ),
          );
        }
      },
      (_) {},
      (Statistics statistics) {
        onTimeMs?.call(statistics.getTime().toDouble());
      },
    );

    _activeSessionId = session.getSessionId();
    return completer.future;
  }

  /// Codifica uma sequência de PNGs numerados (`.../quadro_%05d.png`, gerada
  /// por `collage_animation.dart`) num GIF ou WebP animado.
  ///
  /// GIF: mesmo par `palettegen`/`paletteuse` do caminho de vídeo, com
  /// `reserve_transparent`/`alpha_threshold` — a montagem pode ter fundo
  /// transparente, e o GIF só suporta 1 bit de alfa. WebP: um passe só no
  /// `libwebp`, que aceita alfa de verdade (ver [_webpEncodeArgs]).
  ///
  /// Os argumentos são montados por [collageSequenceArgs], separado para os
  /// testes poderem conferir a linha de comando sem rodar o FFmpeg.
  Future<File> encodeCollageSequence({
    required String framePattern,
    required int fps,
    required String outputPath,
    required bool webp,
    int colors = 256,
    bool loop = true,
    int? frameCount,
    void Function(double progress)? onProgress,
  }) async {
    // Com o número de quadros dá para transformar o tempo já codificado
    // (relatado pelo FFmpeg em ms de mídia) em fração — sem isso a barra
    // ficaria parada durante toda a codificação.
    final totalMs = (frameCount ?? 0) > 0 && fps > 0
        ? frameCount! * 1000 / fps
        : 0.0;
    await _run(
      collageSequenceArgs(
        framePattern: framePattern,
        fps: fps,
        outputPath: outputPath,
        webp: webp,
        colors: colors,
        loop: loop,
      ),
      step: 'exportação da montagem',
      // Mesmo teto de [_ratio] usado por [convert] — sem ele a barra também
      // parece travar perto do fim no WebP da montagem, pelo mesmo motivo
      // (a montagem do contêiner WebPAnimEncoderAssemble roda numa chamada
      // bloqueante só, depois do último quadro já ter sido "reportado").
      onTimeMs: onProgress == null || totalMs <= 0
          ? null
          : (ms) => onProgress(_ratio(ms, totalMs)),
    );
    onProgress?.call(1.0);

    final output = File(outputPath);
    if (!output.existsSync() || output.lengthSync() == 0) {
      throw FfmpegException('O arquivo saiu vazio.');
    }
    return output;
  }

  /// Linha de comando de [encodeCollageSequence]. Público (sem `_`) só para
  /// os testes de unidade.
  @visibleForTesting
  List<String> collageSequenceArgs({
    required String framePattern,
    required int fps,
    required String outputPath,
    required bool webp,
    int colors = 256,
    bool loop = true,
  }) {
    final input = ['-y', '-framerate', '$fps', '-i', framePattern];
    if (webp) {
      return [
        ...input,
        '-c:v',
        'libwebp',
        // 92 no lugar de 85: a montagem costuma ter arte com linhas finas e
        // texto, onde 85 deixava halo visível em volta das bordas. Quem
        // resolve isso é só o -quality — o -compression_level (o "method"
        // do libwebp) não muda qualidade visual nenhuma, só troca tempo de
        // CPU por tamanho de arquivo (mesmo comentário em
        // [_webpEncodeArgs]), por isso fica no mesmo 2 do caminho principal
        // em vez de um 6 que só deixava a montagem final do contêiner WebP
        // mais lenta sem ganho nenhum.
        '-quality',
        '92',
        '-compression_level',
        '2',
        '-pix_fmt',
        'yuva420p',
        '-loop',
        loop ? '0' : '1',
        '-an',
        '-f',
        'webp',
        outputPath,
      ];
    }
    return [
      ...input,
      '-filter_complex',
      '[0:v]split[pal_src][gif_src];'
          '[pal_src]palettegen=max_colors=$colors:reserve_transparent=1[pal];'
          // sierra2_4a no lugar de bayer: o padrão quadriculado do bayer
          // aparecia em áreas lisas (parede, pele) da montagem. A difusão de
          // erro dá degradê mais limpo; em troca pode "fervilhar" um pouco
          // entre quadros, o que quase não se nota numa montagem de fotos.
          '[gif_src][pal]paletteuse=dither=sierra2_4a:'
          'alpha_threshold=128[out]',
      '-map',
      '[out]',
      '-gifflags',
      '-transdiff',
      '-loop',
      loop ? '0' : '-1',
      '-f',
      'gif',
      outputPath,
    ];
  }

  Future<void> cancel() async {
    _cancelled = true;
    final id = _activeSessionId;
    if (id != null) {
      await FFmpegKit.cancel(id);
    }
  }

  Future<ComplexityProfile> calibrate({
    required VideoInfo video,
    required ConversionSettings settings,
    int sampleCount = 2,
    void Function(double progress)? onProgress,
  }) async {
    final duration = settings.sourceDurationSeconds;
    if (duration <= 0) return ComplexityProfile.fallback;

    // O modelo de estimativa de tamanho é específico da paleta/LZW do GIF
    // (ver size_estimator.dart) — não existe um equivalente para WebP ainda,
    // e a UI já não chama calibrate() para WebP (ver editor_page.dart). Essa
    // guarda evita rodar a amostragem em GIF por engano caso algum caminho
    // esquecido chame calibrate() com um formato WebP.
    if (settings.format == OutputFormat.webp) {
      return SizeEstimator.profileFromSource(video);
    }

    final minWindow = 5 / settings.fps * settings.speed;
    var window = duration / 4;
    if (window < minWindow) window = minWindow;
    if (window > 1.0) window = 1.0;
    if (window > duration) window = duration;

    final positions = _samplePositions(
      start: settings.startSeconds,
      duration: duration,
      window: window,
      count: sampleCount,
    );

    final dir = await getTemporaryDirectory();
    final profiles = <ComplexityProfile>[];

    final maskPath = await _prepareMaskFile(
      settings: settings,
      video: video,
      dir: dir,
      stamp: 'calib_${DateTime.now().millisecondsSinceEpoch}',
    );
    final frameArtPath = await _prepareImageFrameArt(
      settings: settings,
      video: video,
      dir: dir,
      stamp: 'calib_${DateTime.now().millisecondsSinceEpoch}',
    );

    try {
      for (var i = 0; i < positions.length; i++) {
        final sample = settings.copyWith(
          startSeconds: positions[i],
          endSeconds: positions[i] + window,
        );

        final stamp = '${DateTime.now().millisecondsSinceEpoch}_$i';
        final palettePath = '${dir.path}/amostra_$stamp.png';
        final gifPath = '${dir.path}/amostra_$stamp.gif';
        final firstFramePath = '${dir.path}/amostra_${stamp}_q1.gif';

        try {
          if (frameArtPath != null) {
            await _run(
              imageFramedGifArgs(
                video: video,
                settings: sample,
                artPath: frameArtPath,
                outputPath: gifPath,
              ),
              step: 'medição',
            );
            await _run(
              imageFramedGifArgs(
                video: video,
                settings: sample,
                artPath: frameArtPath,
                outputPath: firstFramePath,
                frameLimit: 1,
              ),
              step: 'medição',
            );
          } else if (maskPath != null && sample.frame.transparentBackground) {
            await _run(
              transparentGifArgs(
                video: video,
                settings: sample,
                maskPath: maskPath,
                outputPath: gifPath,
              ),
              step: 'medição',
            );
            await _run(
              transparentGifArgs(
                video: video,
                settings: sample,
                maskPath: maskPath,
                outputPath: firstFramePath,
                frameLimit: 1,
              ),
              step: 'medição',
            );
          } else {
            await _run(
              paletteGenArgs(
                video: video,
                settings: sample,
                palettePath: palettePath,
                maskPath: maskPath,
              ),
              step: 'medição',
            );
            await _run(
              paletteUseArgs(
                video: video,
                settings: sample,
                palettePath: palettePath,
                outputPath: gifPath,
                maskPath: maskPath,
              ),
              step: 'medição',
            );
            await _run(
              paletteUseArgs(
                video: video,
                settings: sample,
                palettePath: palettePath,
                outputPath: firstFramePath,
                maskPath: maskPath,
                frameLimit: 1,
              ),
              step: 'medição',
            );
          }

          final gif = File(gifPath);
          final firstFrame = File(firstFramePath);
          if (gif.existsSync() &&
              gif.lengthSync() > 0 &&
              firstFrame.existsSync() &&
              firstFrame.lengthSync() > 0) {
            profiles.add(
              SizeEstimator.calibrate(
                measuredBytes: gif.lengthSync(),
                firstFrameBytes: firstFrame.lengthSync(),
                sampleSettings: sample,
                video: video,
              ),
            );
          }
        } on FfmpegException {
          // Uma amostra inválida não deve interromper as demais medições.
        } finally {
          _activeSessionId = null;
          _deleteQuietly(palettePath);
          _deleteQuietly(gifPath);
          _deleteQuietly(firstFramePath);
          onProgress?.call((i + 1) / positions.length);
        }
      }
    } finally {
      if (maskPath != null) _deleteQuietly(maskPath);
      if (frameArtPath != null) _deleteQuietly(frameArtPath);
    }

    if (profiles.isEmpty) return SizeEstimator.profileFromSource(video);
    return SizeEstimator.combineSamples(profiles);
  }

  List<double> _samplePositions({
    required double start,
    required double duration,
    required double window,
    required int count,
  }) {
    final safeCount = count < 1 ? 1 : count;
    final fractions = switch (safeCount) {
      1 => const [0.4],
      2 => const [0.2, 0.6],
      _ => const [0.1, 0.45, 0.75],
    };

    final maxStart = start + duration - window;
    return fractions.take(safeCount).map((f) {
      final position = start + duration * f;
      return position > maxStart
          ? (maxStart < start ? start : maxStart)
          : position;
    }).toList();
  }

  Future<File?> extractFrame({
    required VideoInfo video,
    required double atSeconds,
    int width = 720,
  }) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/quadro_${DateTime.now().millisecondsSinceEpoch}.jpg';

    try {
      await _run([
        '-y',
        '-ss',
        ffmpegSeconds(atSeconds),
        '-i',
        video.path,
        '-frames:v',
        '1',
        '-vf',
        'scale=$width:-2:flags=lanczos',
        '-q:v',
        '3',
        path,
      ], step: 'extração de quadro');
    } on FfmpegException {
      return null;
    } finally {
      _activeSessionId = null;
    }

    final file = File(path);
    return file.existsSync() ? file : null;
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // A limpeza é de melhor esforço; o arquivo temporário pode já ter sumido.
    }
  }
}
