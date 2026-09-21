import '../models/conversion_settings.dart';
import '../models/frame_settings.dart';
import '../models/video_info.dart';
import 'ffmpeg_primitives.dart';
import 'filter_graph.dart';

/// Argumentos das saídas em GIF: geração e uso da paleta, GIF com fundo
/// transparente e GIF dentro de uma moldura de imagem.

List<String> paletteGenArgs({
  required VideoInfo video,
  required ConversionSettings settings,
  required String palettePath,
  String? maskPath,
}) {
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
      '-vf',
      '$filter,palettegen=max_colors=${settings.colors}'
          ':stats_mode=${settings.palette.statsMode}',
      '-frames:v',
      '1',
      palettePath,
    ];
  }

  final transparent = settings.frame.transparentBackground;
  final graph = framedGraph(settings, video, input: '0:v', output: 'framed');
  final reserve = transparent ? ':reserve_transparent=1' : '';
  final paletteLabel = transparent ? 'alpha' : 'framed';
  final maskStage = transparent
      ? ';[framed][1:v]alphamerge[$paletteLabel]'
      : '';

  return [
    '-y',
    '-ss',
    ffmpegSeconds(settings.startSeconds),
    '-t',
    ffmpegSeconds(settings.sourceDurationSeconds),
    '-i',
    video.path,
    if (maskPath != null) ...[
      '-loop',
      '1',
      '-t',
      ffmpegSeconds(settings.outputDurationSeconds),
      '-i',
      maskPath,
    ],
    '-lavfi',
    '$graph$maskStage;'
        '[$paletteLabel]palettegen=max_colors=${settings.colors}'
        ':stats_mode=${settings.palette.statsMode}$reserve',
    '-frames:v',
    '1',
    palettePath,
  ];
}

List<String> paletteUseArgs({
  required VideoInfo video,
  required ConversionSettings settings,
  required String palettePath,
  required String outputPath,
  String? maskPath,
  int? frameLimit,
}) {
  final newPalette = settings.palette == PaletteMode.perFrame ? ':new=1' : '';

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
      '-i',
      palettePath,
      '-lavfi',
      '[0:v]$filter[v];[v][1:v]paletteuse=dither=${settings.dither.ffmpegValue}'
          ':diff_mode=rectangle$newPalette',
      '-loop',
      settings.loop ? '0' : '-1',
      '-an',
      if (frameLimit != null) ...['-frames:v', '$frameLimit'],
      '-f',
      'gif',
      outputPath,
    ];
  }

  final transparent = settings.frame.transparentBackground;
  final graph = framedGraph(settings, video, input: '0:v', output: 'framed');
  final useLabel = transparent ? 'alpha' : 'framed';
  final maskStage = transparent ? ';[framed][2:v]alphamerge[$useLabel]' : '';
  final alphaThreshold = transparent ? ':alpha_threshold=128' : '';

  return [
    '-y',
    '-ss',
    ffmpegSeconds(settings.startSeconds),
    '-t',
    ffmpegSeconds(settings.sourceDurationSeconds),
    '-i',
    video.path,
    '-i',
    palettePath,
    if (maskPath != null) ...[
      '-loop',
      '1',
      '-t',
      ffmpegSeconds(settings.outputDurationSeconds),
      '-i',
      maskPath,
    ],
    '-lavfi',
    '$graph$maskStage;'
        '[$useLabel][1:v]paletteuse=dither=${settings.dither.ffmpegValue}'
        ':diff_mode=rectangle$newPalette$alphaThreshold',
    '-loop',
    settings.loop ? '0' : '-1',
    '-an',
    if (frameLimit != null) ...['-frames:v', '$frameLimit'],
    // Sem isso, o muxer do GIF reaproveita pixels idênticos ao quadro
    // anterior como "transparentes" para economizar espaço, contando com
    // o descarte (disposal) do quadro anterior para redesenhá-los depois.
    // Toda a área estática da moldura (que não muda de um quadro para o
    // outro) acaba marcada assim — e visualizadores que não implementam
    // esse descarte corretamente (vários apps de galeria e mensagens)
    // pintam essa área com a cor reservada para transparência, que sai
    // verde. Desligar mantém cada quadro completo e correto sozinho.
    if (transparent) ...['-gifflags', '-transdiff'],
    '-f',
    'gif',
    outputPath,
  ];
}

/// Para GIF transparente, gera e aplica a paleta dentro do mesmo grafo.
/// Isso evita a segunda sessão com vídeo + paleta PNG + máscara, que é a
/// etapa que estava falhando no Android ao usar "Fundo transparente".
List<String> transparentGifArgs({
  required VideoInfo video,
  required ConversionSettings settings,
  required String maskPath,
  required String outputPath,
  int? frameLimit,
}) {
  final graph = framedGraph(settings, video, input: '0:v', output: 'framed');
  final newPalette = settings.palette == PaletteMode.perFrame ? ':new=1' : '';

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
        '[framed_rgba][mask_gray]alphamerge=shortest=1[alpha];'
        '[alpha]split=2[palette_source][gif_source];'
        '[palette_source]palettegen=max_colors=${settings.colors}'
        ':stats_mode=${settings.palette.statsMode}'
        ':reserve_transparent=1[palette];'
        '[gif_source][palette]paletteuse=dither=${settings.dither.ffmpegValue}'
        ':diff_mode=rectangle$newPalette:alpha_threshold=128[out]',
    '-map',
    '[out]',
    '-loop',
    settings.loop ? '0' : '-1',
    '-an',
    if (frameLimit != null) ...['-frames:v', '$frameLimit'],
    // Ver o comentário equivalente em [paletteUseArgs]: sem isso a área
    // estática da moldura sai verde em visualizadores que não descartam
    // (disposal) o quadro anterior corretamente.
    '-gifflags',
    '-transdiff',
    '-f',
    'gif',
    outputPath,
  ];
}

List<String> buildImageFramedGifArgs({
  required VideoInfo video,
  required ConversionSettings settings,
  required String artPath,
  required String outputPath,
  int? frameLimit,
}) {
  final transparent = settings.frame.transparentBackground;
  final graph = imageFramedGraph(
    settings,
    video,
    input: '0:v',
    artInput: '1:v',
    needsAreaMask: transparent,
    output: 'framed',
  );
  final newPalette = settings.palette == PaletteMode.perFrame ? ':new=1' : '';
  final reserve = transparent ? ':reserve_transparent=1' : '';
  final alphaThreshold = transparent ? ':alpha_threshold=128' : '';

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
    '$graph;'
        '[framed]split=2[palette_source][gif_source];'
        '[palette_source]palettegen=max_colors=${settings.colors}'
        ':stats_mode=${settings.palette.statsMode}$reserve[palette];'
        '[gif_source][palette]paletteuse=dither=${settings.dither.ffmpegValue}'
        ':diff_mode=rectangle$newPalette$alphaThreshold[out]',
    '-map',
    '[out]',
    '-loop',
    settings.loop ? '0' : '-1',
    '-an',
    // As entradas da arte e da máscara são infinitas; encerra a saída junto
    // com o fluxo de vídeo, mesmo em builds do FFmpeg que não propagam o EOF
    // através de todos os filtros complexos.
    '-shortest',
    if (frameLimit != null) ...['-frames:v', '$frameLimit'],
    // Ver o comentário equivalente em [paletteUseArgs]: sem isso a área
    // estática da arte (o corpo do mockup, o fundo fora dele) sai verde em
    // visualizadores que não descartam (disposal) o quadro anterior
    // corretamente.
    if (transparent) ...['-gifflags', '-transdiff'],
    '-f',
    'gif',
    outputPath,
  ];
}

/// Cauda de encode comum a todo caminho de WebP: um único passe, sem
/// paleta nenhuma. Diferente do GIF — que precisa de `palettegen`/
/// `paletteuse` em dois passes e, no caso transparente, do hack de
/// `reserve_transparent`/`alpha_threshold`/`-gifflags -transdiff` por só
/// suportar 1 bit de alfa —, o `libwebp` aceita cor cheia e alfa real em
/// 8 bits direto do grafo de composição (o mesmo usado pelo GIF). Por
/// isso [hasAlpha] só decide o `-pix_fmt` final, nada mais.
///
/// `-compression_level 2` (em vez do padrão `4` do próprio `libwebp`): essa
/// opção é o "method" do libwebp — quanto o codificador se esforça
/// procurando a melhor compressão. Não muda a qualidade visual (isso é só
/// `-quality`, acima), só troca tempo de CPU por tamanho de arquivo. Nunca
/// tinha sido ajustada de propósito aqui (diferente do caminho da
/// sequência de quadros da montagem, que sobe pra `6` com uma troca
/// documentada) — 4 era só o que sobrava de não setar nada. Baixar pra 2
/// acelera bastante a conversão, principalmente a montagem final do
/// contêiner WebP (`WebPAnimEncoderAssemble`), que roda tudo de uma vez no
/// final e é onde a demora "trava" mais se sente.
