import 'dart:io';
import 'dart:math' as math;
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
Future<CollageAnimationInfo> inspectCollageAnimation(
  CollageSettings settings,
) async {
  final durations = <Duration>[];
  for (final path in _photoPaths(settings)) {
    final duration = await _animationDuration(path);
    if (duration != null) durations.add(duration);
  }
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
Future<Duration?> _animationDuration(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
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
