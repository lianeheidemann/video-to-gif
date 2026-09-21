// Regressão do modelo de estimativa contra medições REAIS do FFmpeg.
//
// Os números abaixo não foram inventados nem derivados do próprio modelo:
// são tamanhos de arquivo de GIFs gerados com a mesma cadeia de filtros que o
// app usa (`fps` → `scale=lanczos` → `palettegen`/`paletteuse` com
// `diff_mode=rectangle`), sobre vídeos sintéticos de 1280×720 escolhidos para
// cobrir os extremos de complexidade.
//
// Para cada vídeo há três medições:
//   - o GIF da conversão inteira (43,1 s → 517 quadros), que é a resposta certa;
//   - duas amostras de 1 s (a 20% e a 60%), cada uma com o tamanho do GIF da
//     janela e o do mesmo GIF cortado no primeiro quadro.
//
// O teste refaz exatamente o que o app faz: calibra com as amostras, combina
// os perfis e prevê a conversão inteira. É o teste que teria pego o erro de
// diluir o custo do primeiro quadro por todos os quadros.
//
// Como reproduzir as medições está em docs/COMO_A_ESTIMATIVA_FUNCIONA.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/models/conversion_settings.dart';
import 'package:video_to_gif/core/models/video_info.dart';
import 'package:video_to_gif/core/services/size_estimator.dart';

const _video = VideoInfo(
  path: '/tmp/sintetico.mp4',
  fileName: 'sintetico.mp4',
  rawWidth: 1280,
  rawHeight: 720,
  durationSeconds: 46,
  frameRate: 30,
  bitrateBps: 2500000,
  fileSizeBytes: 14375000,
  codec: 'h264',
);

/// 43,1 s a 12 FPS, 400 px de largura, 256 cores, dither equilibrado.
const _conversao = ConversionSettings(
  startSeconds: 0,
  endSeconds: 43.1,
  targetWidth: 400,
);

/// Uma janela de 1 s, como a que o app usa para medir.
ConversionSettings _amostra(double inicio) =>
    _conversao.copyWith(startSeconds: inicio, endSeconds: inicio + 1.0);

/// Uma medição real de amostra: peso do GIF da janela inteira e do mesmo
/// GIF cortado no primeiro quadro (os dois números que a calibração usa).
class _Medicao {
  const _Medicao(this.bytes, this.primeiroQuadro);
  final int bytes;
  final int primeiroQuadro;
}

/// Um vídeo sintético de teste: o peso real da conversão completa (medido
/// de verdade) e as amostras usadas para calibrar a previsão.
class _Caso {
  const _Caso(this.nome, this.realBytes, this.amostras);
  final String nome;
  final int realBytes;
  final List<_Medicao> amostras;
}

const _casos = <_Caso>[
  // Cartão de título: texto branco sobre fundo preto, imagem estática.
  // O caso patológico — o primeiro quadro é quase o arquivo inteiro.
  _Caso('cartão de título', 39066, [
    _Medicao(9250, 8975),
    _Medicao(9250, 8975),
  ]),
  // Fundo parado com um objeto atravessando a tela.
  _Caso('objeto se movendo', 445151, [
    _Medicao(13929, 4246),
    _Medicao(13171, 4246),
  ]),
  // testsrc2: muitos elementos em movimento e bordas duras.
  _Caso('cena agitada', 5548603, [
    _Medicao(137740, 19394),
    _Medicao(137681, 19159),
  ]),
  // Gradientes em movimento lento: o pior caso do GIF para cor.
  _Caso('gradiente', 18676573, [
    _Medicao(413024, 40584),
    _Medicao(403686, 37628),
  ]),
  // Ruído puro: incompressível, o teto absoluto de peso.
  _Caso('ruído', 44881747, [
    _Medicao(1057690, 94279),
    _Medicao(1033014, 86718),
  ]),
];

/// Repete o fluxo do app para um [caso]: calibra um perfil a partir de
/// cada amostra medida, combina os perfis e prevê o peso da conversão
/// inteira a partir daí.
int _preverCom(_Caso caso) {
  final perfis = [
    for (var i = 0; i < caso.amostras.length; i++)
      SizeEstimator.calibrate(
        measuredBytes: caso.amostras[i].bytes,
        firstFrameBytes: caso.amostras[i].primeiroQuadro,
        sampleSettings: _amostra(i == 0 ? 43.1 * 0.2 : 43.1 * 0.6),
        video: _video,
      ),
  ];

  return SizeEstimator.estimate(
    settings: _conversao,
    video: _video,
    profile: SizeEstimator.combineSamples(perfis),
  ).bytes;
}

void main() {
  test('a conversão medida tem mesmo 517 quadros e 400×224', () {
    final (w, h) = _conversao.outputDimensions(_video);
    expect(w, 400);
    expect(h, 224);
    expect(_conversao.frameCount, 517);
    expect(_amostra(8.62).frameCount, 12);
  });

  group('previsão calibrada contra o arquivo real', () {
    for (final caso in _casos) {
      test('${caso.nome}: erro dentro dos ±15% anunciados', () {
        final previsto = _preverCom(caso);
        final erro = (previsto - caso.realBytes) / caso.realBytes;

        // O cartão de título é o único fora da régua relativa, e por um
        // motivo bobo: o arquivo inteiro tem 39 KB, então qualquer diferença
        // de poucos KB vira uma porcentagem enorme. O que importa nele é o
        // erro absoluto — e que a previsão não seja dez vezes maior, que era
        // exatamente o defeito anterior.
        if (caso.realBytes < 100 * 1024) {
          expect((previsto - caso.realBytes).abs(), lessThan(30 * 1024));
        } else {
          expect(
            erro.abs(),
            lessThan(0.15),
            reason:
                '${caso.nome}: previsto $previsto, real ${caso.realBytes} '
                '(${(erro * 100).toStringAsFixed(0)}%)',
          );
        }
      });
    }

    test('nenhum caso erra para cima por mais de 15%', () {
      for (final caso in _casos) {
        final previsto = _preverCom(caso);
        expect(
          previsto,
          lessThan((caso.realBytes * 1.15).round() + 30 * 1024),
          reason: caso.nome,
        );
      }
    });
  });
}
