import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/image_frame.dart';
import '../ui/widgets/frame_painter.dart' show rasterizeCanvas;

/// Erro ao importar uma imagem de moldura própria — mensagem já pronta em
/// português para mostrar ao usuário.
class ImportedFrameException implements Exception {
  ImportedFrameException(this.message);

  final String message;

  @override
  String toString() => 'ImportedFrameException: $message';
}

/// Importa, detecta a janela transparente e persiste molduras de imagem em
/// SVG escolhidas pelo usuário no aparelho — a contraparte de
/// [ImageFrameLibrary] (que só lista as molduras prontas do app).
class ImportedFrameStore {
  static const _prefsKey = 'importedFrames';

  /// Downsample da máscara de alfa para detecção rápida: o lado maior nunca
  /// passa disso, então a varredura fica em Dart puro e continua instantânea
  /// mesmo numa foto de altíssima resolução.
  static const _detectionMaxSide = 300;

  /// Abre o seletor de arquivos restrito a SVG (mesmo formato das molduras
  /// que já vêm no app), detecta o retângulo de conteúdo renderizando o
  /// vetor para um bitmap temporário e rodando a mesma detecção usada para
  /// PNG, copia o arquivo original para a pasta de dados do app e persiste
  /// os metadados. Lança [ImportedFrameException] com uma mensagem pronta
  /// para mostrar ao usuário quando o arquivo não serve como moldura.
  Future<ImageFrameAsset> importFrame() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['svg'],
      dialogTitle: 'Escolha um SVG de moldura (mesmo formato das prontas)',
    );
    final path = picked?.path;
    if (path == null) {
      throw ImportedFrameException('Nenhum arquivo selecionado.');
    }

    final bytes = await File(path).readAsBytes();
    late final NormalizedRect contentRect;
    late final double aspectRatio;
    late final int nativeWidth;

    final PictureInfo pictureInfo;
    try {
      pictureInfo = await vg.loadPicture(SvgFileLoader(File(path)), null);
    } catch (_) {
      throw ImportedFrameException(
        'Não foi possível ler este arquivo como SVG.',
      );
    }
    try {
      final nativeSize = pictureInfo.size;
      if (nativeSize.width <= 0 || nativeSize.height <= 0) {
        throw ImportedFrameException('Este SVG não tem um tamanho válido.');
      }
      aspectRatio = nativeSize.width / nativeSize.height;
      nativeWidth = nativeSize.width.round();

      final pngBytes = await rasterizeCanvas(
        nativeWidth < 1 ? 1 : nativeWidth,
        nativeSize.height.round() < 1 ? 1 : nativeSize.height.round(),
        (canvas, size) {
          canvas.scale(
            size.width / nativeSize.width,
            size.height / nativeSize.height,
          );
          canvas.drawPicture(pictureInfo.picture);
        },
      );

      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (raw == null) {
          throw ImportedFrameException('Não foi possível ler este SVG.');
        }
        contentRect = _detectContentRect(raw, image.width, image.height);
      } finally {
        image.dispose();
      }
    } finally {
      pictureInfo.picture.dispose();
    }

    final supportDir = await getApplicationSupportDirectory();
    final framesDir = Directory('${supportDir.path}/imported_frames');
    await framesDir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${framesDir.path}/$stamp.svg';
    await File(destPath).writeAsBytes(bytes);

    final rawLabel = picked!.name;
    final dot = rawLabel.lastIndexOf('.');
    final label = (dot > 0 ? rawLabel.substring(0, dot) : rawLabel).trim();

    final asset = ImageFrameAsset(
      id: 'imported_$stamp',
      label: label.isEmpty ? 'Moldura importada' : label,
      source: ImageFrameSource.importedSvg,
      imageFilePath: destPath,
      nativeAspectRatio: aspectRatio,
      nativeReferenceWidth: nativeWidth,
      contentRect: contentRect,
    );

    await _persistAppend(asset);
    return asset;
  }

  /// Carrega as molduras importadas anteriormente, ignorando entradas cujo
  /// arquivo copiado não existe mais em disco.
  Future<List<ImageFrameAsset>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final assets = <ImageFrameAsset>[];
    for (final entry in raw) {
      final asset = _decode(entry);
      if (asset == null) continue;
      if (!File(asset.imageFilePath!).existsSync()) continue;
      assets.add(asset);
    }
    return assets;
  }

  /// Remove uma moldura importada: apaga o arquivo copiado e o metadado
  /// persistido.
  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final kept = <String>[];
    for (final entry in raw) {
      final asset = _decode(entry);
      if (asset != null && asset.id == id) {
        await _deleteQuietly(asset.imageFilePath!);
        continue;
      }
      kept.add(entry);
    }
    await prefs.setStringList(_prefsKey, kept);
  }

  Future<void> _persistAppend(ImageFrameAsset asset) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    await prefs.setStringList(_prefsKey, [...raw, _encode(asset)]);
  }

  String _encode(ImageFrameAsset asset) => jsonEncode({
    'id': asset.id,
    'label': asset.label,
    'source': asset.source.name,
    'filePath': asset.imageFilePath,
    'aspect': asset.nativeAspectRatio,
    'nativeWidth': asset.nativeReferenceWidth,
    'left': asset.contentRect.left,
    'top': asset.contentRect.top,
    'width': asset.contentRect.width,
    'height': asset.contentRect.height,
  });

  ImageFrameAsset? _decode(String entry) {
    try {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      // Entradas salvas antes de existir o campo `source` são sempre PNGs
      // importados no formato antigo (o único que existia então).
      final source = ImageFrameSource.values.firstWhere(
        (s) => s.name == map['source'],
        orElse: () => ImageFrameSource.importedImage,
      );
      return ImageFrameAsset(
        id: map['id'] as String,
        label: map['label'] as String,
        source: source,
        imageFilePath: map['filePath'] as String,
        nativeAspectRatio: (map['aspect'] as num).toDouble(),
        // Molduras importadas antes deste campo existir nunca tiveram a
        // largura real salva — 1080 é o mesmo padrão usado pelas artes
        // empacotadas.
        nativeReferenceWidth: (map['nativeWidth'] as num?)?.toInt() ?? 1080,
        contentRect: NormalizedRect(
          (map['left'] as num).toDouble(),
          (map['top'] as num).toDouble(),
          (map['width'] as num).toDouble(),
          (map['height'] as num).toDouble(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Acha a janela de conteúdo dentro de uma imagem RGBA: a maior região
  /// transparente que NÃO toca a borda da imagem (a transparência que toca
  /// a borda é o fundo/margem ao redor do corpo da moldura, não a tela).
  ///
  /// Faz *flood fill* (BFS) em duas passadas sobre uma versão reduzida da
  /// máscara de alfa: a primeira propaga a partir de toda borda para marcar
  /// a transparência "externa"; a segunda acha, entre o que sobrou, os
  /// componentes "internos" e escolhe o de maior área.
  NormalizedRect _detectContentRect(ByteData raw, int width, int height) {
    final scale = width > height
        ? _detectionMaxSide / width
        : _detectionMaxSide / height;
    final sw = (width * scale).clamp(1, _detectionMaxSide).round();
    final sh = (height * scale).clamp(1, _detectionMaxSide).round();

    // 0 = opaco, 1 = transparente ainda não visitado, 2 = transparente
    // externo (visitado, descartado), 3 = transparente interno (candidato).
    final grid = Uint8List(sw * sh);
    for (var y = 0; y < sh; y++) {
      final srcY = ((y + 0.5) / sh * height).floor().clamp(0, height - 1);
      for (var x = 0; x < sw; x++) {
        final srcX = ((x + 0.5) / sw * width).floor().clamp(0, width - 1);
        final alpha = raw.getUint8((srcY * width + srcX) * 4 + 3);
        grid[y * sw + x] = alpha < 10 ? 1 : 0;
      }
    }

    final queue = <int>[];
    void enqueueIfTransparent(int x, int y) {
      if (x < 0 || y < 0 || x >= sw || y >= sh) return;
      final i = y * sw + x;
      if (grid[i] == 1) {
        grid[i] = 2;
        queue.add(i);
      }
    }

    for (var x = 0; x < sw; x++) {
      enqueueIfTransparent(x, 0);
      enqueueIfTransparent(x, sh - 1);
    }
    for (var y = 0; y < sh; y++) {
      enqueueIfTransparent(0, y);
      enqueueIfTransparent(sw - 1, y);
    }
    var head = 0;
    while (head < queue.length) {
      final i = queue[head++];
      final x = i % sw;
      final y = i ~/ sw;
      enqueueIfTransparent(x - 1, y);
      enqueueIfTransparent(x + 1, y);
      enqueueIfTransparent(x, y - 1);
      enqueueIfTransparent(x, y + 1);
    }

    // Entre os pixels transparentes restantes (marcados 1), acha os
    // componentes internos e fica com o de maior área.
    var bestArea = 0;
    var bestMinX = 0, bestMinY = 0, bestMaxX = 0, bestMaxY = 0;
    final visited = Uint8List(sw * sh);
    for (var start = 0; start < grid.length; start++) {
      if (grid[start] != 1 || visited[start] != 0) continue;

      var area = 0;
      var minX = start % sw, maxX = minX, minY = start ~/ sw, maxY = minY;
      final component = <int>[start];
      visited[start] = 1;
      var i = 0;
      while (i < component.length) {
        final idx = component[i++];
        final x = idx % sw;
        final y = idx ~/ sw;
        area++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;

        void visit(int nx, int ny) {
          if (nx < 0 || ny < 0 || nx >= sw || ny >= sh) return;
          final ni = ny * sw + nx;
          if (grid[ni] == 1 && visited[ni] == 0) {
            visited[ni] = 1;
            component.add(ni);
          }
        }

        visit(x - 1, y);
        visit(x + 1, y);
        visit(x, y - 1);
        visit(x, y + 1);
      }

      if (area > bestArea) {
        bestArea = area;
        bestMinX = minX;
        bestMinY = minY;
        bestMaxX = maxX;
        bestMaxY = maxY;
      }
    }

    if (bestArea == 0) {
      throw ImportedFrameException(
        'Não encontramos uma área transparente nessa imagem. Abra num '
        'editor de imagem e apague o centro da tela antes de importar.',
      );
    }

    final totalArea = sw * sh;
    final bboxWidth = bestMaxX - bestMinX + 1;
    final bboxHeight = bestMaxY - bestMinY + 1;
    final fraction = (bboxWidth * bboxHeight) / totalArea;
    if (fraction < 0.05) {
      throw ImportedFrameException(
        'A área transparente dessa imagem é pequena demais para servir de '
        'janela de vídeo.',
      );
    }
    if (fraction > 0.90) {
      throw ImportedFrameException(
        'A área transparente dessa imagem é grande demais — ela não parece '
        'ter uma moldura ao redor.',
      );
    }

    return NormalizedRect(
      bestMinX / sw,
      bestMinY / sh,
      bboxWidth / sw,
      bboxHeight / sh,
    );
  }

  /// Apaga [path] se existir, de melhor esforço: o arquivo pode já ter
  /// sumido por uma condição de corrida, e isso não deve impedir o
  /// metadado de ser limpo em [remove].
  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Melhor esforço — segue sem o arquivo.
    }
  }
}
