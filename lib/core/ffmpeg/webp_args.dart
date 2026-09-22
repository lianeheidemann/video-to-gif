import '../models/conversion_settings.dart';
import '../models/frame_settings.dart';
import '../models/video_info.dart';
import 'ffmpeg_primitives.dart';
import 'filter_graph.dart';

/// Argumentos das saídas em WebP animado.

List<String> webpEncodeArgs(
  ConversionSettings settings, {
  required bool hasAlpha,
  bool shortest = false,
  int? frameLimit,
}) {
  return [
    '-map',
    '[out]',
    '-c:v',
    'libwebp',
    '-quality',
    '${settings.webpQuality}',
    '-compression_level',
    '2',
    '-pix_fmt',
    hasAlpha ? 'yuva420p' : 'yuv420p',
    '-loop',
    settings.loop ? '0' : '1',
    '-an',
    if (shortest) '-shortest',
    if (frameLimit != null) ...['-frames:v', '$frameLimit'],
    '-f',
    'webp',
  ];
}

/// Argumentos completos do FFmpeg para WebP animado sem moldura de imagem:
/// cobre tanto "sem moldura nenhuma" quanto moldura procedural (opaca ou
/// com fundo transparente). [maskPath] é a máscara de cantos arredondados
/// preparada por [_prepareMaskFile] — só é usada quando há moldura
/// procedural com fundo transparente; nos outros dois casos é ignorada.
///
/// Público (sem `_`) só para dar acesso direto aos testes de unidade —
/// [convert] continua sendo o único ponto de entrada em uso normal.
List<String> buildWebpArgs({
  required VideoInfo video,
  required ConversionSettings settings,
  required String outputPath,
  String? maskPath,
  int? frameLimit,
}) {
  // O `-map [out]` de [webpEncodeArgs] fixa o rótulo final, então quem muda
  // de nome quando há giro é o rótulo que o grafo produz — ver
  // [transformedInto].
  final (composed, tail) = transformedInto(settings.outputTransform, 'out');

  if (settings.frame.style == FrameStyle.none) {
    final filter = buildConversionVideoFilter(settings, video);
    return [
      '-y',
      '-ss',
      ffmpegSeconds(settings.startSeconds),
      '-t',
      ffmpegSeconds(settings.sourceDurationSeconds),
      '-i',
      video.path,
      '-lavfi',
      '[0:v]$filter[$composed]$tail',
      ...webpEncodeArgs(settings, hasAlpha: false, frameLimit: frameLimit),
      outputPath,
    ];
  }

  if (maskPath == null || !settings.frame.transparentBackground) {
    // Moldura procedural opaca: [framedGraph] já entrega um canvas RGB
    // "achatado" (sem transparência nenhuma), então basta ir direto ao
    // encoder — nem o `alphamerge` externo do GIF é necessário aqui.
    final graph = framedGraph(settings, video, input: '0:v', output: composed);
    return [
      '-y',
      '-ss',
      ffmpegSeconds(settings.startSeconds),
      '-t',
      ffmpegSeconds(settings.sourceDurationSeconds),
      '-i',
      video.path,
      '-lavfi',
      '$graph$tail',
      ...webpEncodeArgs(settings, hasAlpha: false, frameLimit: frameLimit),
      outputPath,
    ];
  }

  // Moldura procedural com fundo transparente: mesmo grafo/máscara de
  // [transparentGifArgs], mas sem o `split`/`palettegen`/`paletteuse` —
  // o `[alpha]` já é RGBA de verdade, então vira `[out]` direto.
  final graph = framedGraph(settings, video, input: '0:v', output: 'framed');
  return [
    '-y',
    '-ss',
    ffmpegSeconds(settings.startSeconds),
    '-t',
    ffmpegSeconds(settings.sourceDurationSeconds),
    '-i',
    video.path,
    '-loop',
    '1',
    '-framerate',
    '${settings.fps}',
    '-i',
    maskPath,
    '-lavfi',
    '$graph;'
        '[framed]format=rgba,setpts=PTS-STARTPTS[framed_rgba];'
        '[1:v]format=gray,fps=${settings.fps},'
        'setpts=PTS-STARTPTS[mask_gray];'
        '[framed_rgba][mask_gray]alphamerge=shortest=1[$composed]$tail',
    ...webpEncodeArgs(settings, hasAlpha: true, frameLimit: frameLimit),
    outputPath,
  ];
}

/// Argumentos completos do FFmpeg para WebP animado com moldura de imagem.
/// Reaproveita [imageFramedGraph] — que já entrega alfa real via
/// `alphamerge` quando "Fundo transparente" está ligado — e, como em
/// [buildWebpArgs], dispensa paleta: o grafo vai direto para o `libwebp`.
///
/// Mantém o `-shortest` global que o [buildImageFramedGifArgs] também usa: a
/// arte é uma entrada infinita (`-loop 1`), e por segurança (builds de
/// FFmpeg que não propagam EOF por todos os filtros complexos) a saída é
/// encerrada junto com o fluxo de vídeo.
///
/// Público (sem `_`) só para dar acesso direto aos testes de unidade —
/// [convert] continua sendo o único ponto de entrada em uso normal.
List<String> buildWebpImageFramedArgs({
  required VideoInfo video,
  required ConversionSettings settings,
  required String artPath,
  required String outputPath,
  int? frameLimit,
}) {
  final transparent = settings.frame.transparentBackground;
  final (composed, tail) = transformedInto(settings.outputTransform, 'out');
  final graph = imageFramedGraph(
    settings,
    video,
    input: '0:v',
    artInput: '1:v',
    needsAreaMask: transparent,
    output: composed,
  );

  return [
    '-y',
    '-ss',
    ffmpegSeconds(settings.startSeconds),
    '-t',
    ffmpegSeconds(settings.sourceDurationSeconds),
    '-i',
    video.path,
    '-loop',
    '1',
    '-framerate',
    '${settings.fps}',
    '-i',
    artPath,
    '-lavfi',
    '$graph$tail',
    ...webpEncodeArgs(
      settings,
      hasAlpha: transparent,
      shortest: true,
      frameLimit: frameLimit,
    ),
    outputPath,
  ];
}

/// Arredonda para o inteiro par mais próximo — mesma exigência de
/// crop/scale do FFmpeg já seguida por [ConversionSettings._evenFromDouble].
