import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import '../color_picker_sheet.dart';

/// Abre a folha de cor da Montagem (swatches + conta-gotas na prévia atual +
/// roda HSV completa) para um seletor de cor de moldura.
///
/// O checkpoint de desfazer entra na primeira cor escolhida, não na abertura
/// do painel nem a cada mexida da roda HSV/conta-gotas: sem isso, arrastar
/// pela roda empilharia um passo de desfazer por quadro.
void showFrameColorPicker({
  required BuildContext context,
  required String title,
  required Color selectedColor,
  required ValueChanged<Color> onSelected,
  required VoidCallback onFirstChange,
  required Future<ui.Image> Function() previewImageBuilder,
}) {
  var checkpointPushed = false;
  showCollageColorPickerSheet(
    context: context,
    title: title,
    initialColor: selectedColor,
    onColorSelected: (color) {
      if (!checkpointPushed) {
        checkpointPushed = true;
        onFirstChange();
      }
      onSelected(color);
    },
    previewImageBuilder: previewImageBuilder,
  );
}

/// Rasteriza o que está desenhado sob [previewKey] para o conta-gotas da
/// folha de cor poder amostrar um pixel da prévia.
Future<ui.Image> renderPreviewImage(
  BuildContext context,
  GlobalKey previewKey,
) async {
  final renderObject = previewKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError('Prévia indisponível para o conta-gotas.');
  }
  return renderObject.toImage(
    pixelRatio: MediaQuery.of(context).devicePixelRatio,
  );
}
