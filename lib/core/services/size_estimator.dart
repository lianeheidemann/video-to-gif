import 'dart:math' as math;

import '../models/conversion_settings.dart';
import '../models/frame_settings.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';

/// "Quanta informação por pixel" a cena deste vídeo tem.
///
/// É o único número que depende do conteúdo do vídeo. Todo o resto do modelo
/// (fps, cores, dither, escala, velocidade) é conhecido antes de converter.
/// Por isso vale a pena medir isso UMA vez, com uma amostra curta, e reusar o
/// valor enquanto o usuário mexe nos controles.
///
/// São dois números, e não um, porque num GIF o primeiro quadro não custa o
/// mesmo que os outros — ver [SizeEstimator].
class ComplexityProfile {
  const ComplexityProfile({
    required this.bytesPerPixel,
    required this.keyBytesPerPixel,
    required this.confidence,
  });

  /// Bytes por pixel de cada quadro **depois do primeiro**, nas condições de
  /// referência (ver [SizeEstimator]). É só o retângulo que mudou.
  final double bytesPerPixel;

  /// Bytes por pixel do **primeiro** quadro, que é sempre uma imagem
  /// completa. Costuma ser muito mais caro que os seguintes.
  final double keyBytesPerPixel;

  final EstimateConfidence confidence;

  /// Valores médios observados em vídeos comuns de celular. Servem de ponto
  /// de partida enquanto nenhuma medição foi feita.
  static const fallback = ComplexityProfile(
    bytesPerPixel: 0.16,
    keyBytesPerPixel: 0.25,
    confidence: EstimateConfidence.rough,
  );
}

/// Estima o peso do GIF *antes* de converter.
///
/// ## Por que dá para estimar
///
/// Um GIF é uma sequência de quadros paletizados comprimidos com LZW, e o
/// FFmpeg ainda regrava só o retângulo que mudou de um quadro para o outro
/// (`diff_mode=rectangle`).
///
/// Isso divide os quadros em duas espécies com preços bem diferentes:
///
///  - o **primeiro** é uma imagem completa, porque não há quadro anterior
///    para comparar;
///  - os **demais** custam só a área que mudou.
///
///     bytes ≈ cabeçalho + paleta
///             + largura × altura × kChave
///             + (quadros − 1) × largura × altura × kDelta
///
/// Tratar os dois como se custassem o mesmo é o erro que faz uma estimativa
/// calibrada numa amostra de 12 quadros explodir numa conversão de 500: numa
/// cena parada o primeiro quadro é praticamente o arquivo inteiro, e ele é
/// diluído em 12 na amostra e em 500 no resultado. Num cartão de título
/// estático isso chega a errar por 8x.
///
/// `kChave` e `kDelta` dependem do quanto a cena é detalhada/agitada; as
/// configurações de codificação viram fatores multiplicativos calculados na
/// hora. A agitação vira o [ComplexityProfile], medido uma vez.
///
/// ## Condições de referência
///
/// Os fatores são todos 1.0 quando: 12 fps, 256 cores, dither equilibrado,
/// paleta única, velocidade 1x e imagem reduzida à metade da largura de
/// origem. Os dois `k` são sempre expressos nessas condições, para que o
/// mesmo valor medido sirva para qualquer combinação de controles.
class SizeEstimator {
  const SizeEstimator._();

  static const double _refFps = 12.0;
  static const int _refColors = 256;
  static const double _refScaleRatio = 0.5;

  /// Limites de sanidade para o custo dos quadros que vêm depois do primeiro.
  ///
  /// O piso é bem baixo de propósito. Um quadro que quase não muda custa só o
  /// cabeçalho do bloco mais um punhado de bytes de LZW — uns 30 bytes, que
  /// num quadro de 400×224 dão 0,0003 por pixel. O valor antigo (0,015) fazia
  /// sentido quando um `k` só carregava o primeiro quadro diluído entre
  /// todos; agora que os dois estão separados, um piso alto reintroduz
  /// exatamente o erro que a separação corrige, inflando cenas paradas.
  static const double _minBpp = 0.0002;
  static const double _maxBpp = 1.30;

  /// O primeiro quadro é uma imagem inteira, então custa bem mais por pixel
  /// que os seguintes — a faixa plausível é outra.
  static const double _minKeyBpp = 0.010;
  static const double _maxKeyBpp = 2.00;

  /// Cabeçalho do GIF, bloco de aplicação (loop) e tabela de cores.
  static int overheadBytes(int colors) => 800 + 3 * colors;

  /// Quantos pixels do canvas final são a borda da moldura (a área fora da
  /// "área de conteúdo" onde o vídeo aparece). É praticamente estática de um
  /// quadro para o outro — o FFmpeg (`diff_mode=rectangle`) só regrava o
  /// retângulo que mudou —, então NÃO deve ser multiplicada pelos fatores de
  /// movimento/configuração em [bpp]; só pesa uma vez, no quadro-chave (ver
  /// [estimate]).
  static int _frameBorderPixels(ConversionSettings settings, VideoInfo video) {
    if (settings.frame.style == FrameStyle.none) return 0;
    final (canvasWidth, canvasHeight) = settings.outputDimensions(video);
    final (areaWidth, areaHeight, _) = settings.frameAreaDimensions(video);
    final canvasPixels = canvasWidth * canvasHeight;
    final areaPixels = areaWidth * areaHeight;
    return (canvasPixels - areaPixels).clamp(0, canvasPixels);
  }

  // --------------------------------------------------------------------
  // Fatores de configuração
  // --------------------------------------------------------------------

  /// Mais quadros por segundo significa mais quadros, mas cada quadro fica
  /// mais parecido com o anterior — então o custo POR QUADRO cai. O expoente
  /// 0.30 modela essa economia parcial: dobrar o fps não dobra o arquivo,
  /// aumenta cerca de 60%.
  static double fpsFactor(int fps) =>
      math.pow(_refFps / math.max(fps, 1), 0.30).toDouble();

  /// Paletas menores comprimem melhor, porque há menos símbolos distintos
  /// para o LZW acompanhar.
  static double colorFactor(int colors) =>
      math.pow(colors.clamp(2, 256) / _refColors, 0.45).toDouble();

  /// Pontilhado é ruído: quanto mais, pior comprime.
  static double ditherFactor(DitherMode dither) => switch (dither) {
    DitherMode.none => 0.72,
    DitherMode.bayer3 => 0.88,
    DitherMode.bayer5 => 1.00,
    DitherMode.sierra => 1.45,
    DitherMode.floydSteinberg => 1.55,
  };

  /// Paleta por quadro impede reaproveitar a tabela de cores e cresce o
  /// arquivo; paleta focada no movimento economiza um pouco.
  static double paletteFactor(PaletteMode palette) => switch (palette) {
    PaletteMode.global => 1.00,
    PaletteMode.movement => 0.95,
    PaletteMode.perFrame => 1.30,
  };

  /// Acelerar o vídeo aumenta a diferença entre quadros vizinhos, o que
  /// encarece cada quadro. Câmera lenta faz o contrário.
  static double speedFactor(double speed) =>
      math.pow(speed.clamp(0.1, 10.0), 0.12).toDouble();

  /// Reduzir muito a imagem também suaviza detalhe e ruído, barateando cada
  /// pixel. Efeito real, porém fraco — daí o expoente pequeno.
  static double scaleFactor(double scaleRatio) =>
      math.pow(scaleRatio.clamp(0.05, 1.0) / _refScaleRatio, 0.12).toDouble();

  /// Produto de todos os fatores de configuração, para os quadros que vêm
  /// depois do primeiro.
  static double settingsFactor(ConversionSettings settings, VideoInfo video) {
    return fpsFactor(settings.fps) *
        colorFactor(settings.colors) *
        ditherFactor(settings.dither) *
        paletteFactor(settings.palette) *
        speedFactor(settings.speed) *
        scaleFactor(settings.scaleRatio(video));
  }

  /// Fatores que valem para o **primeiro** quadro.
  ///
  /// Fps e velocidade ficam de fora de propósito: o primeiro quadro é uma
  /// imagem parada, e uma imagem parada não fica mais barata porque o vídeo
  /// tem mais quadros por segundo. Só cor, dither, paleta e escala mexem
  /// nela.
  static double keySettingsFactor(
    ConversionSettings settings,
    VideoInfo video,
  ) {
    return colorFactor(settings.colors) *
        ditherFactor(settings.dither) *
        paletteFactor(settings.palette) *
        scaleFactor(settings.scaleRatio(video));
  }

  // --------------------------------------------------------------------
  // Estimativa
  // --------------------------------------------------------------------

  static SizeEstimate estimate({
    required ConversionSettings settings,
    required VideoInfo video,
    ComplexityProfile profile = ComplexityProfile.fallback,
  }) {
    final (width, height) = settings.outputDimensions(video);
    final frames = settings.frameCount;
    final pixels = width * height;
    final contentPixels = pixels - _frameBorderPixels(settings, video);

    final bpp = (profile.bytesPerPixel * settingsFactor(settings, video))
        .clamp(_minBpp, _maxBpp)
        .toDouble();
    final keyBpp =
        (profile.keyBytesPerPixel * keySettingsFactor(settings, video))
            .clamp(_minKeyBpp, _maxKeyBpp)
            .toDouble();

    // O quadro-chave é uma imagem inteira: paga por todos os pixels do
    // canvas, moldura incluída. Os quadros seguintes só pagam pela área de
    // conteúdo, que é a única parte que muda de um quadro para o outro.
    final payload = pixels * keyBpp + (frames - 1) * contentPixels * bpp;
    final total = overheadBytes(settings.colors) + payload;

    return SizeEstimate(
      bytes: total.round(),
      frames: frames,
      width: width,
      height: height,
      bytesPerPixel: bpp,
      confidence: profile.confidence,
      durationSeconds: settings.outputDurationSeconds,
    );
  }

  // --------------------------------------------------------------------
  // Calibração
  // --------------------------------------------------------------------

  /// Caminho inverso da estimativa: dados os tamanhos REAIS de uma amostra já
  /// codificada, descobre os dois `k` deste vídeo.
  ///
  /// Precisa de duas medidas da MESMA janela, feitas com a MESMA paleta:
  ///
  ///  - [firstFrameBytes] — o GIF cortado no primeiro quadro. Como o primeiro
  ///    quadro é sempre completo, esse arquivo é o cabeçalho + a paleta + o
  ///    custo do quadro cheio;
  ///  - [measuredBytes] — o GIF da janela inteira. A diferença entre os dois
  ///    é exatamente o que os quadros seguintes custaram.
  ///
  /// Sem essa segunda medida não dá para separar as duas coisas, e o custo do
  /// primeiro quadro acaba distribuído entre todos — que é o que fazia a
  /// previsão estourar em cenas paradas.
  ///
  /// [sampleSettings] tem que ser exatamente o que foi usado para gerar a
  /// amostra (mesmo fps, cores, dither, escala), variando só o trecho.
  static ComplexityProfile calibrate({
    required int measuredBytes,
    required int firstFrameBytes,
    required ConversionSettings sampleSettings,
    required VideoInfo video,
  }) {
    final (width, height) = sampleSettings.outputDimensions(video);
    final frames = sampleSettings.frameCount;
    final pixels = width * height;
    if (pixels <= 0 || frames < 2) return ComplexityProfile.fallback;

    final borderPixels = _frameBorderPixels(sampleSettings, video);
    final contentPixels = pixels - borderPixels <= 0
        ? pixels
        : pixels - borderPixels;

    final overhead = overheadBytes(sampleSettings.colors);
    final keyPayload = firstFrameBytes - overhead;
    final deltaPayload = measuredBytes - firstFrameBytes;
    if (keyPayload <= 0 || deltaPayload < 0) return ComplexityProfile.fallback;

    final keyBpp =
        keyPayload / pixels / keySettingsFactor(sampleSettings, video);
    final deltaBpp =
        deltaPayload /
        ((frames - 1) * contentPixels) /
        settingsFactor(sampleSettings, video);

    return ComplexityProfile(
      bytesPerPixel: deltaBpp.clamp(_minBpp, _maxBpp).toDouble(),
      keyBytesPerPixel: keyBpp.clamp(_minKeyBpp, _maxKeyBpp).toDouble(),
      confidence: EstimateConfidence.calibrated,
    );
  }

  /// Combina várias amostras. Damos peso extra à amostra mais pesada porque
  /// errar para cima incomoda menos do que prometer 3 MB e entregar 12 MB.
  static ComplexityProfile combineSamples(List<ComplexityProfile> samples) {
    if (samples.isEmpty) return ComplexityProfile.fallback;
    if (samples.length == 1) return samples.first;

    double mix(double Function(ComplexityProfile) pick) {
      final values = samples.map(pick).toList();
      final mean = values.reduce((a, b) => a + b) / values.length;
      final max = values.reduce(math.max);
      return 0.55 * mean + 0.45 * max;
    }

    return ComplexityProfile(
      bytesPerPixel: mix(
        (s) => s.bytesPerPixel,
      ).clamp(_minBpp, _maxBpp).toDouble(),
      keyBytesPerPixel: mix(
        (s) => s.keyBytesPerPixel,
      ).clamp(_minKeyBpp, _maxKeyBpp).toDouble(),
      confidence: EstimateConfidence.calibrated,
    );
  }

  /// Palpite melhor que a média genérica quando ainda não houve calibração:
  /// vídeos com bitrate alto por pixel costumam ter mais detalhe e movimento,
  /// e viram GIFs mais pesados.
  static ComplexityProfile profileFromSource(VideoInfo video) {
    final bpp = video.sourceBitsPerPixel;
    if (bpp <= 0) return ComplexityProfile.fallback;

    // ~0.1 bit/pixel/quadro é um vídeo bem comprimido e parado;
    // ~0.6 já é uma cena detalhada e agitada.
    final t = ((bpp - 0.08) / 0.55).clamp(0.0, 1.0).toDouble();
    final estimated = 0.085 + t * 0.24;

    // O primeiro quadro é uma imagem inteira: mesmo num vídeo parado ele
    // custa caro, e num detalhado custa mais ainda. A faixa é bem mais alta
    // que a dos quadros seguintes, e importa pouco em GIFs longos — ele é um
    // quadro entre centenas.
    final key = 0.12 + t * 0.33;

    return ComplexityProfile(
      bytesPerPixel: estimated.clamp(_minBpp, _maxBpp).toDouble(),
      keyBytesPerPixel: key.clamp(_minKeyBpp, _maxKeyBpp).toDouble(),
      confidence: EstimateConfidence.fromSource,
    );
  }

  // --------------------------------------------------------------------
  // Ajuste automático para caber num alvo
  // --------------------------------------------------------------------

  /// Reduz as configurações, na ordem que menos machuca a percepção, até o
  /// GIF caber em [targetBytes].
  ///
  /// A ordem é deliberada:
  ///  1. **fps** — de 30 para 15 quase ninguém percebe, e corta ~40%;
  ///  2. **largura** — o ganho é quadrático, mas a perda já é visível;
  ///  3. **cores** — 128 cores passam despercebidas em muitas cenas;
  ///  4. **dither** — último recurso, pois é o que mais suja gradientes.
  ///
  /// A duração nunca é mexida automaticamente: cortar o conteúdo é uma
  /// decisão do usuário, não do app.
  static ConversionSettings fitToTarget({
    required ConversionSettings settings,
    required VideoInfo video,
    required int targetBytes,
    ComplexityProfile profile = ComplexityProfile.fallback,
  }) {
    var current = settings;

    bool fits() =>
        estimate(settings: current, video: video, profile: profile).bytes <=
        targetBytes;

    if (fits()) return current;

    final fpsLadder = ConversionSettings.fpsOptions.reversed
        .where((f) => f < current.fps)
        .toList();
    final widthLadder = ConversionSettings.widthOptions.reversed
        .where((w) => w < current.targetWidth)
        .toList();
    final colorLadder = ConversionSettings.colorOptions.reversed
        .where((c) => c < current.colors)
        .toList();
    const ditherLadder = [
      DitherMode.bayer5,
      DitherMode.bayer3,
      DitherMode.none,
    ];

    // Alterna entre as alavancas para degradar de forma equilibrada, em vez
    // de destruir uma dimensão só.
    var fpsIndex = 0;
    var widthIndex = 0;
    var colorIndex = 0;
    var ditherIndex = 0;

    var madeProgress = true;
    while (!fits() && madeProgress) {
      madeProgress = false;

      if (fpsIndex < fpsLadder.length && current.fps > 8) {
        current = current.copyWith(fps: fpsLadder[fpsIndex++]);
        madeProgress = true;
        if (fits()) break;
      }

      if (widthIndex < widthLadder.length && current.targetWidth > 160) {
        current = current.copyWith(targetWidth: widthLadder[widthIndex++]);
        madeProgress = true;
        if (fits()) break;
      }

      if (colorIndex < colorLadder.length) {
        current = current.copyWith(colors: colorLadder[colorIndex++]);
        madeProgress = true;
        if (fits()) break;
      }

      if (ditherIndex < ditherLadder.length) {
        final candidate = ditherLadder[ditherIndex++];
        if (ditherFactor(candidate) < ditherFactor(current.dither)) {
          current = current.copyWith(dither: candidate);
          madeProgress = true;
        }
      }
    }

    return current;
  }

  /// Explica, em português, qual controle mais compensa mexer agora.
  static String suggestionFor({
    required ConversionSettings settings,
    required VideoInfo video,
    ComplexityProfile profile = ComplexityProfile.fallback,
  }) {
    final current = estimate(
      settings: settings,
      video: video,
      profile: profile,
    );

    if (current.verdict == SizeVerdict.light) {
      return 'Está leve. Se quiser, dá para subir a resolução ou o FPS sem '
          'estourar o peso.';
    }

    int bytesIf(ConversionSettings s) =>
        estimate(settings: s, video: video, profile: profile).bytes;

    final options = <String, int>{};

    if (settings.fps > 8) {
      final lower = ConversionSettings.fpsOptions.lastWhere(
        (f) => f < settings.fps,
        orElse: () => settings.fps,
      );
      if (lower < settings.fps) {
        options['baixar para $lower FPS'] = bytesIf(
          settings.copyWith(fps: lower),
        );
      }
    }

    if (settings.targetWidth > 160) {
      final lower = ConversionSettings.widthOptions.lastWhere(
        (w) => w < settings.targetWidth,
        orElse: () => settings.targetWidth,
      );
      if (lower < settings.targetWidth) {
        options['reduzir a largura para $lower px'] = bytesIf(
          settings.copyWith(targetWidth: lower),
        );
      }
    }

    if (settings.sourceDurationSeconds > 3) {
      final shorter = settings.copyWith(
        endSeconds:
            settings.startSeconds + settings.sourceDurationSeconds * 0.7,
      );
      options['cortar 30% da duração'] = bytesIf(shorter);
    }

    if (settings.colors > 64) {
      options['usar 128 cores'] = bytesIf(settings.copyWith(colors: 128));
    }

    if (options.isEmpty) return current.verdict.advice;

    final best = options.entries.reduce((a, b) => a.value < b.value ? a : b);
    final saved = current.bytes - best.value;
    if (saved <= 0) return current.verdict.advice;

    final percent = (saved / current.bytes * 100).round();
    return 'Dica: $percent% mais leve se ${best.key} '
        '(${SizeEstimate.formatBytes(best.value)}).';
  }
}
