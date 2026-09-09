import 'dart:math' as math;
import 'dart:ui';

import 'collage_background.dart';
import 'color_adjustments.dart';
import 'default_colors.dart';
import 'crop_rect.dart';

// As matrizes de ajuste de cor moram em color_adjustments.dart (as três
// telas usam), mas continuam saindo daqui para quem já as importava.
export 'color_adjustments.dart'
    show ColorAdjustments, buildAdjustmentColorFilter;

/// Como a foto de uma célula preenche o espaço disponível: [cover] sempre
/// preenche a célula inteira sem sobra (recortando o excedente, comportamento
/// padrão e histórico do app); [contain] mostra a foto inteira, sem cortar
/// nada, deixando o fundo geral da montagem aparecer na sobra — alternado
/// pelo duplo toque na célula.
enum CollageCellFitMode { cover, contain }

/// Footprint (largura/altura) de um retângulo `w`x`h` depois de rotacionado
/// por [angle] radianos — o bounding-box axis-aligned clássico de um
/// retângulo girado. Usado nos dois sentidos:
///  - em [CollageCellSettings.coverSrcRect]/[paintCollageCell]/[_CellPhoto],
///    para saber de quanto a foto precisa "sobrar" (antes de girar) para
///    continuar cobrindo a célula inteira depois de girada — nunca deixa
///    canto vazio, generaliza a antiga troca de eixos em 90°/270° para
///    qualquer ângulo (em 0°/180° devolve `(w,h)`; em 90°/270° devolve
///    `(h,w)`, batendo com o comportamento anterior).
///  - invertido, para o modo [CollageCellFitMode.contain]: a maior escala que
///    ainda cabe a foto inteira dentro da célula depois de girada.
(double, double) rotatedFootprint(double w, double h, double angle) {
  final cosA = math.cos(angle).abs();
  final sinA = math.sin(angle).abs();
  return (w * cosA + h * sinA, w * sinA + h * cosA);
}

/// Configuração de uma célula da montagem: qual foto ocupa esse espaço, como
/// ela é enquadrada (deslocamento/zoom/rotação livre em relação ao recorte
/// "cover"/"contain" da célula), um recorte manual opcional (ver
/// [manualCrop]), sua rotação/espelhamento, o arredondamento e a borda
/// próprios da célula e os ajustes de cor aplicados só a ela.
///
/// [offsetX]/[offsetY] variam sempre em `[-1, 1]` e representam a fração da
/// folga de recorte/deslocamento disponível no eixo — não pixels fixos —,
/// então [coverSrcRect] nunca deixa a foto menor que a célula em modo
/// [CollageCellFitMode.cover] (sem "buracos"), qualquer que seja o valor
/// dentro desse intervalo.
class CollageCellSettings {
  const CollageCellSettings({
    this.photoPath,
    this.photoWidth = 0,
    this.photoHeight = 0,
    this.manualCrop,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.zoom = minZoom,
    this.rotation = 0.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.fitMode = CollageCellFitMode.cover,
    this.background = const CollageBackground(),
    this.cornerRatio = 0.0,
    this.borderThicknessAtReference = 0.0,
    this.borderColor = defaultFrameColor,
    this.brightness = 0.0,
    this.exposure = 0.0,
    this.contrast = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.saturation = 0.0,
    this.hue = 0.0,
    this.temperature = 0.0,
  });

  /// `null` representa uma célula ainda sem foto escolhida.
  final String? photoPath;
  final int photoWidth;
  final int photoHeight;

  /// Recorte manual opcional (ver `PhotoCropPage`), em pixels da foto na sua
  /// orientação nativa — sempre com a mesma proporção da célula (o recorte é
  /// travado a essa proporção na hora de escolher). Quando presente,
  /// [coverSrcRect]/[offsetDeltaForDrag] tratam [CropRect.width]/
  /// [CropRect.height] como as dimensões "efetivas" da foto (em vez de
  /// [photoWidth]/[photoHeight]) e deslocam o resultado por
  /// [CropRect.x]/[CropRect.y] — zoom/deslocamento/rotação continuam
  /// funcionando normalmente, só que dentro dessa sub-região em vez da foto
  /// inteira.
  final CropRect? manualCrop;

  final double offsetX;
  final double offsetY;

  /// Em [CollageCellFitMode.cover]: de [minZoom] (recorte padrão, preenche a
  /// célula sem sobra) a [maxZoom]. Em [CollageCellFitMode.contain]: `1.0` é
  /// a foto inteira ("ajustar" puro); acima disso amplia, podendo passar da
  /// célula (cortado pelo próprio arredondamento da célula).
  final double zoom;

  /// Rotação livre, em radianos — ao contrário das sobreposições
  /// (stickers/texto), a foto de célula continua presa ("cover"/"contain")
  /// dentro da própria célula em qualquer ângulo.
  final double rotation;
  final bool flipHorizontal;
  final bool flipVertical;

  final CollageCellFitMode fitMode;

  /// Fundo próprio desta foto: o que aparece atrás dela, dentro da célula (já
  /// dentro da borda própria, se houver) — mesmo modelo do fundo da montagem
  /// inteira ([CollageSettings.background]), só que por foto. Transparente
  /// (padrão) deixa o fundo da montagem aparecer na sobra do modo
  /// [CollageCellFitMode.contain], que era o único comportamento possível
  /// antes; cor/imagem preenchem só a área da célula. Em
  /// [CollageCellFitMode.cover] a foto cobre a célula inteira, então o fundo
  /// fica escondido — mas continua guardado, para reaparecer ao voltar para
  /// "encaixar".
  final CollageBackground background;

  /// Arredondamento do canto desta célula, como razão do menor lado da
  /// célula — mesma unidade proporcional de [FrameSettings.cornerRatio].
  final double cornerRatio;

  /// Espessura da borda só desta foto (não a da montagem inteira — ver
  /// [CollageSettings.borderThicknessAtReference] para isso), em pixels numa
  /// largura de referência de [referenceWidth]px. `0` = sem borda própria.
  final double borderThicknessAtReference;
  final Color borderColor;

  /// Ajustes de cor, todos em `[-1, 1]` (0 = neutro) e todos aplicados por
  /// uma matriz só ([colorFilter]/[buildAdjustmentColorFilter]), na ordem em
  /// que aparecem aqui.
  ///
  /// [brightness] soma luz linearmente (clareia sombras e altas junto);
  /// [exposure] multiplica (mais parecido com abrir o diafragma, mantém o
  /// preto no lugar); [highlights] e [shadows] puxam só a parte alta ou só a
  /// parte baixa da faixa; [hue] gira a roda de cores; [temperature] esquenta
  /// (mais vermelho, menos azul) ou esfria.
  final double brightness;
  final double exposure;
  final double contrast;
  final double highlights;
  final double shadows;
  final double saturation;
  final double hue;
  final double temperature;

  static const minZoom = 1.0;
  static const maxZoom = 4.0;
  static const maxCornerRatio = 0.5;
  static const maxBorderThickness = 24.0;

  /// Mesmo valor de [CollageSettings.referenceWidth] — duplicado aqui (em
  /// vez de importado) só para não criar um import circular entre os dois
  /// arquivos de modelo.
  static const referenceWidth = 480.0;

  bool get hasPhoto => photoPath != null;

  /// Largura/altura "efetivas" da foto para todo o resto desta classe: a
  /// foto inteira, ou — quando [manualCrop] está definido — só a sub-região
  /// recortada. Única fonte de verdade para não duplicar o `if (manualCrop
  /// != null)` em cada método.
  double get _effectiveWidth => (manualCrop?.width ?? photoWidth).toDouble();
  double get _effectiveHeight => (manualCrop?.height ?? photoHeight).toDouble();
  double get _effectiveOriginX => (manualCrop?.x ?? 0).toDouble();
  double get _effectiveOriginY => (manualCrop?.y ?? 0).toDouble();

  /// Retângulo de origem (pixels da foto decodificada) que [manualCrop]
  /// recorta — ou a foto inteira, sem recorte manual nenhum. Fonte comum
  /// para o "src" de `drawImageRect`/`_CroppedCover` em
  /// [CollageCellFitMode.contain], que — ao contrário de [coverSrcRect] —
  /// não tem zoom/offset próprios para compor com o recorte.
  Rect get manualCropSrcRect => Rect.fromLTWH(
    _effectiveOriginX,
    _effectiveOriginY,
    _effectiveWidth,
    _effectiveHeight,
  );

  double borderThicknessFor(double cellWidth) {
    if (cellWidth <= 0) return borderThicknessAtReference;
    return borderThicknessAtReference * (cellWidth / referenceWidth);
  }

  /// Retângulo de origem (em pixels da foto decodificada, na orientação
  /// nativa do arquivo) que cobre inteiramente uma célula de tamanho
  /// [cellSize] — o "cover" do `BoxFit.cover`, ciente de [zoom]/[offsetX]/
  /// [offsetY], de [rotation] (livre, qualquer ângulo — [rotatedFootprint]
  /// calcula de quanto a foto precisa "sobrar" para cobrir a célula mesmo
  /// depois de girada) e de [manualCrop] (ver [_effectiveWidth] etc.). Só
  /// faz sentido em [CollageCellFitMode.cover] — em [CollageCellFitMode.
  /// contain] use [containDisplayRect].
  Rect coverSrcRect(Size cellSize) {
    final photoW = _effectiveWidth;
    final photoH = _effectiveHeight;
    if (photoW <= 0 || photoH <= 0 || cellSize.isEmpty) {
      return Rect.zero;
    }

    final (destWidth, destHeight) = rotatedFootprint(
      cellSize.width,
      cellSize.height,
      rotation,
    );
    final srcAspect = photoW / photoH;
    final dstAspect = destWidth / destHeight;

    double baseWidth, baseHeight;
    if (srcAspect > dstAspect) {
      baseHeight = photoH;
      baseWidth = baseHeight * dstAspect;
    } else {
      baseWidth = photoW;
      baseHeight = baseWidth / dstAspect;
    }

    final z = zoom.clamp(minZoom, maxZoom);
    final cropWidth = (baseWidth / z).clamp(1.0, photoW);
    final cropHeight = (baseHeight / z).clamp(1.0, photoH);

    final maxOffsetX = (photoW - cropWidth) / 2;
    final maxOffsetY = (photoH - cropHeight) / 2;
    final ox = offsetX.clamp(-1.0, 1.0);
    final oy = offsetY.clamp(-1.0, 1.0);
    final centerX = _effectiveOriginX + photoW / 2 + ox * maxOffsetX;
    final centerY = _effectiveOriginY + photoH / 2 + oy * maxOffsetY;

    return Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: cropWidth,
      height: cropHeight,
    );
  }

  /// Tamanho (em pixels locais, antes da rotação do canvas) no qual a foto
  /// **inteira** deve ser desenhada, centralizada na célula, para o modo
  /// [CollageCellFitMode.contain] — o `BoxFit.contain` clássico, generalizado
  /// para uma célula que pode estar rotacionada: a maior escala tal que a
  /// foto, depois de girada, ainda cabe inteira dentro de [cellSize] (mesma
  /// fórmula de [rotatedFootprint], só que invertida: em vez de "de quanto a
  /// foto precisa sobrar para cobrir", pergunta "qual o maior tamanho que
  /// ainda cabe sem sobrar"). `zoom == 1` é o "ajustar" puro (foto inteira,
  /// sem ampliar); `zoom > 1` amplia a partir daí, podendo passar da célula
  /// (cortado pelo arredondamento da própria célula, igual ao cover).
  Size containDisplaySize(Size cellSize) {
    final photoW = _effectiveWidth;
    final photoH = _effectiveHeight;
    if (photoW <= 0 || photoH <= 0 || cellSize.isEmpty) return Size.zero;

    final (footprintW, footprintH) = rotatedFootprint(photoW, photoH, rotation);
    final baseScale = math.min(
      cellSize.width / footprintW,
      cellSize.height / footprintH,
    );
    final scale = baseScale * zoom.clamp(minZoom, maxZoom);
    return Size(photoW * scale, photoH * scale);
  }

  /// Deslocamento (em pixels locais, antes da rotação do canvas) do centro
  /// da foto em relação ao centro da célula, no modo [CollageCellFitMode.
  /// contain]. O alcance é baseado no tamanho da CÉLULA (metade da largura/
  /// altura), não em quanto a foto exibida excede a célula: assim o usuário
  /// pode mover a foto livremente de uma borda a outra da célula em
  /// qualquer zoom, inclusive no "ajustar" puro (foto inteira, menor que a
  /// célula) — antes disso ficava travado centralizado até ampliar, porque
  /// o alcance antigo zerava exatamente nesse ponto. A sobra vira o fundo
  /// geral da montagem (já pintado por baixo) e o recorte arredondado da
  /// própria célula corta visualmente o que passar da borda.
  Offset containDisplayOffset(Size cellSize) {
    if (containDisplaySize(cellSize) == Size.zero) return Offset.zero;

    final maxOffsetX = cellSize.width / 2;
    final maxOffsetY = cellSize.height / 2;
    final ox = offsetX.clamp(-1.0, 1.0);
    final oy = offsetY.clamp(-1.0, 1.0);
    return Offset(ox * maxOffsetX, oy * maxOffsetY);
  }

  /// Equivalente de [offsetDeltaForDrag] para o modo [CollageCellFitMode.
  /// contain]: converte um deslocamento em pixels de tela para o incremento
  /// de [offsetX]/[offsetY], desfazendo a rotação do mesmo jeito. A diferença
  /// de sinal em relação ao cover é proposital — lá o arrasto move a
  /// *janela de recorte* (efeito inverso: arrastar para a direita revela
  /// mais a partir da esquerda, mas com o mesmo resultado visual final de
  /// "a foto acompanha o dedo"); aqui o arrasto move a própria foto
  /// desenhada, então o mesmo resultado visual já sai direto, sem inverter.
  /// Mesmo alcance zoom-independente de [containDisplayOffset] (metade do
  /// tamanho da célula em cada eixo).
  Offset containOffsetDeltaForDrag(Offset screenDelta, Size cellSize) {
    if (containDisplaySize(cellSize) == Size.zero) return Offset.zero;

    final cosA = math.cos(rotation);
    final sinA = math.sin(rotation);
    var local = Offset(
      screenDelta.dx * cosA + screenDelta.dy * sinA,
      -screenDelta.dx * sinA + screenDelta.dy * cosA,
    );
    if (flipHorizontal) local = Offset(-local.dx, local.dy);
    if (flipVertical) local = Offset(local.dx, -local.dy);

    final maxOffsetX = cellSize.width / 2;
    final maxOffsetY = cellSize.height / 2;
    final dx = maxOffsetX > 0 ? local.dx / maxOffsetX : 0.0;
    final dy = maxOffsetY > 0 ? local.dy / maxOffsetY : 0.0;
    return Offset(dx, dy);
  }

  /// Proporção efetiva da foto já considerando a rotação (girada troca
  /// largura por altura na proporção que [rotatedFootprint] calcular).
  double get aspectRatio {
    final w = _effectiveWidth;
    final h = _effectiveHeight;
    if (w <= 0 || h <= 0) return 1;
    final (fw, fh) = rotatedFootprint(w, h, rotation);
    return fw / fh;
  }

  /// Converte um deslocamento em pixels de tela (ex.: [ScaleUpdateDetails.
  /// focalPointDelta] de um gesto sobre a célula) para o incremento
  /// correspondente de [offsetX]/[offsetY], levando em conta [zoom] atual, a
  /// orientação efetiva de [rotation] (ângulo livre — desfeito por uma
  /// rotação inversa genérica do vetor, não mais um `switch` de 4 casos) e
  /// de [flipHorizontal]/[flipVertical] — arrastar sempre desloca a foto na
  /// direção intuitiva na tela, mesmo girada ou espelhada. Só faz sentido em
  /// [CollageCellFitMode.cover]. Devolve `Offset.zero` quando não há folga
  /// naquele eixo (ex.: zoom no mínimo).
  Offset offsetDeltaForDrag(Offset screenDelta, Size cellSize) {
    final src = coverSrcRect(cellSize);
    if (src == Rect.zero) return Offset.zero;

    // Desfaz primeiro a rotação, depois o espelhamento — ordem inversa de
    // como o desenho aplica as duas (gira o canvas e só então espelha, tanto
    // aqui quanto em `paintCollageCell`/`Transform.rotate` na prévia), para
    // o arrasto sempre mover a foto na direção em que o dedo se move na
    // tela, qualquer que seja o ângulo atual. Rotação inversa genérica de um
    // vetor por `-rotation` (equivalente exato do antigo `switch` de 4 casos
    // em 0°/90°/180°/270°).
    final cosA = math.cos(rotation);
    final sinA = math.sin(rotation);
    var local = Offset(
      screenDelta.dx * cosA + screenDelta.dy * sinA,
      -screenDelta.dx * sinA + screenDelta.dy * cosA,
    );
    if (flipHorizontal) local = Offset(-local.dx, local.dy);
    if (flipVertical) local = Offset(local.dx, -local.dy);

    final (destWidth, destHeight) = rotatedFootprint(
      cellSize.width,
      cellSize.height,
      rotation,
    );
    if (destWidth <= 0 || destHeight <= 0) return Offset.zero;

    final scaleX = src.width / destWidth;
    final scaleY = src.height / destHeight;
    final maxOffsetX = (_effectiveWidth - src.width) / 2;
    final maxOffsetY = (_effectiveHeight - src.height) / 2;

    // Negativo: a janela de recorte se move para o lado OPOSTO ao dedo, que é
    // o que faz a própria foto parecer se mover JUNTO com o dedo (arrastar
    // para a direita revela mais do lado esquerdo da foto, como se ela
    // estivesse sendo empurrada para a direita) — a manipulação direta que o
    // usuário espera ao "arrastar a foto", não um pan de câmera/viewport.
    final dx = maxOffsetX > 0 ? -(local.dx * scaleX) / maxOffsetX : 0.0;
    final dy = maxOffsetY > 0 ? -(local.dy * scaleY) / maxOffsetY : 0.0;
    return Offset(dx, dy);
  }

  ColorFilter get colorFilter => buildAdjustmentColorFilter(
    brightness: brightness,
    exposure: exposure,
    contrast: contrast,
    highlights: highlights,
    shadows: shadows,
    saturation: saturation,
    hue: hue,
    temperature: temperature,
  );

  /// `true` quando nenhum ajuste de cor está em uso — atalho para a tela
  /// mostrar/esconder o "Redefinir" e para não gastar um passo de desfazer
  /// zerando o que já está zerado.
  bool get hasColorAdjustments =>
      brightness != 0 ||
      exposure != 0 ||
      contrast != 0 ||
      highlights != 0 ||
      shadows != 0 ||
      saturation != 0 ||
      hue != 0 ||
      temperature != 0;

  /// Volta todos os ajustes de cor ao neutro, sem tocar em mais nada.
  CollageCellSettings withoutColorAdjustments() => copyWith(
    brightness: 0,
    exposure: 0,
    contrast: 0,
    highlights: 0,
    shadows: 0,
    saturation: 0,
    hue: 0,
    temperature: 0,
  );

  CollageCellSettings copyWith({
    String? photoPath,
    bool clearPhoto = false,
    int? photoWidth,
    int? photoHeight,
    CropRect? manualCrop,
    bool clearManualCrop = false,
    double? offsetX,
    double? offsetY,
    double? zoom,
    double? rotation,
    bool? flipHorizontal,
    bool? flipVertical,
    CollageCellFitMode? fitMode,
    CollageBackground? background,
    double? cornerRatio,
    double? borderThicknessAtReference,
    Color? borderColor,
    double? brightness,
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? saturation,
    double? hue,
    double? temperature,
  }) {
    return CollageCellSettings(
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      photoWidth: photoWidth ?? this.photoWidth,
      photoHeight: photoHeight ?? this.photoHeight,
      manualCrop: clearManualCrop ? null : (manualCrop ?? this.manualCrop),
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      zoom: zoom ?? this.zoom,
      rotation: rotation ?? this.rotation,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      fitMode: fitMode ?? this.fitMode,
      background: background ?? this.background,
      cornerRatio: cornerRatio ?? this.cornerRatio,
      borderThicknessAtReference:
          borderThicknessAtReference ?? this.borderThicknessAtReference,
      borderColor: borderColor ?? this.borderColor,
      brightness: brightness ?? this.brightness,
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      saturation: saturation ?? this.saturation,
      hue: hue ?? this.hue,
      temperature: temperature ?? this.temperature,
    );
  }

  /// Reseta enquadramento (deslocamento/zoom/rotação/espelhamento) mantendo
  /// a foto, o recorte manual e os ajustes de cor/borda — usado no menu
  /// "Recentralizar" e ao substituir a foto de uma célula (o enquadramento
  /// antigo não faz sentido para outra foto, mas a cor/borda escolhidas para
  /// aquele espaço sim). [fitMode] e [background] não mudam aqui — são eixos
  /// independentes do enquadramento; o duplo toque na célula alterna o
  /// [fitMode] e aplica este mesmo reset por cima (ver `CollageCellView`).
  CollageCellSettings resetFraming() => copyWith(
    offsetX: 0,
    offsetY: 0,
    zoom: minZoom,
    rotation: 0.0,
    flipHorizontal: false,
    flipVertical: false,
  );
}
