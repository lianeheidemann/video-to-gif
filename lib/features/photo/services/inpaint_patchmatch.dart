/// Preenchimento de buracos por síntese de textura (inpainting), no esquema
/// PatchMatch multi-escala — o mesmo tipo de algoritmo por trás de um
/// "preenchimento sensível ao conteúdo". É o motor da borracha mágica de
/// "Editar imagem".
///
/// Dart puro de propósito: **nada de `package:flutter`** aqui. Isso permite
/// (a) rodar num `Isolate` comum, sem token de engine, e (b) testar o
/// algoritmo inteiro com arranjos sintéticos, sem aparelho e sem binding.
///
/// A ideia, em três parágrafos:
///
/// 1. **Pirâmide.** A imagem é reduzida pela metade várias vezes, até o
///    buraco ficar do tamanho de uns poucos patches. Lá em cima o buraco é
///    semeado por difusão (média dos vizinhos conhecidos, de fora para
///    dentro) — não para acertar, só para não começar do ruído.
/// 2. **Busca (PatchMatch).** Em cada nível, para cada pixel da região-alvo
///    procura-se o patch mais parecido que esteja inteiramente fora do
///    buraco, alternando propagação (herdar o deslocamento do vizinho) com
///    busca aleatória em janela que cai pela metade. É o que torna a busca
///    viável: sem isso seria força bruta.
/// 3. **Votação.** Cada patch encontrado "vota" suas cores nos pixels que
///    cobre, com peso por similaridade. A média ponderada dos votos vira a
///    nova cor do buraco. O peso é o detalhe que mais importa: com média
///    simples o resultado borra (é o artefato clássico de smear).
///
/// Os pixels conhecidos são reimpostos ao fim de toda iteração — o buraco
/// muda, o resto da imagem nunca.
///
/// Esta função trabalha na imagem **inteira** que recebe: quem chama é que
/// decide recortar uma janela em volta do buraco e reduzi-la (ver
/// `magic_eraser.dart`). Manter a limitação de escopo fora daqui deixa o
/// algoritmo simples e o teste honesto.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Tamanho do patch (lado, em pixels). Ímpar, para ter centro.
const _defaultPatchSize = 7;

/// Quantas iterações de votação cada nível recebe. O nível mais grosso leva
/// mais porque é ele que decide a estrutura; os finos herdam uma NNF já boa
/// do nível anterior e só precisam refinar — gastar mais ali seria pagar o
/// pixel mais caro por quase nada.
const _coarseIterations = 6;
const _middleIterations = 3;
const _fineIterations = 2;

/// Passadas de PatchMatch (propagação + busca aleatória) por iteração.
const _searchPasses = 2;

/// Teto de níveis da pirâmide, só como trava de segurança.
const _maxLevels = 8;

/// Preenche a região marcada de [rgba] com textura sintetizada do resto da
/// imagem.
///
/// [rgba] tem `width * height * 4` bytes (RGBA, como sai de
/// `ui.Image.toByteData`). [mask] tem `width * height` bytes: qualquer valor
/// diferente de zero marca um pixel a apagar.
///
/// Devolve um RGBA novo, do mesmo tamanho. O canal alfa e todos os pixels
/// fora da máscara vêm intactos do original.
///
/// [seed] muda o resultado: é o que dá sentido ao botão "Tentar de novo".
/// [onProgress] recebe valores de 0 a 1. [isCancelled], quando devolve
/// `true`, interrompe e a função devolve o melhor resultado até ali.
Uint8List inpaintPatchMatch({
  required Uint8List rgba,
  required Uint8List mask,
  required int width,
  required int height,
  int patchSize = _defaultPatchSize,
  int seed = 0,
  void Function(double progress)? onProgress,
  bool Function()? isCancelled,
}) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Dimensões inválidas: ${width}x$height.');
  }
  if (rgba.length != width * height * 4) {
    throw ArgumentError(
      'rgba deveria ter ${width * height * 4} bytes, tem ${rgba.length}.',
    );
  }
  if (mask.length != width * height) {
    throw ArgumentError(
      'mask deveria ter ${width * height} bytes, tem ${mask.length}.',
    );
  }
  if (patchSize < 3 || patchSize.isEven) {
    throw ArgumentError('patchSize precisa ser ímpar e >= 3: $patchSize.');
  }

  final out = Uint8List.fromList(rgba);

  final levels = _buildPyramid(rgba, mask, width, height, patchSize);
  // Sem buraco nenhum, ou sem textura conhecida de onde copiar: devolve a
  // imagem como veio, em vez de inventar.
  if (levels.isEmpty) return out;

  final totalIterations = levels.fold<int>(
    0,
    (sum, level) => sum + _iterationsFor(level.index, levels.length),
  );
  var doneIterations = 0;

  // Da base da pirâmide (mais grossa) para o topo (resolução original).
  _Level? previous;
  for (var i = levels.length - 1; i >= 0; i--) {
    final level = levels[i];

    if (previous == null) {
      _seedByDiffusion(level);
      _initialiseNnfRandomly(level, seed);
    } else {
      _upscaleInto(previous, level);
      _upscaleNnf(previous, level);
    }

    final iterations = _iterationsFor(level.index, levels.length);
    for (var it = 0; it < iterations; it++) {
      if (isCancelled?.call() ?? false) {
        _writeBack(levels.first, out);
        return out;
      }
      for (var pass = 0; pass < _searchPasses; pass++) {
        _searchPass(level, seed + it * 31 + pass * 7, reverse: pass.isOdd);
      }
      _vote(level);
      doneIterations++;
      onProgress?.call(doneIterations / totalIterations);
    }

    previous = level;
  }

  _writeBack(levels.first, out);
  return out;
}

int _iterationsFor(int index, int levelCount) {
  if (index == levelCount - 1) return _coarseIterations;
  if (index == 0) return _fineIterations;
  return _middleIterations;
}

// ---------------------------------------------------------------------------
// Um nível da pirâmide
// ---------------------------------------------------------------------------

/// Tudo o que um nível precisa, em arranjos planos. Nada de `List<List<>>`:
/// o laço interno da busca roda dezenas de milhões de vezes, e indexação
/// aninhada ali dentro custa caro.
class _Level {
  _Level({
    required this.index,
    required this.width,
    required this.height,
    required this.rgb,
    required this.mask,
    required this.patchSize,
  }) : half = patchSize ~/ 2,
       nnf = Int32List(width * height),
       cost = Float64List(width * height);

  /// 0 é a resolução original; quanto maior, mais grosso.
  final int index;
  final int width;
  final int height;
  final int patchSize;
  final int half;

  /// `width * height * 3` — RGB, sem alfa (o alfa do original é preservado
  /// na recomposição e não participa da busca).
  final Uint8List rgb;

  /// `width * height` — 255 no buraco, 0 no que é conhecido.
  final Uint8List mask;

  /// Região onde a busca acontece: o buraco dilatado por [half], para que
  /// todo pixel do buraco esteja coberto por patches centrados aqui.
  late final Uint8List target = _dilate(mask, width, height, half);

  /// Índices dos pixels de [target], em ordem de varredura.
  late final Int32List targetPixels = _collectSet(target);

  /// Centros de patch válidos (patch inteiro dentro da imagem e sem nenhum
  /// pixel de buraco). Pré-calculado porque a busca aleatória sorteia daqui
  /// milhares de vezes por pixel.
  late final Int32List sources = _collectSources();

  /// Soma acumulada da máscara, para responder "este patch encosta no
  /// buraco?" em tempo constante.
  late final Int32List maskSat = _summedAreaTable(mask, width, height);

  /// Deslocamento atual de cada pixel-alvo, como índice do pixel de origem.
  final Int32List nnf;

  /// Distância do casamento atual, para a votação ponderada e para o corte
  /// antecipado da busca.
  final Float64List cost;

  /// Tabelas de reflexão: leem um pixel fora da borda rebatendo para dentro,
  /// sem `if` no laço interno. O patch-alvo pode passar da borda (um buraco
  /// encostado no canto da foto é comum); o de origem, não.
  late final Int32List reflectX = _reflectTable(width, half);
  late final Int32List reflectY = _reflectTable(height, half);

  Int32List _collectSources() {
    final result = <int>[];
    for (var y = half; y < height - half; y++) {
      for (var x = half; x < width - half; x++) {
        if (_patchIsClean(x, y)) result.add(y * width + x);
      }
    }
    return Int32List.fromList(result);
  }

  /// `true` quando o patch centrado em ([cx], [cy]) não toca o buraco.
  bool _patchIsClean(int cx, int cy) =>
      _rectSum(maskSat, width, cx - half, cy - half, patchSize, patchSize) == 0;
}

// ---------------------------------------------------------------------------
// Pirâmide
// ---------------------------------------------------------------------------

/// Monta a pirâmide do nível 0 (resolução cheia) até o mais grosso. Devolve
/// vazio quando não há o que fazer: sem buraco, ou sem nenhum patch limpo de
/// onde copiar.
List<_Level> _buildPyramid(
  Uint8List rgba,
  Uint8List mask,
  int width,
  int height,
  int patchSize,
) {
  final rgb = Uint8List(width * height * 3);
  for (var i = 0, j = 0; i < width * height; i++, j += 4) {
    rgb[i * 3] = rgba[j];
    rgb[i * 3 + 1] = rgba[j + 1];
    rgb[i * 3 + 2] = rgba[j + 2];
  }

  // Normaliza para 0/255: o resto do algoritmo testa só "zero ou não".
  final holes = Uint8List(width * height);
  var holeCount = 0;
  for (var i = 0; i < holes.length; i++) {
    if (mask[i] != 0) {
      holes[i] = 255;
      holeCount++;
    }
  }
  if (holeCount == 0) return const [];

  final levels = <_Level>[
    _Level(
      index: 0,
      width: width,
      height: height,
      rgb: rgb,
      mask: holes,
      patchSize: patchSize,
    ),
  ];

  // Para de descer quando a imagem não comporta mais um patch com folga, ou
  // quando o buraco já está do tamanho de uns poucos patches — descer além
  // disso faz o algoritmo inventar estrutura que não existe.
  while (levels.length < _maxLevels) {
    final finer = levels.last;
    final w = finer.width ~/ 2;
    final h = finer.height ~/ 2;
    if (w < patchSize * 3 || h < patchSize * 3) break;
    if (_holeExtent(finer) <= patchSize * 2) break;

    final coarser = _downsample(finer, levels.length, patchSize);
    if (coarser == null) break;
    levels.add(coarser);
  }

  // Um patch limpo no nível mais fino é o mínimo para haver o que copiar.
  if (levels.first.sources.isEmpty) return const [];
  return levels;
}

/// Maior lado da caixa que envolve o buraco, em pixels daquele nível.
int _holeExtent(_Level level) {
  var minX = level.width, minY = level.height, maxX = -1, maxY = -1;
  for (var y = 0; y < level.height; y++) {
    final row = y * level.width;
    for (var x = 0; x < level.width; x++) {
      if (level.mask[row + x] == 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return 0;
  return math.max(maxX - minX + 1, maxY - minY + 1);
}

/// Reduz um nível pela metade. A cor média usa **só os pixels conhecidos**
/// do bloco 2x2: sem isso o lixo de dentro do buraco vazaria para o nível de
/// cima e contaminaria a busca. A máscara, ao contrário, é dilatada (o bloco
/// vira buraco se qualquer um dos quatro for), porque um pixel meio inventado
/// nunca deve servir de origem.
_Level? _downsample(_Level finer, int index, int patchSize) {
  final w = finer.width ~/ 2;
  final h = finer.height ~/ 2;
  final rgb = Uint8List(w * h * 3);
  final mask = Uint8List(w * h);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var r = 0, g = 0, b = 0, known = 0, hole = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final si = (y * 2 + dy) * finer.width + (x * 2 + dx);
          if (finer.mask[si] != 0) {
            hole++;
            continue;
          }
          r += finer.rgb[si * 3];
          g += finer.rgb[si * 3 + 1];
          b += finer.rgb[si * 3 + 2];
          known++;
        }
      }
      final di = y * w + x;
      mask[di] = hole > 0 ? 255 : 0;
      if (known > 0) {
        rgb[di * 3] = r ~/ known;
        rgb[di * 3 + 1] = g ~/ known;
        rgb[di * 3 + 2] = b ~/ known;
      }
    }
  }

  final level = _Level(
    index: index,
    width: w,
    height: h,
    rgb: rgb,
    mask: mask,
    patchSize: patchSize,
  );
  // Um nível sem nenhum patch limpo não serve de ponto de partida.
  return level.sources.isEmpty ? null : level;
}

// ---------------------------------------------------------------------------
// Semente e transferência entre níveis
// ---------------------------------------------------------------------------

/// Preenche o buraco do nível mais grosso por difusão, de fora para dentro
/// ("onion peel"): cada casca vira a média dos vizinhos já resolvidos. Dá uma
/// base suave e sem cor solta para a primeira busca.
void _seedByDiffusion(_Level level) {
  final w = level.width;
  final h = level.height;
  final filled = Uint8List(w * h);
  for (var i = 0; i < filled.length; i++) {
    filled[i] = level.mask[i] == 0 ? 1 : 0;
  }

  var remaining = filled.length - filled.fold<int>(0, (s, v) => s + v);
  while (remaining > 0) {
    final ready = <int>[];
    final colors = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (filled[i] == 1) continue;
        var r = 0, g = 0, b = 0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w || (dx == 0 && dy == 0)) continue;
            final ni = ny * w + nx;
            if (filled[ni] == 0) continue;
            r += level.rgb[ni * 3];
            g += level.rgb[ni * 3 + 1];
            b += level.rgb[ni * 3 + 2];
            n++;
          }
        }
        if (n == 0) continue;
        ready.add(i);
        colors
          ..add(r ~/ n)
          ..add(g ~/ n)
          ..add(b ~/ n);
      }
    }
    // Nenhum pixel do buraco encosta em nada resolvido — não há como
    // continuar (buraco desconexo do conhecido).
    if (ready.isEmpty) break;
    for (var k = 0; k < ready.length; k++) {
      final i = ready[k];
      level.rgb[i * 3] = colors[k * 3];
      level.rgb[i * 3 + 1] = colors[k * 3 + 1];
      level.rgb[i * 3 + 2] = colors[k * 3 + 2];
      filled[i] = 1;
    }
    remaining -= ready.length;
  }
}

/// Leva a reconstrução do nível grosso para o fino por interpolação
/// bilinear, **só dentro do buraco** — o que é conhecido no nível fino já
/// está em resolução cheia e não deve ser trocado por uma versão ampliada.
void _upscaleInto(_Level coarse, _Level fine) {
  final sx = coarse.width / fine.width;
  final sy = coarse.height / fine.height;

  for (var y = 0; y < fine.height; y++) {
    for (var x = 0; x < fine.width; x++) {
      final di = y * fine.width + x;
      if (fine.mask[di] == 0) continue;

      final fx = ((x + 0.5) * sx - 0.5).clamp(0.0, coarse.width - 1.0);
      final fy = ((y + 0.5) * sy - 0.5).clamp(0.0, coarse.height - 1.0);
      final x0 = fx.floor();
      final y0 = fy.floor();
      final x1 = math.min(x0 + 1, coarse.width - 1);
      final y1 = math.min(y0 + 1, coarse.height - 1);
      final tx = fx - x0;
      final ty = fy - y0;

      final i00 = (y0 * coarse.width + x0) * 3;
      final i10 = (y0 * coarse.width + x1) * 3;
      final i01 = (y1 * coarse.width + x0) * 3;
      final i11 = (y1 * coarse.width + x1) * 3;

      for (var c = 0; c < 3; c++) {
        final top = coarse.rgb[i00 + c] * (1 - tx) + coarse.rgb[i10 + c] * tx;
        final bottom =
            coarse.rgb[i01 + c] * (1 - tx) + coarse.rgb[i11 + c] * tx;
        fine.rgb[di * 3 + c] = (top * (1 - ty) + bottom * ty).round().clamp(
          0,
          255,
        );
      }
    }
  }
}

/// Herda a NNF do nível grosso, dobrando as coordenadas. Começar daqui em
/// vez de do aleatório é o que torna os níveis finos baratos — a estrutura
/// já foi decidida embaixo.
void _upscaleNnf(_Level coarse, _Level fine) {
  for (final q in fine.targetPixels) {
    final x = q % fine.width;
    final y = q ~/ fine.width;
    final cx = math.min(x ~/ 2, coarse.width - 1);
    final cy = math.min(y ~/ 2, coarse.height - 1);
    final ci = cy * coarse.width + cx;

    var sx = (coarse.nnf[ci] % coarse.width) * 2 + (x & 1);
    var sy = (coarse.nnf[ci] ~/ coarse.width) * 2 + (y & 1);
    sx = sx.clamp(fine.half, fine.width - 1 - fine.half);
    sy = sy.clamp(fine.half, fine.height - 1 - fine.half);

    if (!fine._patchIsClean(sx, sy)) {
      final fallback = fine.sources[(q * 2654435761) % fine.sources.length];
      sx = fallback % fine.width;
      sy = fallback ~/ fine.width;
    }
    fine.nnf[q] = sy * fine.width + sx;
    fine.cost[q] = _patchDistance(fine, x, y, sx, sy, double.infinity);
  }
}

void _initialiseNnfRandomly(_Level level, int seed) {
  final random = math.Random(seed);
  for (final q in level.targetPixels) {
    final s = level.sources[random.nextInt(level.sources.length)];
    level.nnf[q] = s;
    level.cost[q] = _patchDistance(
      level,
      q % level.width,
      q ~/ level.width,
      s % level.width,
      s ~/ level.width,
      double.infinity,
    );
  }
}

// ---------------------------------------------------------------------------
// Busca (PatchMatch)
// ---------------------------------------------------------------------------

/// Uma passada de PatchMatch: propagação seguida de busca aleatória, em cada
/// pixel-alvo. Passadas alternam o sentido da varredura — de outro jeito a
/// informação só viaja para a direita e para baixo.
void _searchPass(_Level level, int seed, {required bool reverse}) {
  final random = math.Random(seed);
  final pixels = level.targetPixels;
  final w = level.width;
  final step = reverse ? -1 : 1;
  final start = reverse ? pixels.length - 1 : 0;
  final end = reverse ? -1 : pixels.length;

  for (var k = start; k != end; k += step) {
    final q = pixels[k];
    final x = q % w;
    final y = q ~/ w;

    // Propagação: o vizinho de trás (na ordem da varredura) provavelmente
    // casa com o patch vizinho ao dele — testar esse deslocamento deslocado
    // de um pixel é o truque central do PatchMatch.
    final nx = x - step;
    final ny = y - step;
    if (nx >= 0 && nx < w && level.target[y * w + nx] != 0) {
      final s = level.nnf[y * w + nx];
      _tryCandidate(level, q, x, y, s % w + step, s ~/ w);
    }
    if (ny >= 0 && ny < level.height && level.target[ny * w + x] != 0) {
      final s = level.nnf[ny * w + x];
      _tryCandidate(level, q, x, y, s % w, s ~/ w + step);
    }

    // Busca aleatória: janela em volta do melhor palpite atual, caindo pela
    // metade a cada passo. Tira a busca de mínimos locais sem custar uma
    // varredura inteira.
    final best = level.nnf[q];
    var bx = best % w;
    var by = best ~/ w;
    var radius = math.max(w, level.height);
    while (radius > 1) {
      final cx = bx + random.nextInt(radius * 2 + 1) - radius;
      final cy = by + random.nextInt(radius * 2 + 1) - radius;
      _tryCandidate(level, q, x, y, cx, cy);
      radius ~/= 2;
    }
  }
}

/// Testa um candidato a origem e o adota se for melhor. Rejeita o que sai da
/// imagem ou encosta no buraco — copiar de um pixel inventado é o caminho
/// mais curto para o buraco se propagar.
void _tryCandidate(_Level level, int q, int x, int y, int sx, int sy) {
  if (sx < level.half || sx >= level.width - level.half) return;
  if (sy < level.half || sy >= level.height - level.half) return;
  if (!level._patchIsClean(sx, sy)) return;

  final current = level.cost[q];
  final d = _patchDistance(level, x, y, sx, sy, current);
  if (d < current) {
    level.nnf[q] = sy * level.width + sx;
    level.cost[q] = d;
  }
}

/// Soma dos quadrados das diferenças entre o patch-alvo centrado em
/// ([tx], [ty]) e o de origem centrado em ([sx], [sy]).
///
/// [ceiling] corta a conta assim que a soma parcial já passa do melhor
/// resultado conhecido. Esse corte é o que torna o laço interno pagável: a
/// esmagadora maioria dos candidatos é descartada nas primeiras linhas.
double _patchDistance(
  _Level level,
  int tx,
  int ty,
  int sx,
  int sy,
  double ceiling,
) {
  final w = level.width;
  final half = level.half;
  final rgb = level.rgb;
  var sum = 0.0;

  for (var dy = -half; dy <= half; dy++) {
    final trow = level.reflectY[ty + dy + half] * w;
    final srow = (sy + dy) * w;
    for (var dx = -half; dx <= half; dx++) {
      final ti = (trow + level.reflectX[tx + dx + half]) * 3;
      final si = (srow + sx + dx) * 3;
      final dr = rgb[ti] - rgb[si];
      final dg = rgb[ti + 1] - rgb[si + 1];
      final db = rgb[ti + 2] - rgb[si + 2];
      sum += (dr * dr + dg * dg + db * db).toDouble();
    }
    if (sum >= ceiling) return sum;
  }
  return sum;
}

// ---------------------------------------------------------------------------
// Votação
// ---------------------------------------------------------------------------

/// Reconstrói o buraco a partir dos casamentos encontrados: cada patch vota
/// suas cores nos pixels que cobre, com peso por similaridade.
///
/// O peso é o que separa um resultado nítido de um borrão. Com média simples
/// (peso 1), dezenas de patches razoáveis e um ótimo contam igual e o
/// resultado vira a média de todos eles — exatamente o artefato de smear. Com
/// `exp(-d / 2σ²)`, o melhor casamento domina e a textura sobrevive. σ² sai
/// da distância média do próprio nível, então a escala se ajusta sozinha
/// entre uma foto lisa e uma cheia de detalhe.
void _vote(_Level level) {
  final w = level.width;
  final h = level.height;
  final half = level.half;
  final pixels = level.targetPixels;
  if (pixels.isEmpty) return;

  var meanCost = 0.0;
  for (final q in pixels) {
    meanCost += level.cost[q];
  }
  meanCost /= pixels.length;
  final sigma2 = math.max(meanCost, 1.0);

  final sums = Float64List(w * h * 3);
  final weights = Float64List(w * h);

  for (final q in pixels) {
    final x = q % w;
    final y = q ~/ w;
    final s = level.nnf[q];
    final sx = s % w;
    final sy = s ~/ w;
    final weight = math.exp(-level.cost[q] / (2 * sigma2));

    for (var dy = -half; dy <= half; dy++) {
      final ty = y + dy;
      if (ty < 0 || ty >= h) continue;
      final trow = ty * w;
      final srow = (sy + dy) * w;
      for (var dx = -half; dx <= half; dx++) {
        final tx = x + dx;
        if (tx < 0 || tx >= w) continue;
        final ti = trow + tx;
        // Só o buraco é reescrito; o resto da foto é intocável.
        if (level.mask[ti] == 0) continue;
        final si = (srow + sx + dx) * 3;
        sums[ti * 3] += level.rgb[si] * weight;
        sums[ti * 3 + 1] += level.rgb[si + 1] * weight;
        sums[ti * 3 + 2] += level.rgb[si + 2] * weight;
        weights[ti] += weight;
      }
    }
  }

  for (var i = 0; i < w * h; i++) {
    if (level.mask[i] == 0) continue;
    final weight = weights[i];
    // Peso zero acontece quando todos os casamentos daquele pixel ficaram
    // absurdamente ruins (exp satura em 0): manter o que já estava é melhor
    // que dividir por zero e pintar preto.
    if (weight <= 0) continue;
    level.rgb[i * 3] = (sums[i * 3] / weight).round().clamp(0, 255);
    level.rgb[i * 3 + 1] = (sums[i * 3 + 1] / weight).round().clamp(0, 255);
    level.rgb[i * 3 + 2] = (sums[i * 3 + 2] / weight).round().clamp(0, 255);
  }
}

/// Copia o RGB reconstruído do nível fino de volta para o RGBA de saída, só
/// nos pixels do buraco — o alfa e tudo o mais continuam os do original.
void _writeBack(_Level level, Uint8List out) {
  for (var i = 0; i < level.width * level.height; i++) {
    if (level.mask[i] == 0) continue;
    out[i * 4] = level.rgb[i * 3];
    out[i * 4 + 1] = level.rgb[i * 3 + 1];
    out[i * 4 + 2] = level.rgb[i * 3 + 2];
  }
}

// ---------------------------------------------------------------------------
// Utilitários geométricos
// ---------------------------------------------------------------------------

/// Dilata uma máscara por [radius] com uma janela quadrada, em duas passadas
/// separáveis (horizontal e vertical) — O(n) em vez de O(n·r²).
Uint8List _dilate(Uint8List mask, int width, int height, int radius) {
  final horizontal = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      final from = math.max(0, x - radius);
      final to = math.min(width - 1, x + radius);
      for (var i = from; i <= to; i++) {
        if (mask[row + i] != 0) {
          horizontal[row + x] = 255;
          break;
        }
      }
    }
  }

  final result = Uint8List(width * height);
  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      final from = math.max(0, y - radius);
      final to = math.min(height - 1, y + radius);
      for (var i = from; i <= to; i++) {
        if (horizontal[i * width + x] != 0) {
          result[y * width + x] = 255;
          break;
        }
      }
    }
  }
  return result;
}

Int32List _collectSet(Uint8List flags) {
  final result = <int>[];
  for (var i = 0; i < flags.length; i++) {
    if (flags[i] != 0) result.add(i);
  }
  return Int32List.fromList(result);
}

/// Tabela de somas acumuladas (`(width + 1) * (height + 1)`), para somar
/// qualquer retângulo da máscara em quatro leituras.
Int32List _summedAreaTable(Uint8List mask, int width, int height) {
  final sat = Int32List((width + 1) * (height + 1));
  final stride = width + 1;
  for (var y = 0; y < height; y++) {
    var rowSum = 0;
    for (var x = 0; x < width; x++) {
      rowSum += mask[y * width + x] != 0 ? 1 : 0;
      sat[(y + 1) * stride + (x + 1)] = sat[y * stride + (x + 1)] + rowSum;
    }
  }
  return sat;
}

int _rectSum(Int32List sat, int width, int x, int y, int w, int h) {
  final stride = width + 1;
  final x0 = x;
  final y0 = y;
  final x1 = x + w;
  final y1 = y + h;
  return sat[y1 * stride + x1] -
      sat[y0 * stride + x1] -
      sat[y1 * stride + x0] +
      sat[y0 * stride + x0];
}

/// Índices rebatidos na borda: `tabela[i + pad]` devolve a coluna/linha
/// válida correspondente a `i`, refletindo para dentro quando `i` sai da
/// imagem. Refletir em vez de repetir a borda evita o rastro de faixas que a
/// repetição deixa quando o buraco encosta no canto.
Int32List _reflectTable(int size, int pad) {
  final table = Int32List(size + 2 * pad);
  if (size == 1) return table;
  final period = 2 * size - 2;
  for (var i = 0; i < table.length; i++) {
    var v = (i - pad) % period;
    if (v < 0) v += period;
    table[i] = v < size ? v : period - v;
  }
  return table;
}
