import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/color_adjustments.dart';
import 'package:video_to_gif/services/ffmpeg_service.dart';

void main() {
  final service = FfmpegService();

  test('sem ajuste nenhum, nenhum filtro entra na cadeia', () {
    expect(service.colorAdjustFilters(ColorAdjustments.neutral), isEmpty);
  });

  test('brilho e contraste viram um "eq" só', () {
    final filters = service.colorAdjustFilters(
      const ColorAdjustments(brightness: 0.5, contrast: 0.2),
    );
    expect(filters, hasLength(1));
    expect(filters.single, startsWith('eq='));
    expect(filters.single, contains('contrast=1.2000'));
    // Nada de mistura de canais: brilho e contraste tratam os três igual.
    expect(filters.single, isNot(contains('colorchannelmixer')));
  });

  test('"eq" reproduz o ganho e o deslocamento das matrizes', () {
    const adjustments = ColorAdjustments(brightness: 0.4, contrast: 0.3);
    final (gain, shift) = adjustments.toneTransfer;
    final filter = service.colorAdjustFilters(adjustments).single;

    // eq faz (entrada - 0.5) * contrast + 0.5 + brightness, então o
    // deslocamento pedido tem que sair de brightness - 0.5 + 0.5 * ganho.
    final contrast = double.parse(
      RegExp(r'contrast=([-\d.]+)').firstMatch(filter)!.group(1)!,
    );
    final brightness = double.parse(
      RegExp(r'brightness=([-\d.]+)').firstMatch(filter)!.group(1)!,
    );
    expect(contrast, closeTo(gain, 0.001));
    expect(brightness + 0.5 - 0.5 * gain, closeTo(shift / 255, 0.001));
  });

  test('saturação vira colorchannelmixer, não eq', () {
    final filters = service.colorAdjustFilters(
      const ColorAdjustments(saturation: -1),
    );
    expect(filters, hasLength(1));
    expect(filters.single, startsWith('colorchannelmixer='));
    // Saturação -1 é preto e branco: cada canal vira a luma da imagem, então
    // os três coeficientes de uma linha batem com os pesos de luma.
    expect(filters.single, contains('rr=0.2126'));
    expect(filters.single, contains('rg=0.7152'));
    expect(filters.single, contains('rb=0.0722'));
  });

  test('ajustes dos dois tipos entram na ordem da prévia', () {
    final filters = service.colorAdjustFilters(
      const ColorAdjustments(brightness: 0.2, saturation: 0.5),
    );
    expect(filters, hasLength(2));
    expect(filters.first, startsWith('eq='));
    expect(filters.last, startsWith('colorchannelmixer='));
  });
}
