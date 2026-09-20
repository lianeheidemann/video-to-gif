import 'package:flutter_svg/flutter_svg.dart';

import '../models/image_frame.dart';
import 'bundled_assets.dart';
import 'imported_frame_store.dart';

/// Molduras de imagem oferecidas pelo app, preenchida no `main()`.
///
/// Começa com o que [ImageFrameLibrary.bundled] traz, para a lista existir
/// mesmo antes da varredura terminar.
var bundledImageFrames = ImageFrameLibrary.bundled;

/// Monta a lista de molduras a partir de `assets/frame`, em vez de depender
/// só da lista escrita à mão.
///
/// Para cada SVG da pasta:
/// - se [ImageFrameLibrary.bundled] já descreve aquele caminho, usa a
///   entrada curada, que tem o nome curto e a janela tirada à mão da
///   geometria do próprio SVG — mais exata que qualquer detecção;
/// - se não, mede o arquivo com [measureSvgFrame], a mesma detecção de
///   janela usada quando o usuário importa uma moldura do aparelho, e tira o
///   nome do nome do arquivo.
///
/// Assim, soltar um SVG em `assets/frame` e gerar o APK basta para a moldura
/// aparecer, e as que já existiam não perdem o acabamento.
Future<List<ImageFrameAsset>> loadBundledImageFrames() async {
  final curadas = {
    for (final frame in ImageFrameLibrary.bundled) frame.svgAssetPath!: frame,
  };

  final paths = await BundledAssets.list('assets/frame/', extensions: {'svg'});

  final frames = <ImageFrameAsset>[];
  for (final path in paths) {
    final curada = curadas[path];
    if (curada != null) {
      frames.add(curada);
      continue;
    }
    final descoberta = await _describe(path);
    // SVG ilegível é pulado em silêncio: um arquivo quebrado na pasta não
    // pode tirar as outras molduras do app.
    if (descoberta != null) frames.add(descoberta);
  }

  // As curadas primeiro, na ordem em que foram escritas; as achadas depois,
  // em ordem alfabética, que é a ordem do nome do arquivo.
  frames.sort((a, b) {
    final ia = ImageFrameLibrary.bundled.indexWhere((f) => f.id == a.id);
    final ib = ImageFrameLibrary.bundled.indexWhere((f) => f.id == b.id);
    if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
    if (ia >= 0) return -1;
    if (ib >= 0) return 1;
    return a.svgAssetPath!.compareTo(b.svgAssetPath!);
  });
  return frames;
}

Future<ImageFrameAsset?> _describe(String assetPath) async {
  try {
    final medida = await measureSvgFrame(SvgAssetLoader(assetPath));
    return ImageFrameAsset(
      // Derivado do caminho e não de um contador: o id precisa ser o mesmo
      // entre execuções, senão a moldura escolhida mudaria a cada abertura.
      id: 'asset_$assetPath',
      label: labelFromFileName(assetPath),
      source: ImageFrameSource.bundledSvg,
      svgAssetPath: assetPath,
      nativeAspectRatio: medida.aspectRatio,
      nativeReferenceWidth: medida.nativeWidth,
      contentRect: medida.contentRect,
    );
  } catch (_) {
    return null;
  }
}
