import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/ffmpeg/ffmpeg_service.dart';
import '../models/collage_export.dart';
import '../models/collage_settings.dart';
import '../painting/collage_painter.dart';
import '../widgets/export_progress_dialog.dart';
import 'collage_animation.dart';
import 'collage_compositor.dart';

/// Gera o arquivo final da montagem: PNG numa composição só, ou a sequência
/// de quadros da montagem animada codificada pelo FFmpeg.
///
/// Guarda o progresso, o cancelamento e o cache da inspeção de animação. A
/// tela fica só com as folhas de escolha e o pop-up de progresso, que
/// precisam de `BuildContext`.
class CollageExportRunner {
  final _ffmpeg = FfmpegService();

  /// Progresso da exportação animada, consumido pelo [ExportProgressDialog].
  final progress = ValueNotifier(const ExportProgress());

  bool _cancelled = false;
  bool get cancelled => _cancelled;

  Set<String>? _cachedAnimationPhotoPaths;
  CollageAnimationInfo? _cachedAnimationInfo;

  void dispose() => progress.dispose();

  /// Largura da exportação: grande o bastante para cada foto caber na sua
  /// célula sem encolher, multiplicada pelo tamanho escolhido ("Padrão" tem
  /// multiplicador 1 e não muda nada daqui).
  ///
  /// Antes valia o maior lado entre as fotos, o que ignorava o layout: numa
  /// montagem com quatro fotos lado a lado, cada célula fica com ~1/4 da
  /// largura, então exportar na largura de UMA foto reduzia todas a um quarto
  /// do tamanho — era isso que saía visivelmente borrado. A conta é ao
  /// contrário: mede que fração da montagem cada célula ocupa e pede a
  /// largura que devolve a resolução original de cada foto.
  static int exportWidth(CollageSettings settings, CollageExportSize size) {
    // A fração não depende do tamanho medido, então qualquer largura de
    // referência serve para descobrir as proporções do layout.
    const probe = 1000.0;
    final probeSize = Size(probe, probe / settings.aspectRatio);
    final geometry = CollageGeometry.of(probeSize, settings);
    var needed = 480.0;
    for (var i = 0; i < settings.cells.length; i++) {
      if (i >= geometry.cellRects.length) continue;
      final cell = settings.cells[i];
      if (!cell.hasPhoto) continue;
      final rect = geometry.cellRects[i];
      if (rect.width > 0) {
        needed = math.max(needed, cell.photoWidth * probe / rect.width);
      }
      if (rect.height > 0) {
        // Pela altura: a montagem precisa de tantas alturas quanto a célula
        // é menor que a foto, e a largura sai da proporção da montagem.
        final byHeight = cell.photoHeight * probeSize.height / rect.height;
        needed = math.max(needed, byHeight * settings.aspectRatio);
      }
    }
    // O piso/teto escalam junto com o tamanho escolhido — "Extra grande" pode
    // pedir o dobro do teto padrão, "Pequeno" aceita a metade do piso.
    final multiplier = size.multiplier;
    final minWidth = (480 * multiplier).round();
    final maxWidth = (2200 * multiplier).round();
    return (needed * multiplier).round().clamp(minWidth, maxWidth);
  }

  /// Largura da exportação animada — o PNG usa [exportWidth] inteiro.
  ///
  /// O teto existe porque a animação paga o custo de desenhar e codificar
  /// cada quadro; 1440 ainda cabe no celular e já é o bastante para quatro
  /// fotos de 360px lado a lado saírem sem redução — e escala com o tamanho
  /// escolhido do mesmo jeito que o teto do PNG.
  static int animatedExportWidth(
    CollageSettings settings,
    CollageExportSize size,
  ) => math.min(exportWidth(settings, size), (1440 * size.multiplier).round());

  /// Tamanho final em pixels, do mesmo jeito que o compositor calcula: a
  /// altura sai da proporção da montagem.
  static (int width, int height) pixelSize(
    CollageSettings settings,
    CollageExportSize size,
    CollageExportFormat format,
  ) {
    final width = format.isAnimated
        ? animatedExportWidth(settings, size)
        : exportWidth(settings, size);
    final height = (width / settings.aspectRatio).round().clamp(2, 1 << 20);
    return (width, height);
  }

  /// Inspeciona a animação das fotos, reaproveitando o resultado enquanto o
  /// conjunto de fotos não muda — adicionar, tirar ou trocar uma célula troca
  /// o caminho também, então reabrir a folha de exportar não relê nenhum
  /// arquivo do zero.
  Future<CollageAnimationInfo> inspectAnimationCached(
    CollageSettings settings,
  ) async {
    final Set<String> paths = {
      for (final cell in settings.cells)
        if (cell.photoPath != null) cell.photoPath!,
    };
    final cachedPaths = _cachedAnimationPhotoPaths;
    final cachedInfo = _cachedAnimationInfo;
    if (cachedInfo != null &&
        cachedPaths != null &&
        cachedPaths.length == paths.length &&
        cachedPaths.containsAll(paths)) {
      return cachedInfo;
    }
    final info = await inspectCollageAnimation(settings);
    _cachedAnimationPhotoPaths = paths;
    _cachedAnimationInfo = info;
    return info;
  }

  /// Prepara um começo de exportação: zera o cancelamento e o progresso.
  void begin() {
    _cancelled = false;
    progress.value = const ExportProgress();
  }

  void cancel() {
    _cancelled = true;
    progress.value = ExportProgress(
      value: progress.value.value,
      cancelling: true,
    );
    unawaited(_ffmpeg.cancel());
  }

  /// Gera o arquivo final no formato escolhido.
  ///
  /// [reportProgress] recebe valores de 0 a 1 e é chamado só durante a
  /// exportação animada — quem chama decide se ainda vale atualizar a tela.
  Future<File> build({
    required CollageSettings settings,
    required CollageExportFormat format,
    required CollageExportSize size,
    required CollageDurationRule rule,
    required ValueChanged<double> reportProgress,
  }) async {
    if (!format.isAnimated) {
      final bytes = await composeCollage(
        settings: settings,
        outputWidth: exportWidth(settings, size),
      );
      return writeTempFile(bytes, format.extension);
    }

    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final workDir = await Directory(
      '${temp.path}/montagem_quadros_$stamp',
    ).create(recursive: true);
    try {
      final sequence = await renderCollageFrames(
        settings: settings,
        // A animação multiplica o custo por quadro; um limite mais baixo que
        // o do PNG mantém a exportação viável no celular.
        outputWidth: animatedExportWidth(settings, size),
        rule: rule,
        workDir: workDir,
        // Desenhar os quadros é a parte longa: fica com 85% da barra, e a
        // codificação com os 15% finais.
        onProgress: (value) => reportProgress(value * 0.85),
        isCancelled: () => _cancelled,
      );
      return await _ffmpeg.encodeCollageSequence(
        framePattern: sequence.pattern,
        fps: sequence.fps,
        outputPath: '${temp.path}/montagem_$stamp.${format.extension}',
        webp: format == CollageExportFormat.webp,
        frameCount: sequence.frameCount,
        onProgress: (value) => reportProgress(0.85 + value * 0.15),
      );
    } finally {
      if (await workDir.exists()) await workDir.delete(recursive: true);
    }
  }

  Future<File> writeTempFile(Uint8List bytes, String extension) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/montagem_${DateTime.now().millisecondsSinceEpoch}'
        '.$extension';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
