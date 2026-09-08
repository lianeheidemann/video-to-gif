import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/size_estimate.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/services/size_estimator.dart';

const _video = VideoInfo(
  path: '/tmp/exemplo.mp4',
  fileName: 'exemplo.mp4',
  rawWidth: 1920,
  rawHeight: 1080,
  durationSeconds: 30,
  frameRate: 30,
  bitrateBps: 8000000,
  fileSizeBytes: 30000000,
  codec: 'h264',
);

const _base = ConversionSettings(
  startSeconds: 2,
  endSeconds: 8,
  targetWidth: 480,
);

/// Atalho para pegar só os bytes estimados de uma combinação de
/// configurações (e, opcionalmente, um perfil já calibrado).
int _bytes(ConversionSettings settings, {ComplexityProfile? profile}) =>
    SizeEstimator.estimate(
      settings: settings,
      video: _video,
      profile: profile ?? ComplexityProfile.fallback,
    ).bytes;

/// Monta um perfil de complexidade "calibrado" fictício para os testes,
/// com o custo do primeiro quadro por padrão 1,8x o dos demais.
ComplexityProfile _profile(double bpp, {double? key}) => ComplexityProfile(
  bytesPerPixel: bpp,
  keyBytesPerPixel: key ?? bpp * 1.8,
  confidence: EstimateConfidence.calibrated,
);

/// O par de medidas que uma amostra real produziria com este perfil:
/// o GIF da janela inteira e o mesmo GIF cortado no primeiro quadro.
(int, int) _sampleBytes(
  ConversionSettings settings, {
  required ComplexityProfile profile,
}) {
  final (w, h) = settings.outputDimensions(_video);
  final pixels = w * h;
  final overhead = SizeEstimator.overheadBytes(settings.colors);
  final key =
      pixels *
      profile.keyBytesPerPixel *
      SizeEstimator.keySettingsFactor(settings, _video);
  final delta =
      (settings.frameCount - 1) *
      pixels *
      profile.bytesPerPixel *
      SizeEstimator.settingsFactor(settings, _video);
  return ((overhead + key + delta).round(), (overhead + key).round());
}

void main() {
  group('dimensões de saída', () {
    test('nunca amplia o vídeo além da origem', () {
      const settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        targetWidth: 4000,
      );
      final (w, h) = settings.outputDimensions(_video);
      expect(w, 1920);
      expect(h, 1080);
    });

    test('sempre devolve números pares', () {
      for (final width in [161, 321, 483, 719]) {
        final settings = _base.copyWith(targetWidth: width);
        final (w, h) = settings.outputDimensions(_video);
        expect(w.isEven, isTrue, reason: 'largura $w para alvo $width');
        expect(h.isEven, isTrue, reason: 'altura $h para alvo $width');
      }
    });

    test('respeita a proporção do recorte, não a do vídeo', () {
      final settings = _base.copyWith(
        crop: CropRect.centeredIn(_video.width, _video.height, 1.0),
        targetWidth: 400,
      );
      final (w, h) = settings.outputDimensions(_video);
      expect(w, h);
    });

    test('leva em conta a rotação do vídeo', () {
      const rotated = VideoInfo(
        path: '/tmp/vertical.mp4',
        fileName: 'vertical.mp4',
        rawWidth: 1920,
        rawHeight: 1080,
        durationSeconds: 10,
        frameRate: 30,
        bitrateBps: 8000000,
        fileSizeBytes: 10000000,
        codec: 'h264',
        rotationDegrees: 90,
      );
      expect(rotated.width, 1080);
      expect(rotated.height, 1920);
      expect(rotated.isPortrait, isTrue);
    });
  });

  group('contagem de quadros', () {
    test('acelerar o vídeo encurta o GIF', () {
      expect(_base.outputDurationSeconds, 6);
      expect(_base.copyWith(speed: 2.0).outputDurationSeconds, 3);
      expect(_base.copyWith(speed: 0.5).outputDurationSeconds, 12);
    });

    test('quadros seguem duração final x fps', () {
      expect(_base.copyWith(fps: 10).frameCount, 60);
      expect(_base.copyWith(fps: 10, speed: 2.0).frameCount, 30);
    });

    test('nunca fica abaixo de um quadro', () {
      const tiny = ConversionSettings(startSeconds: 1, endSeconds: 1, fps: 5);
      expect(tiny.frameCount, 1);
    });
  });

  group('monotonicidade da estimativa', () {
    test('mais FPS pesa mais', () {
      expect(
        _bytes(_base.copyWith(fps: 20)),
        greaterThan(_bytes(_base.copyWith(fps: 10))),
      );
    });

    test('mas dobrar o FPS custa menos que dobrar o arquivo', () {
      // Redundância entre quadros vizinhos: o crescimento é sublinear.
      final low = _bytes(_base.copyWith(fps: 10));
      final high = _bytes(_base.copyWith(fps: 20));
      expect(high, lessThan(low * 2));
      expect(high, greaterThan((low * 1.3).round()));
    });

    test('mais largura pesa mais', () {
      expect(
        _bytes(_base.copyWith(targetWidth: 640)),
        greaterThan(_bytes(_base.copyWith(targetWidth: 320))),
      );
    });

    test('mais duração pesa mais', () {
      expect(
        _bytes(_base.copyWith(endSeconds: 12)),
        greaterThan(_bytes(_base)),
      );
    });

    test('mais cores pesa mais', () {
      expect(
        _bytes(_base.copyWith(colors: 256)),
        greaterThan(_bytes(_base.copyWith(colors: 64))),
      );
    });

    test('mais pontilhado pesa mais', () {
      expect(
        _bytes(_base.copyWith(dither: DitherMode.floydSteinberg)),
        greaterThan(_bytes(_base.copyWith(dither: DitherMode.none))),
      );
    });

    test('paleta por quadro pesa mais que paleta única', () {
      expect(
        _bytes(_base.copyWith(palette: PaletteMode.perFrame)),
        greaterThan(_bytes(_base.copyWith(palette: PaletteMode.global))),
      );
    });

    test('acelerar reduz o peso porque o GIF fica mais curto', () {
      expect(_bytes(_base.copyWith(speed: 2.0)), lessThan(_bytes(_base)));
    });
  });

  group('calibração', () {
    test('volta ao perfil original (ida e volta)', () {
      final profile = _profile(0.21, key: 0.40);
      final sample = _base.copyWith(startSeconds: 3, endSeconds: 4);

      final (measured, firstFrame) = _sampleBytes(sample, profile: profile);
      final recovered = SizeEstimator.calibrate(
        measuredBytes: measured,
        firstFrameBytes: firstFrame,
        sampleSettings: sample,
        video: _video,
      );

      expect(recovered.bytesPerPixel, closeTo(profile.bytesPerPixel, 0.005));
      expect(
        recovered.keyBytesPerPixel,
        closeTo(profile.keyBytesPerPixel, 0.005),
      );
      expect(recovered.confidence, EstimateConfidence.calibrated);
    });

    test('perfil medido com um ajuste vale para outros ajustes', () {
      // Calibramos com uma amostra a 12 fps / 480 px e usamos o resultado
      // para prever um GIF a 20 fps / 320 px. O perfil é independente das
      // configurações, então a previsão tem que bater.
      final truth = _profile(0.19, key: 0.36);
      final sample = _base.copyWith(startSeconds: 3, endSeconds: 4);
      final (measured, firstFrame) = _sampleBytes(sample, profile: truth);

      final recovered = SizeEstimator.calibrate(
        measuredBytes: measured,
        firstFrameBytes: firstFrame,
        sampleSettings: sample,
        video: _video,
      );

      final different = _base.copyWith(fps: 20, targetWidth: 320, colors: 128);
      final predicted = _bytes(different, profile: recovered);
      final actual = _bytes(different, profile: truth);

      expect((predicted - actual).abs() / actual, lessThan(0.05));
    });

    test('uma amostra curta não infla a previsão de um GIF longo', () {
      // O caso que motivou separar o primeiro quadro: cena praticamente
      // parada, em que o quadro inicial é quase o arquivo inteiro. Medindo
      // 1 segundo e prevendo 40, a conta não pode multiplicar esse custo.
      final parada = _profile(0.004, key: 0.35);
      final amostra = _base.copyWith(startSeconds: 3, endSeconds: 4);
      final longo = _base.copyWith(startSeconds: 0, endSeconds: 40);

      final (measured, firstFrame) = _sampleBytes(amostra, profile: parada);
      final recovered = SizeEstimator.calibrate(
        measuredBytes: measured,
        firstFrameBytes: firstFrame,
        sampleSettings: amostra,
        video: _video,
      );

      final previsto = _bytes(longo, profile: recovered);
      final real = _bytes(longo, profile: parada);
      expect((previsto - real).abs() / real, lessThan(0.05));
    });

    test('medida absurda não quebra o modelo', () {
      final sample = _base.copyWith(startSeconds: 3, endSeconds: 4);
      final tooSmall = SizeEstimator.calibrate(
        measuredBytes: 10,
        firstFrameBytes: 5,
        sampleSettings: sample,
        video: _video,
      );
      expect(tooSmall.bytesPerPixel, ComplexityProfile.fallback.bytesPerPixel);

      final tooBig = SizeEstimator.calibrate(
        measuredBytes: 900000000,
        firstFrameBytes: 400000000,
        sampleSettings: sample,
        video: _video,
      );
      expect(tooBig.bytesPerPixel, lessThanOrEqualTo(1.30));
      expect(tooBig.keyBytesPerPixel, lessThanOrEqualTo(2.00));

      // O GIF da janela inteira nunca pode ser menor que o do primeiro
      // quadro; se vier assim, a medição não serve.
      final invertido = SizeEstimator.calibrate(
        measuredBytes: 5000,
        firstFrameBytes: 9000,
        sampleSettings: sample,
        video: _video,
      );
      expect(invertido.bytesPerPixel, ComplexityProfile.fallback.bytesPerPixel);
    });

    test('combinar amostras puxa para a mais pesada', () {
      final combined = SizeEstimator.combineSamples([
        _profile(0.10, key: 0.20),
        _profile(0.30, key: 0.60),
      ]);
      expect(combined.bytesPerPixel, greaterThan(0.20));
      expect(combined.bytesPerPixel, lessThan(0.30));
      expect(combined.keyBytesPerPixel, greaterThan(0.40));
      expect(combined.keyBytesPerPixel, lessThan(0.60));
    });
  });

  group('ajuste automático para um alvo', () {
    test('chega abaixo do alvo quando é possível', () {
      const target = 3 * 1024 * 1024;
      final heavy = _base.copyWith(endSeconds: 20, fps: 30, targetWidth: 720);
      expect(_bytes(heavy), greaterThan(target));

      final fitted = SizeEstimator.fitToTarget(
        settings: heavy,
        video: _video,
        targetBytes: target,
      );
      expect(_bytes(fitted), lessThanOrEqualTo(target));
    });

    test('não mexe em nada se já couber', () {
      final light = _base.copyWith(endSeconds: 3, fps: 8, targetWidth: 240);
      final fitted = SizeEstimator.fitToTarget(
        settings: light,
        video: _video,
        targetBytes: 50 * 1024 * 1024,
      );
      expect(fitted.fps, light.fps);
      expect(fitted.targetWidth, light.targetWidth);
    });

    test('nunca altera o trecho escolhido pelo usuário', () {
      final fitted = SizeEstimator.fitToTarget(
        settings: _base.copyWith(endSeconds: 25, fps: 30, targetWidth: 1080),
        video: _video,
        targetBytes: 512 * 1024,
      );
      expect(fitted.startSeconds, 2);
      expect(fitted.endSeconds, 25);
    });

    test('termina mesmo com um alvo impossível', () {
      final fitted = SizeEstimator.fitToTarget(
        settings: _base.copyWith(endSeconds: 30, fps: 30, targetWidth: 1080),
        video: _video,
        targetBytes: 1,
      );
      expect(fitted.fps, lessThanOrEqualTo(_base.fps));
    });
  });

  group('classificação e formatação', () {
    test('separa as faixas de peso', () {
      expect(SizeVerdict.forBytes(15 * 1024 * 1024), SizeVerdict.light);
      expect(SizeVerdict.forBytes(20 * 1024 * 1024), SizeVerdict.good);
      expect(SizeVerdict.forBytes(25 * 1024 * 1024), SizeVerdict.heavy);
      expect(SizeVerdict.forBytes(50 * 1024 * 1024), SizeVerdict.tooHeavy);
    });

    test('a faixa é mais estreita quando houve calibração', () {
      final rough = SizeEstimator.estimate(settings: _base, video: _video);
      final calibrated = SizeEstimator.estimate(
        settings: _base,
        video: _video,
        profile: _profile(0.16),
      );

      final roughSpread = rough.highBytes - rough.lowBytes;
      final calibratedSpread = calibrated.highBytes - calibrated.lowBytes;
      expect(calibratedSpread, lessThan(roughSpread));
    });

    test('formata bytes de forma legível', () {
      expect(SizeEstimate.formatBytes(512), '512 B');
      expect(SizeEstimate.formatBytes(2048), '2 KB');
      expect(SizeEstimate.formatBytes(3 * 1024 * 1024), '3.0 MB');
      expect(SizeEstimate.formatBytes(25 * 1024 * 1024), '25 MB');
    });

    test('sugere o controle mais eficaz', () {
      final heavy = _base.copyWith(endSeconds: 25, fps: 30, targetWidth: 720);
      final suggestion = SizeEstimator.suggestionFor(
        settings: heavy,
        video: _video,
      );
      expect(suggestion, contains('mais leve'));
    });
  });

  group('perfil a partir do arquivo de origem', () {
    test('bitrate alto por pixel indica cena mais complexa', () {
      const busy = VideoInfo(
        path: '/tmp/a.mp4',
        fileName: 'a.mp4',
        rawWidth: 1280,
        rawHeight: 720,
        durationSeconds: 10,
        frameRate: 30,
        bitrateBps: 12000000,
        fileSizeBytes: 15000000,
        codec: 'h264',
      );
      const calm = VideoInfo(
        path: '/tmp/b.mp4',
        fileName: 'b.mp4',
        rawWidth: 1280,
        rawHeight: 720,
        durationSeconds: 10,
        frameRate: 30,
        bitrateBps: 900000,
        fileSizeBytes: 1200000,
        codec: 'h264',
      );

      expect(
        SizeEstimator.profileFromSource(busy).bytesPerPixel,
        greaterThan(SizeEstimator.profileFromSource(calm).bytesPerPixel),
      );
    });

    test('sem bitrate conhecido cai no valor padrão', () {
      const unknown = VideoInfo(
        path: '/tmp/c.mp4',
        fileName: 'c.mp4',
        rawWidth: 640,
        rawHeight: 480,
        durationSeconds: 5,
        frameRate: 24,
        bitrateBps: 0,
        fileSizeBytes: 0,
        codec: 'h264',
      );
      expect(
        SizeEstimator.profileFromSource(unknown).bytesPerPixel,
        ComplexityProfile.fallback.bytesPerPixel,
      );
    });
  });
}
