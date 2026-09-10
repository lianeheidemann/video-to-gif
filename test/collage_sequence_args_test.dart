import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/services/ffmpeg_service.dart';

// `collageSequenceArgs` é uma função pura (não toca o FFmpeg de verdade),
// então dá para conferir a linha de comando da montagem animada sem rodar
// nenhuma exportação — mesma abordagem de `ffmpeg_service_webp_args_test`.

void main() {
  final service = FfmpegService();

  List<String> args({required bool webp}) => service.collageSequenceArgs(
    framePattern: '/tmp/quadros/quadro_%05d.png',
    fps: 12,
    outputPath: '/tmp/montagem.${webp ? 'webp' : 'gif'}',
    webp: webp,
  );

  test('entra como sequência de PNGs no FPS calculado', () {
    for (final webp in [false, true]) {
      final list = args(webp: webp);
      expect(list.first, '-y');
      final framerate = list.indexOf('-framerate');
      expect(framerate, greaterThan(0));
      expect(list[framerate + 1], '12');
      final input = list.indexOf('-i');
      expect(list[input + 1], '/tmp/quadros/quadro_%05d.png');
      expect(list.last, '/tmp/montagem.${webp ? 'webp' : 'gif'}');
    }
  });

  test('GIF usa paleta em dois passes com transparência reservada', () {
    final list = args(webp: false);
    final graph = list[list.indexOf('-filter_complex') + 1];
    expect(graph, contains('palettegen'));
    expect(graph, contains('reserve_transparent=1'));
    expect(graph, contains('paletteuse'));
    expect(graph, contains('alpha_threshold=128'));
    // Difusão de erro em vez do quadriculado do bayer — ver o comentário em
    // collageSequenceArgs.
    expect(graph, contains('dither=sierra2_4a'));
    expect(list, containsAllInOrder(['-gifflags', '-transdiff']));
    expect(list, containsAllInOrder(['-loop', '0']));
    expect(list, isNot(contains('libwebp')));
  });

  test('WebP vai direto no libwebp, com alfa de verdade e sem paleta', () {
    final list = args(webp: true);
    expect(list, containsAllInOrder(['-c:v', 'libwebp']));
    expect(list, containsAllInOrder(['-pix_fmt', 'yuva420p']));
    expect(list, containsAllInOrder(['-quality', '92']));
    // -compression_level 2 (não 6): essa opção não muda qualidade visual,
    // só troca tempo de CPU por tamanho — 6 só deixava a montagem final do
    // contêiner WebP mais lenta sem ganho nenhum (ver comentário em
    // collageSequenceArgs).
    expect(list, containsAllInOrder(['-compression_level', '2']));
    expect(list, containsAllInOrder(['-loop', '0']));
    expect(list.join(' '), isNot(contains('palettegen')));
    expect(list.join(' '), isNot(contains('paletteuse')));
    expect(list.join(' '), isNot(contains('gifflags')));
  });

  test('sem repetição, o laço é desligado nos dois formatos', () {
    final gif = service.collageSequenceArgs(
      framePattern: '/tmp/q_%05d.png',
      fps: 10,
      outputPath: '/tmp/a.gif',
      webp: false,
      loop: false,
    );
    expect(gif[gif.indexOf('-loop') + 1], '-1');

    final webp = service.collageSequenceArgs(
      framePattern: '/tmp/q_%05d.png',
      fps: 10,
      outputPath: '/tmp/a.webp',
      webp: true,
      loop: false,
    );
    expect(webp[webp.indexOf('-loop') + 1], '1');
  });
}
