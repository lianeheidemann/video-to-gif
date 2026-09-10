import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/collage_background.dart';
import '../models/collage_export.dart';
import '../models/collage_settings.dart';
import 'collage_compositor.dart';

/// Quadros já decodificados de uma foto animada (GIF/WebP), com o instante em
/// que cada um entra. [starts] tem o mesmo tamanho de [frames]: `starts[i]` é
/// o tempo (do começo da animação) em que o quadro `i` aparece.
class _AnimatedPhoto {
  _AnimatedPhoto(this.frames, this.starts, this.duration);

  final List<ui.Image> frames;
  final List<Duration> starts;
  final Duration duration;

  /// Quadro que está na tela no instante [t] — passando do fim, **continua no
  /// último quadro** em vez de sumir ou recomeçar: é o que faz uma animação
  /// curta "esperar" a mais longa terminar.
  ui.Image frameAt(Duration t) {
    for (var i = starts.length - 1; i >= 0; i--) {
      if (t >= starts[i]) return frames[i];
    }
    return frames.first;
  }

  void dispose() {
    for (final frame in frames) {
      frame.dispose();
    }
  }
}

/// O que a montagem tem de animado — usado pela tela para decidir se oferece
/// GIF/WebP na exportação e para mostrar as durações na folha de opções.
class CollageAnimationInfo {
  const CollageAnimationInfo({
    required this.animatedCount,
    required this.longest,
    required this.shortest,
  });

  /// Quantas fotos da montagem são animadas (mais de um quadro).
  final int animatedCount;

  /// Duração da animação mais longa e da mais curta entre elas — iguais
  /// quando só há uma foto animada; `Duration.zero` quando não há nenhuma.
  final Duration longest;
  final Duration shortest;

  bool get hasAnimation => animatedCount > 0;

  /// `true` quando as animações têm durações diferentes — só nesse caso a
  /// escolha "mais longa/mais curta" muda alguma coisa.
  bool get hasDifferentDurations => animatedCount > 1 && longest != shortest;

  Duration durationFor(CollageDurationRule rule) =>
      rule == CollageDurationRule.shortest ? shortest : longest;
}

/// Lê só os cabeçalhos das fotos da montagem para saber quais são animadas e
/// quanto duram — não decodifica nenhum quadro, então serve para decidir na
/// hora do toque se a folha de exportação mostra GIF/WebP.
///
/// Uma foto por vez aqui já significava esperar o disco de cada uma antes da
/// próxima começar; com [Future.wait] elas são lidas em paralelo, o que
/// importa sobretudo no caminho de reserva (foto que não é GIF, decodificada
/// quadro a quadro) quando a montagem tem várias fotos animadas.
Future<CollageAnimationInfo> inspectCollageAnimation(
  CollageSettings settings,
) async {
  final results = await Future.wait(
    _photoPaths(settings).map(_animationDuration),
  );
  final durations = [for (final d in results) ?d];
  if (durations.isEmpty) {
    return const CollageAnimationInfo(
      animatedCount: 0,
      longest: Duration.zero,
      shortest: Duration.zero,
    );
  }
  durations.sort();
  return CollageAnimationInfo(
    animatedCount: durations.length,
    longest: durations.last,
    shortest: durations.first,
  );
}

/// Caminhos distintos das fotos usadas nas células (uma mesma foto pode estar
/// em mais de uma célula — decodificar duas vezes seria desperdício).
Set<String> _photoPaths(CollageSettings settings) => {
  for (final cell in settings.cells)
    if (cell.photoPath != null) cell.photoPath!,
};

/// Duração total de um GIF/WebP animado, ou `null` quando o arquivo é uma
/// imagem parada (ou não dá para ler).
///
/// Tenta primeiro [_gifHeaderDuration], que lê só os blocos de controle do
/// GIF sem decodificar pixel nenhum — cobre o caso comum, já que o app é
/// "video to GIF". Qualquer coisa que não seja um GIF bem-formado (WebP
/// animado, arquivo corrompido, formato desconhecido) cai no caminho de
/// reserva abaixo, que decodifica quadro a quadro como antes.
Future<Duration?> _animationDuration(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    try {
      return _gifHeaderDuration(bytes);
    } on _GifParseFailure {
      // Não é um GIF reconhecível — segue para o decode completo abaixo.
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      if (codec.frameCount <= 1) return null;
      var total = Duration.zero;
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        total += _frameDuration(frame.duration);
        frame.image.dispose();
      }
      return total;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// Sinaliza que [_gifHeaderDuration] não conseguiu interpretar os bytes como
/// um GIF87a/89a válido — não é um erro de verdade, só o gatilho para
/// [_animationDuration] cair no decode completo de reserva.
class _GifParseFailure implements Exception {}

/// Lê a duração total de um GIF animado direto da estrutura de blocos do
/// arquivo (cabeçalho, *Graphic Control Extension* antes de cada quadro),
/// sem chamar [ui.instantiateImageCodec] nem decodificar um pixel sequer.
/// Devolve `null` para um GIF válido com um quadro só (parado); lança
/// [_GifParseFailure] para qualquer coisa que não seja um GIF87a/89a bem
/// formado, ou que a leitura não conseguiu terminar de percorrer.
///
/// Referência do formato: seção 23 (Graphic Control Extension) e 20 (Image
/// Descriptor) do GIF89a Specification.
Duration? _gifHeaderDuration(Uint8List bytes) {
  if (bytes.length < 13 ||
      bytes[0] != 0x47 /* G */ ||
      bytes[1] != 0x49 /* I */ ||
      bytes[2] != 0x46 /* F */ ) {
    throw _GifParseFailure();
  }

  var pos = 6; // "GIFxxa"
  pos += 4; // largura + altura da tela lógica
  final screenPacked = _byteAt(bytes, pos);
  pos += 1;
  pos += 2; // cor de fundo + proporção de pixel
  if ((screenPacked & 0x80) != 0) {
    pos += 3 * (1 << ((screenPacked & 0x07) + 1)); // tabela de cores global
  }

  var frameCount = 0;
  var totalMs = 0;
  var pendingDelayCentiseconds = 0;

  while (true) {
    final block = _byteAt(bytes, pos);
    pos += 1;
    if (block == 0x3B) break; // trailer: fim do arquivo

    if (block == 0x21) {
      final label = _byteAt(bytes, pos);
      pos += 1;
      if (label == 0xF9) {
        // Graphic Control Extension: tamanho do bloco (4), byte de opções,
        // atraso em centésimos de segundo (little-endian), índice de cor
        // transparente — sempre 4 bytes antes do terminador de sub-blocos.
        pos += 1; // tamanho do bloco (sempre 4)
        pos += 1; // byte de opções
        pendingDelayCentiseconds =
            _byteAt(bytes, pos) | (_byteAt(bytes, pos + 1) << 8);
        pos += 3; // atraso (2) + índice de cor transparente (1)
        pos = _skipGifSubBlocks(bytes, pos);
      } else if (label == 0x01 || label == 0xFF) {
        // Plain Text / Application Extension: um bloco de tamanho fixo (que
        // começa com o próprio tamanho em bytes) antes dos sub-blocos.
        final size = _byteAt(bytes, pos);
        pos += 1 + size;
        pos = _skipGifSubBlocks(bytes, pos);
      } else {
        // Comment Extension (0xFE) ou algo desconhecido: direto pros
        // sub-blocos, que é a estrutura comum a todas as extensões.
        pos = _skipGifSubBlocks(bytes, pos);
      }
    } else if (block == 0x2C) {
      // Image Descriptor: posição/tamanho do quadro (8 bytes) + byte de
      // opções; com tabela de cores local, ela vem antes dos dados da
      // imagem.
      pos += 8;
      final imgPacked = _byteAt(bytes, pos);
      pos += 1;
      if ((imgPacked & 0x80) != 0) {
        pos += 3 * (1 << ((imgPacked & 0x07) + 1));
      }
      pos += 1; // tamanho mínimo de código LZW
      pos = _skipGifSubBlocks(bytes, pos);

      frameCount += 1;
      totalMs += _frameDuration(
        Duration(milliseconds: pendingDelayCentiseconds * 10),
      ).inMilliseconds;
      pendingDelayCentiseconds = 0;
    } else {
      // Byte fora do esperado nesta posição — não é seguro seguir lendo.
      throw _GifParseFailure();
    }
  }

  if (frameCount <= 1) return null;
  return Duration(milliseconds: totalMs);
}

/// Sub-blocos de tamanho variável que terminam extensões e dados de imagem
/// no GIF: cada um começa com 1 byte de tamanho `N` seguido de `N` bytes,
/// até um tamanho `0` marcar o fim da sequência.
int _skipGifSubBlocks(Uint8List bytes, int start) {
  var pos = start;
  while (true) {
    final size = _byteAt(bytes, pos);
    pos += 1;
    if (size == 0) return pos;
    pos += size;
  }
}

/// Acesso ao byte em [index], lançando [_GifParseFailure] em vez de
/// `RangeError` quando os bytes acabam no meio de uma estrutura — um GIF
/// truncado/corrompido deve cair no decode de reserva, nunca derrubar a
/// tela.
int _byteAt(Uint8List bytes, int index) {
  if (index < 0 || index >= bytes.length) throw _GifParseFailure();
  return bytes[index];
}

/// GIFs com quadro de duração 0 (ou absurdamente curta) são comuns; os
/// navegadores tratam isso como ~100ms, e é o que fazemos aqui para a
/// montagem não sair acelerada.
Duration _frameDuration(Duration raw) =>
    raw.inMilliseconds < 20 ? const Duration(milliseconds: 100) : raw;

/// Resultado de [renderCollageFrames]: os PNGs de cada quadro, em ordem, e o
/// FPS com que devem ser tocados.
class CollageFrameSequence {
  const CollageFrameSequence({
    required this.directory,
    required this.pattern,
    required this.frameCount,
    required this.fps,
  });

  final Directory directory;

  /// Padrão no formato que o FFmpeg entende (`.../quadro_%05d.png`).
  final String pattern;
  final int frameCount;
  final int fps;

  Future<void> dispose() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

/// Lançada por [renderCollageFrames] quando quem chamou pede o cancelamento
/// pelo `isCancelled` — não é erro de verdade, e a tela trata mostrando
/// "exportação cancelada" em vez de uma mensagem de falha.
class CollageRenderCancelled implements Exception {
  @override
  String toString() => 'CollageRenderCancelled';
}

/// Limite de segurança para não estourar a memória/armazenamento com uma
/// montagem de várias fotos animadas longas.
const _maxOutputFrames = 300;
const _minFps = 5;
const _maxFps = 20;

/// Renderiza a montagem quadro a quadro numa pasta temporária, reusando o
/// mesmo desenho da prévia e do PNG ([composeCollageFrame]) — as fotos
/// paradas ficam iguais em todos os quadros e as animadas trocam conforme a
/// própria linha do tempo, segurando o último quadro quando acabam antes.
Future<CollageFrameSequence> renderCollageFrames({
  required CollageSettings settings,
  required int outputWidth,
  required CollageDurationRule rule,
  required Directory workDir,
  void Function(double progress)? onProgress,
  bool Function()? isCancelled,
}) async {
  final animated = <String, _AnimatedPhoto>{};
  final stills = <String, ui.Image>{};
  final backgrounds = <String, ui.Image>{};

  try {
    for (final path in _photoPaths(settings)) {
      final decoded = await _decodeAnimated(path);
      if (decoded == null) continue;
      if (decoded.frames.length > 1) {
        animated[path] = decoded;
      } else {
        stills[path] = decoded.frames.first;
      }
    }
    for (final path in _backgroundPaths(settings)) {
      final image = await _decodeStill(path);
      if (image != null) backgrounds[path] = image;
    }

    final durations = animated.values.map((a) => a.duration).toList()..sort();
    final total = durations.isEmpty
        ? const Duration(milliseconds: 100)
        : (rule == CollageDurationRule.shortest
              ? durations.first
              : durations.last);

    final fps = _fpsFor(animated.values);
    final frameCount = math.max(
      1,
      math.min(_maxOutputFrames, (total.inMilliseconds * fps / 1000).round()),
    );

    final pattern = '${workDir.path}/quadro_%05d.png';
    for (var index = 0; index < frameCount; index++) {
      // Entre um quadro e outro: é o ponto em que dá para parar sem deixar
      // um PNG pela metade na pasta de trabalho.
      if (isCancelled?.call() ?? false) throw CollageRenderCancelled();
      final t = Duration(milliseconds: (index * 1000 / fps).round());
      final cellImages = [
        for (final cell in settings.cells)
          cell.photoPath == null
              ? null
              : (animated[cell.photoPath!]?.frameAt(t) ??
                    stills[cell.photoPath!]),
      ];
      final bytes = await composeCollageFrame(
        settings: settings,
        outputWidth: outputWidth,
        cellImages: cellImages,
        backgroundImage: backgrounds[settings.background.imagePath],
        cellBackgroundImages: backgrounds,
      );
      final name = index.toString().padLeft(5, '0');
      await File('${workDir.path}/quadro_$name.png').writeAsBytes(bytes);
      onProgress?.call((index + 1) / frameCount);
    }

    return CollageFrameSequence(
      directory: workDir,
      pattern: pattern,
      frameCount: frameCount,
      fps: fps,
    );
  } finally {
    for (final photo in animated.values) {
      photo.dispose();
    }
    for (final image in stills.values) {
      image.dispose();
    }
    for (final image in backgrounds.values) {
      image.dispose();
    }
  }
}

/// FPS de saída: acompanha a animação mais "rápida" da montagem, limitado a
/// uma faixa razoável para GIF ([_minFps] a [_maxFps]) — mais que isso só
/// engorda o arquivo sem ganho visível.
int _fpsFor(Iterable<_AnimatedPhoto> photos) {
  var best = _minFps.toDouble();
  for (final photo in photos) {
    final seconds = photo.duration.inMilliseconds / 1000;
    if (seconds <= 0) continue;
    best = math.max(best, photo.frames.length / seconds);
  }
  return best.round().clamp(_minFps, _maxFps);
}

Set<String> _backgroundPaths(CollageSettings settings) => {
  if (settings.background.mode == CollageBackgroundMode.image &&
      settings.background.imagePath != null)
    settings.background.imagePath!,
  for (final cell in settings.cells)
    if (cell.background.mode == CollageBackgroundMode.image &&
        cell.background.imagePath != null)
      cell.background.imagePath!,
};

/// Decodifica todos os quadros de [path] (um só, quando a imagem é parada).
Future<_AnimatedPhoto?> _decodeAnimated(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frames = <ui.Image>[];
      final starts = <Duration>[];
      var elapsed = Duration.zero;
      final count = math.min(codec.frameCount, _maxOutputFrames);
      for (var i = 0; i < count; i++) {
        final frame = await codec.getNextFrame();
        frames.add(frame.image);
        starts.add(elapsed);
        elapsed += _frameDuration(frame.duration);
      }
      if (frames.isEmpty) return null;
      return _AnimatedPhoto(frames, starts, elapsed);
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

Future<ui.Image?> _decodeStill(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}
