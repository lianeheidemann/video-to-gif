/// A borracha mágica de "Editar imagem": apaga a região marcada e devolve a
/// foto com o fundo reconstruído, em PNG e **nas mesmas dimensões** da
/// original.
///
/// Manter o tamanho é o que deixa o resto da tela em paz: o recorte da aba
/// "Recorte" está em pixels da foto, então mudar a resolução aqui
/// desalinharia tudo.
///
/// ## Por que a memória não estoura
///
/// O caminho ingênuo — decodificar a foto inteira para RGBA e mandar para o
/// Isolate — coloca 48 MB **por cópia** no heap do Dart numa foto de 12 MP, e
/// derruba aparelho mediano. Aqui a foto nunca vira bytes no heap: ela fica
/// como [ui.Image] (memória da engine), e o que atravessa para o Isolate é só
/// uma **janela recortada em volta da máscara**, reduzida ao teto da
/// qualidade escolhida — da ordem de 1 a 4 MB. A recomposição em resolução
/// cheia volta a ser desenho de `Canvas`, não aritmética de bytes.
///
/// Efeito colateral bom: quando a janela já cabe abaixo do teto (apagar uma
/// marca d'água, uma placa, alguém ao longe), não há redução nenhuma e o
/// preenchimento sai em resolução nativa.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/eraser_mask.dart';
import '../../../core/models/photo_info.dart';
import '../../../core/painting/frame_painter.dart' show rasterizeCanvas;
import 'inpaint_patchmatch.dart';

/// Quanto a emenda entre o preenchimento e a foto é suavizada, em pixels da
/// foto. Pouco de propósito: o suficiente para não deixar um degrau de um
/// pixel, pouco o bastante para não repuxar a borda.
const _featherSigma = 1.2;

/// Uma apagada em andamento. A tela guarda isto enquanto o pop-up de
/// progresso está na frente, para poder cancelar.
class MagicEraseTask {
  MagicEraseTask._(this._isolate, this._done);

  final Completer<Uint8List> _done;
  Isolate? _isolate;

  /// O PNG da foto já corrigida. Falha com [MagicEraserCancelled] quando
  /// [cancel] é chamado antes do fim.
  Future<Uint8List> get done => _done.future;

  var _cancelled = false;
  bool get isCancelled => _cancelled;

  /// Interrompe na hora. Matar o Isolate é o único jeito de parar um laço
  /// apertado de verdade — checar uma bandeira entre iterações deixaria a
  /// pessoa esperando pela iteração corrente, que no nível mais fino é a
  /// parte mais cara.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    if (!_done.isCompleted) _done.completeError(MagicEraserCancelled());
  }
}

class MagicEraserCancelled implements Exception {
  @override
  String toString() => 'Apagada cancelada.';
}

class MagicEraserException implements Exception {
  MagicEraserException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Começa a apagar [mask] de [photo].
///
/// [seed] muda o resultado sem mudar a seleção — é o que o botão "Tentar de
/// novo" usa. [onProgress] recebe de 0 a 1.
MagicEraseTask startMagicErase({
  required PhotoInfo photo,
  required EraserMask mask,
  required EraserQuality quality,
  int seed = 0,
  ValueChanged<double>? onProgress,
}) {
  final completer = Completer<Uint8List>();
  final task = MagicEraseTask._(null, completer);

  unawaited(
    _erase(
      photo: photo,
      mask: mask,
      quality: quality,
      seed: seed,
      onProgress: onProgress,
      task: task,
    ).then(
      (bytes) {
        if (!completer.isCompleted) completer.complete(bytes);
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    ),
  );

  return task;
}

Future<Uint8List> _erase({
  required PhotoInfo photo,
  required EraserMask mask,
  required EraserQuality quality,
  required int seed,
  required ValueChanged<double>? onProgress,
  required MagicEraseTask task,
}) async {
  final hole = mask.boundsIn(photo.width, photo.height);
  if (hole == null) {
    throw MagicEraserException('Não há nada marcado para apagar.');
  }

  final window = eraserContextWindow(hole, photo.width, photo.height);
  final scale = eraserWorkingScale(window, quality);
  // Um mínimo de folga: abaixo disso a pirâmide não tem onde descer e o
  // algoritmo não tem textura de onde copiar.
  final workWidth = (window.width * scale).round().clamp(32, 4096);
  final workHeight = (window.height * scale).round().clamp(32, 4096);

  final source = await _decodeImage(photo.path);
  ui.Image? windowImage;
  ui.Image? maskImage;
  ui.Image? patchImage;

  try {
    windowImage = await _renderWindow(source, window, workWidth, workHeight);
    maskImage = await _renderMask(mask, window, workWidth, workHeight);

    final rgba = await windowImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final maskRgba = await maskImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (rgba == null || maskRgba == null) {
      throw MagicEraserException('Não foi possível ler a imagem.');
    }

    // A máscara vive no canal alfa: a imagem nasce transparente, o que soma
    // pinta branco opaco e o que tira volta a limpar.
    final maskBytes = Uint8List(workWidth * workHeight);
    final maskSource = maskRgba.buffer.asUint8List();
    for (var i = 0; i < maskBytes.length; i++) {
      maskBytes[i] = maskSource[i * 4 + 3] >= 128 ? 255 : 0;
    }

    final filled = await _inpaintInIsolate(
      rgba: rgba.buffer.asUint8List(),
      mask: maskBytes,
      width: workWidth,
      height: workHeight,
      seed: seed,
      onProgress: onProgress,
      task: task,
    );

    patchImage = await _imageFromPixels(filled, workWidth, workHeight);
    return await _composeFullSize(
      source: source,
      patch: patchImage,
      maskImage: maskImage,
      window: window,
      width: photo.width,
      height: photo.height,
    );
  } finally {
    source.dispose();
    windowImage?.dispose();
    maskImage?.dispose();
    patchImage?.dispose();
  }
}

// ---------------------------------------------------------------------------
// Passos de imagem (tudo no isolate principal — `dart:ui` precisa da engine)
// ---------------------------------------------------------------------------

Future<ui.Image> _decodeImage(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// Recorta a janela de contexto de [source] já na resolução de trabalho. É
/// aqui que a foto de 12 MP vira um buffer de poucos MB.
Future<ui.Image> _renderWindow(
  ui.Image source,
  Rect window,
  int width,
  int height,
) => _recordImage(width, height, (canvas) {
  canvas.drawImageRect(
    source,
    window,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
});

/// Rasteriza a seleção na mesma grade da janela. Sai transparente com as
/// áreas marcadas em branco opaco — assim o **alfa** é a máscara, e a mesma
/// imagem serve de recorte na recomposição, sem precisar rasterizar de novo.
Future<ui.Image> _renderMask(
  EraserMask mask,
  Rect window,
  int width,
  int height,
) => _recordImage(width, height, (canvas) {
  final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  // `BlendMode.clear` do "apagar seleção" só funciona dentro de uma camada
  // própria; no canvas raiz do gravador ele não tem o que limpar.
  canvas.saveLayer(bounds, Paint());
  canvas.scale(width / window.width, height / window.height);
  canvas.translate(-window.left, -window.top);
  paintEraserMask(
    canvas,
    mask,
    addColor: const Color(0xFFFFFFFF),
    subtractColor: const Color(0x00000000),
    subtractBlendMode: BlendMode.clear,
  );
  canvas.restore();
});

/// Junta tudo na resolução original: a foto inteira, e por cima o pedaço
/// preenchido, recortado pela máscara com a borda suavizada.
///
/// O recorte é feito com [BlendMode.dstIn] contra a própria imagem da
/// máscara: o alfa dela multiplica o alfa do pedaço, então só o que estava
/// marcado sobrevive. O desfoque transforma a borda dura num degradê curto,
/// que é o que faz a emenda sumir.
Future<Uint8List> _composeFullSize({
  required ui.Image source,
  required ui.Image patch,
  required ui.Image maskImage,
  required Rect window,
  required int width,
  required int height,
}) => rasterizeCanvas(width, height, (canvas, size) {
  canvas.drawImage(source, Offset.zero, Paint());

  final patchSource = Rect.fromLTWH(
    0,
    0,
    patch.width.toDouble(),
    patch.height.toDouble(),
  );

  canvas.saveLayer(Offset.zero & size, Paint());
  canvas.drawImageRect(
    patch,
    patchSource,
    window,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.drawImageRect(
    maskImage,
    patchSource,
    window,
    Paint()
      ..blendMode = BlendMode.dstIn
      ..filterQuality = FilterQuality.high
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: _featherSigma,
        sigmaY: _featherSigma,
      ),
  );
  canvas.restore();
});

Future<ui.Image> _recordImage(
  int width,
  int height,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<ui.Image> _imageFromPixels(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

// ---------------------------------------------------------------------------
// O Isolate
// ---------------------------------------------------------------------------

/// O que atravessa para o Isolate. Só tipos que a porta aceita — nada de
/// [ui.Image], que não sai do isolate da engine.
class _InpaintRequest {
  const _InpaintRequest({
    required this.reply,
    required this.rgba,
    required this.mask,
    required this.width,
    required this.height,
    required this.seed,
  });

  final SendPort reply;
  final TransferableTypedData rgba;
  final TransferableTypedData mask;
  final int width;
  final int height;
  final int seed;
}

/// Roda o inpainting fora da thread de interface.
///
/// `Isolate.run` seria mais curto, mas não dá porta de volta para o progresso
/// nem como cancelar — e uma apagada de alguns segundos sem barra parece o
/// app travado. Daí o [Isolate.spawn] com [ReceivePort] na mão.
Future<Uint8List> _inpaintInIsolate({
  required Uint8List rgba,
  required Uint8List mask,
  required int width,
  required int height,
  required int seed,
  required ValueChanged<double>? onProgress,
  required MagicEraseTask task,
}) async {
  if (task.isCancelled) throw MagicEraserCancelled();

  final receive = ReceivePort();
  final result = Completer<Uint8List>();

  final isolate = await Isolate.spawn(
    _inpaintEntryPoint,
    _InpaintRequest(
      reply: receive.sendPort,
      // Transfere em vez de copiar: os buffers saem daqui e chegam lá sem
      // passar duas vezes pela memória.
      rgba: TransferableTypedData.fromList([rgba]),
      mask: TransferableTypedData.fromList([mask]),
      width: width,
      height: height,
      seed: seed,
    ),
    onError: receive.sendPort,
    onExit: receive.sendPort,
    errorsAreFatal: true,
  );
  task._isolate = isolate;

  // Cancelar mata o Isolate; sem isso a espera abaixo nunca terminaria.
  if (task.isCancelled) {
    isolate.kill(priority: Isolate.immediate);
    receive.close();
    throw MagicEraserCancelled();
  }

  final subscription = receive.listen((Object? message) {
    if (message is double) {
      onProgress?.call(message);
      return;
    }
    if (message is TransferableTypedData) {
      if (!result.isCompleted) {
        result.complete(message.materialize().asUint8List());
      }
      return;
    }
    // `onExit` manda `null`; `onError` manda uma lista [erro, pilha]. Os dois
    // só importam se chegarem antes do resultado — aí a apagada falhou.
    if (!result.isCompleted) {
      result.completeError(
        task.isCancelled
            ? MagicEraserCancelled()
            : MagicEraserException('A apagada falhou: $message'),
      );
    }
  });

  try {
    return await result.future;
  } finally {
    await subscription.cancel();
    receive.close();
    isolate.kill(priority: Isolate.immediate);
    task._isolate = null;
  }
}

void _inpaintEntryPoint(_InpaintRequest request) {
  final filled = inpaintPatchMatch(
    rgba: request.rgba.materialize().asUint8List(),
    mask: request.mask.materialize().asUint8List(),
    width: request.width,
    height: request.height,
    seed: request.seed,
    onProgress: request.reply.send,
  );
  request.reply.send(TransferableTypedData.fromList([filled]));
}
