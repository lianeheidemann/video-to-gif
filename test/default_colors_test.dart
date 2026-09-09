import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_background.dart';
import 'package:video_to_gif/models/collage_cell.dart';
import 'package:video_to_gif/models/collage_layout.dart';
import 'package:video_to_gif/models/collage_settings.dart';
import 'package:video_to_gif/models/default_colors.dart';
import 'package:video_to_gif/models/frame_settings.dart';

/// O que estes testes seguram é a promessa de que as duas cores padrão são as
/// *mesmas* nas três telas de edição. Sem isso, uma delas volta a ser branco
/// ou preto num modelo só e a diferença só aparece no aparelho.
void main() {
  test('fundo e moldura do vídeo/moldura em foto usam as cores padrão', () {
    const frame = FrameSettings();
    expect(frame.color, defaultFrameColor);
    expect(frame.backgroundColor, defaultBackgroundColor);
  });

  test('borda e fundo da montagem usam as mesmas cores', () {
    const settings = CollageSettings(
      layout: CollageLayout(kind: CollageLayoutKind.grid2x2),
    );
    expect(settings.borderColor, defaultFrameColor);
    expect(settings.background.color, defaultBackgroundColor);
  });

  test('a borda e o fundo de cada foto da montagem também', () {
    const cell = CollageCellSettings();
    expect(cell.borderColor, defaultFrameColor);
    expect(cell.background.color, defaultBackgroundColor);
  });

  test('a cor não liga nada sozinha: fundo continua transparente', () {
    expect(const FrameSettings().transparentBackground, isTrue);
    expect(const CollageBackground().mode, CollageBackgroundMode.transparent);
  });
}
