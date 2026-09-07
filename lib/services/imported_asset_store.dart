import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Erro ao importar um sticker ou uma imagem de fundo próprios — mensagem já
/// pronta em português para mostrar ao usuário.
class ImportedAssetException implements Exception {
  ImportedAssetException(this.message);

  final String message;

  @override
  String toString() => 'ImportedAssetException: $message';
}

/// Para quê o arquivo importado vai servir — decide a chave de preferências,
/// a subpasta e quais extensões o seletor de arquivos aceita. Ao contrário de
/// `ImportedFrameStore` (que exige SVG e detecta uma janela transparente por
/// flood-fill), stickers e imagens de fundo não têm "janela": só precisam de
/// um arquivo e da proporção nativa, então os dois compartilham esta mesma
/// implementação em vez de duplicar a lógica de import/persistência.
enum ImportedAssetKind {
  sticker('importedStickers', 'imported_stickers', true),
  backgroundImage('importedBackgroundImages', 'imported_backgrounds', false);

  const ImportedAssetKind(this._prefsKey, this._folderName, this.allowsSvg);

  final String _prefsKey;
  final String _folderName;

  /// Fundo customizado é sempre uma foto (raster); stickers também aceitam
  /// SVG, reaproveitando o mesmo pipeline de rasterização vetorial já usado
  /// para molduras de imagem.
  final bool allowsSvg;
}

/// Um arquivo importado pelo usuário (sticker ou imagem de fundo), já
/// copiado para a pasta de dados do app e com a proporção nativa resolvida.
class ImportedAsset {
  const ImportedAsset({
    required this.id,
    required this.label,
    required this.filePath,
    required this.isVector,
    required this.nativeAspectRatio,
  });

  final String id;
  final String label;
  final String filePath;
  final bool isVector;
  final double nativeAspectRatio;
}

/// Importa e persiste stickers/imagens de fundo escolhidos pelo usuário no
/// aparelho — generaliza o padrão (seletor de arquivo → copia para a pasta
/// de dados do app → persiste metadados em `SharedPreferences`) já usado por
/// `ImportedFrameStore`, sem alterar aquele arquivo (sua detecção de janela
/// por flood-fill continua específica de molduras).
class ImportedAssetStore {
  const ImportedAssetStore(this.kind);

  final ImportedAssetKind kind;

  Future<ImportedAsset> import() async {
    final picked = await FilePicker.pickFile(
      type: kind.allowsSvg ? FileType.custom : FileType.image,
      allowedExtensions: kind.allowsSvg
          ? const ['svg', 'png', 'jpg', 'jpeg', 'webp']
          : null,
      dialogTitle: kind == ImportedAssetKind.sticker
          ? 'Escolha uma imagem para o sticker'
          : 'Escolha uma imagem de fundo',
    );
    final path = picked?.path;
    if (path == null) {
      throw ImportedAssetException('Nenhum arquivo selecionado.');
    }

    final isVector = path.toLowerCase().endsWith('.svg');
    final double aspectRatio;
    if (isVector) {
      aspectRatio = await _svgAspectRatio(path);
    } else {
      aspectRatio = await _rasterAspectRatio(path);
    }

    final supportDir = await getApplicationSupportDirectory();
    final assetsDir = Directory('${supportDir.path}/${kind._folderName}');
    await assetsDir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final extension = isVector ? 'svg' : _extensionOf(path);
    final destPath = '${assetsDir.path}/$stamp.$extension';
    await File(path).copy(destPath);

    final rawLabel = picked!.name;
    final dot = rawLabel.lastIndexOf('.');
    final label = (dot > 0 ? rawLabel.substring(0, dot) : rawLabel).trim();

    final asset = ImportedAsset(
      id: '${kind.name}_$stamp',
      label: label.isEmpty ? 'Importado' : label,
      filePath: destPath,
      isVector: isVector,
      nativeAspectRatio: aspectRatio,
    );

    await _persistAppend(asset);
    return asset;
  }

  Future<List<ImportedAsset>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kind._prefsKey) ?? const [];
    final assets = <ImportedAsset>[];
    for (final entry in raw) {
      final asset = _decode(entry);
      if (asset == null) continue;
      if (!File(asset.filePath).existsSync()) continue;
      assets.add(asset);
    }
    return assets;
  }

  Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kind._prefsKey) ?? const [];
    final kept = <String>[];
    for (final entry in raw) {
      final asset = _decode(entry);
      if (asset != null && asset.id == id) {
        final file = File(asset.filePath);
        if (file.existsSync()) await file.delete();
        continue;
      }
      kept.add(entry);
    }
    await prefs.setStringList(kind._prefsKey, kept);
  }

  Future<void> _persistAppend(ImportedAsset asset) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kind._prefsKey) ?? const [];
    await prefs.setStringList(kind._prefsKey, [...raw, _encode(asset)]);
  }

  String _encode(ImportedAsset asset) => jsonEncode({
    'id': asset.id,
    'label': asset.label,
    'filePath': asset.filePath,
    'isVector': asset.isVector,
    'aspect': asset.nativeAspectRatio,
  });

  ImportedAsset? _decode(String entry) {
    try {
      final map = jsonDecode(entry) as Map<String, dynamic>;
      return ImportedAsset(
        id: map['id'] as String,
        label: map['label'] as String,
        filePath: map['filePath'] as String,
        isVector: map['isVector'] as bool,
        nativeAspectRatio: (map['aspect'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<double> _svgAspectRatio(String path) async {
    try {
      final pictureInfo = await vg.loadPicture(SvgFileLoader(File(path)), null);
      try {
        final size = pictureInfo.size;
        if (size.width <= 0 || size.height <= 0) {
          throw ImportedAssetException('Este SVG não tem um tamanho válido.');
        }
        return size.width / size.height;
      } finally {
        pictureInfo.picture.dispose();
      }
    } on ImportedAssetException {
      rethrow;
    } catch (_) {
      throw ImportedAssetException('Não foi possível ler este arquivo como SVG.');
    }
  }

  Future<double> _rasterAspectRatio(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        if (image.width <= 0 || image.height <= 0) {
          throw ImportedAssetException('Esta imagem não tem um tamanho válido.');
        }
        return image.width / image.height;
      } finally {
        image.dispose();
      }
    } on ImportedAssetException {
      rethrow;
    } catch (_) {
      throw ImportedAssetException('Não foi possível ler esta imagem.');
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'png';
    return path.substring(dot + 1).toLowerCase();
  }
}
