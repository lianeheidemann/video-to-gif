import 'dart:ui' show Size;

import '../models/color_adjustments.dart';
import '../models/conversion_settings.dart';
import '../models/frame_settings.dart';
import '../models/video_info.dart';
import '../painting/frame_painter.dart';
import 'ffmpeg_primitives.dart';

/// Montagem da cadeia de filtros do FFmpeg: recorte, escala, velocidade,
/// ajuste de cor, moldura procedural e moldura de imagem.
///
/// Fica separado da execução de propósito: a calibração e a conversão final
/// precisam usar *exatamente* a mesma cadeia, senão a estimativa medida não
/// bate com o resultado.

String buildConversionVideoFilter(
  ConversionSettings settings,
  VideoInfo video,
) {
  final parts = <String>[];

  final crop = settings.crop;
  if (crop != null) {
    parts.add('crop=${crop.width}:${crop.height}:${crop.x}:${crop.y}');
  }

  if (settings.speed != 1.0) {
    parts.add('setpts=PTS/${settings.speed}');
  }

  parts.add('fps=${settings.fps}');

  final (width, height) = settings.contentDimensions(video);
  parts.add('scale=$width:$height:flags=lanczos');

  // 5. ajuste de cor — por último, sobre a imagem já no tamanho final
  //    (menos pixels para processar) e só sobre o CONTEÚDO: a moldura e o
  //    fundo entram depois, nos grafos de moldura, e não passam por aqui.
  parts.addAll(buildColorAdjustFilters(settings.adjustments));

  return parts.join(',');
}

/// Traduz os oito ajustes de cor para filtros do FFmpeg, na mesma ordem em
/// que a prévia os aplica (ver `buildAdjustmentColorFilter`):
///
///  * `eq` faz a parte que trata os três canais igual (exposição, realces,
///    sombras, brilho e contraste), já composta num ganho e um
///    deslocamento por [ColorAdjustments.toneTransfer] — `eq` calcula
///    `(entrada - 0.5) * contrast + 0.5 + brightness`, então é só resolver
///    os dois parâmetros a partir do par;
///  * `colorchannelmixer` faz a parte que mistura canais (saturação, matiz
///    e temperatura), com a matriz de [ColorAdjustments.channelMixMatrix].
///
/// Sair dos mesmos números das matrizes é o que mantém o GIF exportado
/// igual ao que a prévia mostrou.
List<String> buildColorAdjustFilters(ColorAdjustments adjustments) {
  if (!adjustments.hasAdjustments) return const [];
  final filters = <String>[];

  final (gain, shift) = adjustments.toneTransfer;
  // O deslocamento vem na escala 0–255; o `eq` trabalha normalizado.
  final normalizedShift = shift / 255;
  if (gain != 1 || normalizedShift != 0) {
    final brightness = normalizedShift - 0.5 + 0.5 * gain;
    filters.add(
      'eq=contrast=${filterNumber(gain)}:'
      'brightness=${filterNumber(brightness)}',
    );
  }

  final m = adjustments.channelMixMatrix;
  if (!isIdentityMix(m)) {
    filters.add(
      'colorchannelmixer='
      'rr=${filterNumber(m[0])}:rg=${filterNumber(m[1])}:'
      'rb=${filterNumber(m[2])}:'
      'gr=${filterNumber(m[5])}:gg=${filterNumber(m[6])}:'
      'gb=${filterNumber(m[7])}:'
      'br=${filterNumber(m[10])}:bg=${filterNumber(m[11])}:'
      'bb=${filterNumber(m[12])}',
    );
  }

  return filters;
}

bool isIdentityMix(List<double> m) {
  const identity = [0, 1, 2, 5, 6, 7, 10, 11, 12];
  const expected = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];
  for (var i = 0; i < identity.length; i++) {
    if ((m[identity[i]] - expected[i]).abs() > 0.0001) return false;
  }
  return true;
}

/// Número no formato que o FFmpeg entende: ponto decimal, sem notação
/// científica (que a linha de comando não aceita) e sem casas demais.

String framedGraph(
  ConversionSettings settings,
  VideoInfo video, {
  required String input,
  required String output,
}) {
  final contentFilter = buildConversionVideoFilter(settings, video);
  final frame = settings.frame;

  final (contentWidth, contentHeight) = settings.contentDimensions(video);
  final (areaWidth, areaHeight, thickness) = settings.frameAreaDimensions(
    video,
  );
  final (canvasWidth, canvasHeight) = settings.outputDimensions(video);
  final colorHex = ffmpegColor(frame.color);
  final thicknessPx = thickness.round();
  final geometry = FrameGeometry.of(
    Size(canvasWidth.toDouble(), canvasHeight.toDouble()),
    frame,
  );
  final innerRadius = geometry.innerRadius;

  final parts = <String>['[$input]$contentFilter[content]'];

  if (contentWidth == areaWidth && contentHeight == areaHeight) {
    parts.add('[content]copy[fitted]');
  } else {
    final fit = resolveContentFit(
      frame.contentFit,
      contentWidth / contentHeight,
      areaWidth / areaHeight,
    );
    switch (fit) {
      case ContentFitMode.fill:
        parts.add(
          '[content]scale=$areaWidth:$areaHeight:'
          'force_original_aspect_ratio=increase:flags=lanczos,'
          'crop=$areaWidth:$areaHeight[fitted]',
        );
      case ContentFitMode.expand:
        parts.add(
          '[content]scale=$areaWidth:$areaHeight:'
          'force_original_aspect_ratio=decrease:flags=lanczos,'
          'pad=$areaWidth:$areaHeight:(ow-iw)/2:(oh-ih)/2:'
          'color=black[fitted]',
        );
      case ContentFitMode.auto:
      case ContentFitMode.fit:
        parts.add(
          '[content]scale=$areaWidth:$areaHeight:'
          'force_original_aspect_ratio=decrease:flags=lanczos,'
          'pad=$areaWidth:$areaHeight:(ow-iw)/2:(oh-ih)/2:'
          'color=$colorHex[fitted]',
        );
    }
  }

  // A prévia recorta o vídeo pelo raio interno e o desenha sobre a moldura.
  // A exportação precisa manter essa mesma ordem: primeiro o fundo colorido,
  // depois o vídeo já recortado. Um `pad` simples deixava o vídeo retangular
  // e uma composição invertida fazia a borda cobrir parte dele.
  parts.add('[fitted]format=rgba,setpts=PTS-STARTPTS[fitted_rgba]');
  parts.add(
    '${grayCanvas(settings, areaWidth, areaHeight)}'
    '${roundedLumaChain(innerRadius)}[inner_mask]',
  );
  parts.add('[fitted_rgba][inner_mask]alphamerge=shortest=1[rounded_content]');
  parts.addAll(
    frameBackgroundParts(
      settings,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      colorHex: colorHex,
      outerRadius: geometry.outerRadius,
    ),
  );
  parts.add(
    '[frame_background][rounded_content]overlay='
    '$thicknessPx:$thicknessPx:shortest=1:repeatlast=0[$output]',
  );

  return parts.join(';');
}

/// Fonte `color` branca em escala de cinza do tamanho pedido, com a
/// duração e o fps da saída — a base de todas as máscaras deste arquivo.
String grayCanvas(ConversionSettings settings, int width, int height) =>
    'color=white:s=${width}x$height:r=${settings.fps}:'
    'd=${ffmpegSeconds(settings.outputDurationSeconds)},format=gray';

/// Filtro que recorta uma máscara em escala de cinza numa forma de cantos
/// arredondados de raio [radius], já com a vírgula que o encadeia ao
/// filtro anterior — string vazia quando o raio é zero, porque aí a forma
/// é o próprio retângulo. É a mesma expressão para o raio interno (janela
/// do vídeo) e para o externo (contorno da moldura); escrevê-la uma vez só
/// garante que as duas nunca divirjam.
String roundedLumaChain(double radius) {
  if (radius <= 0) return '';
  final r = radius.toStringAsFixed(3);
  return ",geq=lum='clip(($r+0.5-hypot(max(abs(X-(W-1)/2)-((W-1)/2-$r),0),"
      "max(abs(Y-(H-1)/2)-((H-1)/2-$r),0)))*255,0,255)'";
}

/// O `[frame_background]` sobre o qual o vídeo é composto.
///
/// Com "Fundo transparente" ligado, basta o retângulo na cor da moldura:
/// a máscara externa ([_prepareMaskFile]) recorta os cantos depois. Com o
/// toggle desligado não há máscara nenhuma, então é aqui que a forma
/// arredondada precisa aparecer — cor da moldura dentro dela e a cor de
/// fundo escolhida nos cantos que sobram. Sem isso o modo opaco pintava o
/// canvas inteiro com a cor da moldura e o arredondamento sumia, divergindo
/// de `paintFrame`.
List<String> frameBackgroundParts(
  ConversionSettings settings, {
  required int canvasWidth,
  required int canvasHeight,
  required String colorHex,
  required double outerRadius,
}) {
  final flat =
      'color=c=$colorHex:s=${canvasWidth}x$canvasHeight:'
      'r=${settings.fps}:d=${ffmpegSeconds(settings.outputDurationSeconds)}';

  if (settings.frame.transparentBackground || outerRadius <= 0) {
    return ['$flat[frame_background]'];
  }

  final backgroundHex = ffmpegColor(settings.frame.backgroundColor);
  return [
    'color=c=$backgroundHex:s=${canvasWidth}x$canvasHeight:'
        'r=${settings.fps}:d=${ffmpegSeconds(settings.outputDurationSeconds)}'
        '[bg_opaque]',
    '$flat,format=rgba[frame_color]',
    '${grayCanvas(settings, canvasWidth, canvasHeight)}'
        '${roundedLumaChain(outerRadius)}[outer_mask]',
    '[frame_color][outer_mask]alphamerge=shortest=1[frame_rrect]',
    // `format=rgb`: sem isso o overlay compõe em yuv420 e a borda
    // arredondada, que é antisserrilhada, perde definição na
    // subamostragem de croma logo antes de virar paleta de GIF.
    '[bg_opaque][frame_rrect]overlay=0:0:shortest=1:format=rgb'
        '[frame_background]',
  ];
}

/// Grafo de filtro completo pronto para `-lavfi` quando a moldura é uma
/// arte de imagem ([FrameSettings.imageFrame]) — diferente de
/// [framedGraph] (que desenha a borda com `pad` de cor sólida), aqui o
/// conteúdo é ajustado para a área de conteúdo da arte
/// ([ConversionSettings.imageFrameContentAreaPx]) e a arte (já
/// rasterizada em [artInput], no tamanho exato do canvas) é composta por
/// cima via `overlay`, usando o próprio canal alfa da arte — sem precisar
/// de [rasterizeCornerMask]/[_prepareMaskFile], que só existem para os
/// cantos arredondados da moldura procedural.
///
/// Com "Fundo transparente" ligado, a transparência final vem da união
/// (`blend=lighten`, ou seja, máximo por pixel) de dois mapas em escala de
/// cinza: o canal alfa da própria arte (o corpo do mockup) e um retângulo
/// sólido do tamanho exato da área de conteúdo (onde o vídeo sempre
/// aparece opaco, mesmo nas barras de "Encaixar", que não têm cor de
/// moldura configurável — por isso usam preto). [areaMaskInput] é uma
/// fonte `color` do `lavfi`, gerada direto no grafo, sem precisar de um
/// arquivo temporário; só é usada nesse caso, e por isso é opcional.
///
/// Com o toggle desligado, nada disso é necessário: o `pad` que centraliza
/// o conteúdo já preenche o canvas com a cor de fundo escolhida, e o grafo
/// termina no `overlay` da arte.
String imageFramedGraph(
  ConversionSettings settings,
  VideoInfo video, {
  required String input,
  required String artInput,
  bool needsAreaMask = false,
  required String output,
}) {
  final contentFilter = buildConversionVideoFilter(settings, video);
  final frame = settings.frame;

  final (contentWidth, contentHeight) = settings.contentDimensions(video);
  final (areaX, areaY, areaWidth, areaHeight) = settings
      .imageFrameContentAreaPx(video);
  final (canvasWidth, canvasHeight) = settings.imageFrameCanvasDimensions(
    video,
  );
  final backgroundHex = ffmpegColor(frame.backgroundColor);

  final parts = <String>['[$input]$contentFilter[content]'];

  final fit = resolveContentFit(
    frame.contentFit,
    contentWidth / contentHeight,
    areaWidth / areaHeight,
  );

  if (fit == ContentFitMode.expand) {
    // O fundo permanece preto. O zoom atua somente no vídeo nítido central:
    // abaixo de 100% revela mais da área preta; acima de 100% aproxima e o
    // overlay recorta o excedente.
    final widthScale = areaWidth / contentWidth;
    final heightScale = areaHeight / contentHeight;
    final fitScale = widthScale < heightScale ? widthScale : heightScale;
    final fittedWidth = evenAtLeast2(contentWidth * fitScale);
    final fittedHeight = evenAtLeast2(contentHeight * fitScale);
    final zoom = frame.effectiveContentZoom;
    final zoomedWidth = evenAtLeast2(fittedWidth * zoom);
    final zoomedHeight = evenAtLeast2(fittedHeight * zoom);

    parts.add('[content]split=2[bg][fg]');
    parts.add(
      '[bg]scale=$areaWidth:$areaHeight:flags=lanczos,'
      'drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill[bg2]',
    );
    parts.add('[fg]scale=$zoomedWidth:$zoomedHeight:flags=lanczos[fg2]');
    parts.add('[bg2][fg2]overlay=(W-w)/2:(H-h)/2[fitted]');
  } else if (contentWidth == areaWidth && contentHeight == areaHeight) {
    parts.add('[content]copy[fitted]');
  } else if (fit == ContentFitMode.fill) {
    parts.add(
      '[content]scale=$areaWidth:$areaHeight:'
      'force_original_aspect_ratio=increase:flags=lanczos,'
      'crop=$areaWidth:$areaHeight[fitted]',
    );
  } else {
    parts.add(
      '[content]scale=$areaWidth:$areaHeight:'
      'force_original_aspect_ratio=decrease:flags=lanczos,'
      'pad=$areaWidth:$areaHeight:(ow-iw)/2:(oh-ih)/2:'
      'color=black[fitted]',
    );
  }

  parts.add(
    '[fitted]pad=$canvasWidth:$canvasHeight:$areaX:$areaY:'
    'color=$backgroundHex[base]',
  );
  parts.add('[$artInput]setpts=PTS-STARTPTS[art]');
  // A arte e a máscara são entradas em loop. Sem `shortest`, o overlay
  // continua repetindo o último quadro do vídeo para sempre e a conversão
  // de molduras de imagem fica presa em 0%. O vídeo é a entrada principal,
  // portanto ele também define o fim da composição.
  if (!needsAreaMask) {
    parts.add('[base][art]overlay=0:0:shortest=1:repeatlast=0[$output]');
    return parts.join(';');
  }

  parts.add(
    '[base][art]overlay=0:0:shortest=1:repeatlast=0,'
    'format=rgba[visual]',
  );
  parts.add(
    '[$artInput]alphaextract,format=gray,setpts=PTS-STARTPTS[art_alpha]',
  );
  // Cor sólida do tamanho da área de conteúdo, gerada como filtro
  // (`libavfilter`) dentro do próprio grafo — não como uma entrada
  // `-f lavfi` separada. Essa entrada depende do dispositivo de entrada
  // `lavfi` do `libavdevice`, que builds de FFmpeg para celular (o
  // `ffmpeg_kit_flutter_new_video` usado aqui incluso) costumam remover —
  // sem faz sentido nenhum dos dispositivos de captura de tela/áudio de
  // desktop num app de celular. Isso fazia a exportação falhar direto na
  // abertura das entradas, com "Unknown input format: 'lavfi'", sempre que
  // "Fundo transparente" estava ligado (o padrão).
  parts.add(
    'color=white:size=${areaWidth}x$areaHeight:rate=${settings.fps}'
    '[area_src]',
  );
  parts.add(
    '[area_src]pad=$canvasWidth:$canvasHeight:$areaX:$areaY:'
    'color=black,format=gray,setpts=PTS-STARTPTS[area_mask]',
  );
  parts.add('[art_alpha][area_mask]blend=all_mode=lighten[final_mask]');
  parts.add('[visual][final_mask]alphamerge=shortest=1[$output]');

  return parts.join(';');
}

/// Rasteriza a arte da moldura de imagem selecionada
/// ([FrameSettings.imageFrame]) num PNG de exatamente o tamanho do canvas
/// final ([ConversionSettings.imageFrameCanvasDimensions]) — nunca um
/// asset esticado, mesmo princípio de [_prepareMaskFile]. Devolve `null`
/// quando não há moldura de imagem selecionada.
