import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/models/crop_rect.dart';
import '../../../core/ui/color_adjust_controls.dart';
import '../../../core/ui/crop/photo_crop_page.dart';
import '../models/collage_cell.dart';
import '../models/collage_settings.dart';
import 'panels/collage_panel_actions.dart';

/// Ações de uma célula da montagem: o menu de contexto e o que cada item
/// dele faz — substituir a foto, trocar com outra célula, recortar, ajustar
/// cor, girar, espelhar e recentralizar.
///
/// [settings] é um getter, não um valor: as folhas abertas aqui sobrevivem a
/// vários rebuilds e releem as configurações a cada um — a de ajuste de cor
/// mostra o resultado da régua enquanto o dedo ainda está na tela.

void openCollageCellMenu(
  int index,
  BuildContext context, {
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) {
  final cell = settings().cells[index];
  if (!cell.hasPhoto) {
    pickPhotoForCell(index, context, settings: settings, actions: actions);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        // Numa tela baixa (ou com a barra de navegação do sistema
        // ocupando espaço), a lista de itens pode não caber na altura
        // disponível — sem isto o `Column` simplesmente estourava por
        // baixo em vez de rolar (`isScrollControlled: true` deixa a folha
        // crescer até a tela quase inteira antes disso ser preciso).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Substituir foto'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  pickPhotoForCell(
                    index,
                    context,
                    settings: settings,
                    actions: actions,
                  );
                },
              ),
              if (settings().cells.where((c) => c.hasPhoto).length > 1)
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: const Text('Trocar com…'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    openSwapPicker(
                      index,
                      context,
                      settings: settings,
                      actions: actions,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.crop_rounded),
                title: const Text('Recortar'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openCropTool(
                    index,
                    context,
                    settings: settings,
                    actions: actions,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Ajustar cor'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openCellColorAdjust(
                    index,
                    context,
                    settings: settings,
                    actions: actions,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.rotate_90_degrees_ccw_rounded),
                title: const Text('Girar 90°'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  rotateCell(
                    index,
                    context,
                    settings: settings,
                    actions: actions,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.flip_rounded),
                title: const Text('Espelhar horizontal'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  flipCell(
                    index,
                    context,
                    settings: settings,
                    actions: actions,
                    horizontal: true,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.flip_rounded),
                title: const Text('Espelhar vertical'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  flipCell(
                    index,
                    context,
                    settings: settings,
                    actions: actions,
                    horizontal: false,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.center_focus_strong_outlined),
                title: const Text('Recentralizar'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  recenterCell(
                    index,
                    context,
                    settings: settings,
                    actions: actions,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> pickPhotoForCell(
  int index,
  BuildContext context, {
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) async {
  try {
    final picked = await FilePicker.pickFile(
      type: FileType.image,
      dialogTitle: 'Escolha uma foto',
    );
    final path = picked?.path;
    if (path == null) return;

    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final int width;
    final int height;
    try {
      final frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      frame.image.dispose();
    } finally {
      codec.dispose();
    }

    final cell = settings().cells[index];
    // O estilo compartilhado entra por cima: uma foto escolhida depois
    // (numa célula que nasceu vazia, antes de a borda/fundo terem sido
    // ajustados) tem que aparecer igual às outras, não com os padrões.
    final replaced = settings().withSharedCellStyle(
      cell
          .copyWith(
            photoPath: path,
            photoWidth: width,
            photoHeight: height,
            clearManualCrop: true,
          )
          .resetFraming(),
    );
    actions.update(settings().replacingCell(index, replaced));
  } catch (_) {
    actions.message('Não foi possível abrir esta foto.');
  }
}

void openSwapPicker(
  int index,
  BuildContext context, {
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        // Uma montagem com muitas células (grade livre até 9) pode ter
        // miniaturas demais para caber na altura da folha sem rolar.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trocar com qual foto?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < settings().cells.length; i++)
                    if (i != index && settings().cells[i].hasPhoto)
                      GestureDetector(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          actions.update(settings().swappingCells(index, i));
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 62,
                            height: 62,
                            child: Image.file(
                              File(settings().cells[i].photoPath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Folha de ajuste de cor: uma fileira de bolinhas (uma por ajuste, como
/// nos editores de foto), o nome do ajuste escolhido em cima e a régua de
/// intensidade embaixo, com o zero no centro. Cada mexida na régua é
/// aplicada na hora à célula, então a prévia atrás da folha mostra o
/// resultado enquanto o dedo ainda está na tela.
void openCellColorAdjust(
  int index,
  BuildContext context, {
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Sem véu: a régua muda a prévia da montagem em tempo real (ver
    // comentário acima), e uma barreira escura por trás escondia
    // exatamente o resultado que essa mexida deveria mostrar.
    barrierColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, sheetSetState) {
          if (index >= settings().cells.length) return const SizedBox.shrink();
          final cell = settings().cells[index];
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ColorAdjustPanel(
                title: 'Ajustar cor',
                hasAdjustments: cell.hasColorAdjustments,
                valueOf: (adjustment) => adjustment.valueOf(cell),
                onChangeStart: actions.pushUndoCheckpoint,
                onChanged: (adjustment, value) {
                  actions.update(
                    settings().replacingCell(
                      index,
                      adjustment.apply(cell, value),
                    ),
                    pushUndo: false,
                  );
                  sheetSetState(() {});
                },
                onReset: () {
                  actions.pushUndoCheckpoint();
                  actions.update(
                    settings().replacingCell(
                      index,
                      cell.withoutColorAdjustments(),
                    ),
                    pushUndo: false,
                  );
                  sheetSetState(() {});
                },
              ),
            ),
          );
        },
      );
    },
  );
}

/// Mais um quarto de volta a partir de onde a foto já estiver — continua
/// útil como atalho rápido mesmo depois de girar livremente com o dedo.
void rotateCell(
  int index,
  BuildContext context, {
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) {
  final cell = settings().cells[index];
  actions.update(
    settings().replacingCell(
      index,
      cell.copyWith(rotation: cell.rotation + math.pi / 2),
    ),
  );
}

void flipCell(
  int index,
  BuildContext context, {
  required bool horizontal,
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) {
  final cell = settings().cells[index];
  actions.update(
    settings().replacingCell(
      index,
      horizontal
          ? cell.copyWith(flipHorizontal: !cell.flipHorizontal)
          : cell.copyWith(flipVertical: !cell.flipVertical),
    ),
  );
}

/// Volta ao enquadramento padrão (deslocamento/zoom/rotação/espelhamento),
/// mantendo foto, recorte manual, cor e borda — o antigo comportamento do
/// duplo toque, agora um item do menu já que o duplo toque passa a
/// alternar preencher/ajustar.
void recenterCell(
  int index,
  BuildContext context, {
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) {
  final cell = settings().cells[index];
  actions.pushUndoCheckpoint();
  actions.update(
    settings().replacingCell(index, cell.resetFraming()),
    pushUndo: false,
  );
}

/// Proporção que a célula [index] tem no layout atual — todas as células de
/// um mesmo layout compartilham a mesma proporção (a grade sempre gera
/// larguras/alturas uniformes), então basta calcular contra um canvas de
/// referência do mesmo formato da montagem (`settings().aspectRatio`) em vez
/// de depender do tamanho real da prévia na tela.
double cellAspectRatioFor(
  int index,
  BuildContext context, {
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) {
  const refWidth = 1000.0;
  final refHeight = refWidth / settings().aspectRatio;
  final rects = settings().layout.cellRectsFor(
    Size(refWidth, refHeight),
    outerMarginRatio: settings().outerMarginRatio,
    innerMarginRatio: settings().innerMarginRatio,
  );
  if (index >= rects.length) return 1.0;
  final rect = rects[index];
  if (rect.width <= 0 || rect.height <= 0) return 1.0;
  return rect.width / rect.height;
}

/// Abre o recorte de uma foto específica. O recorte é livre por padrão (a
/// proporção da célula é só mais uma opção da fileira), então o resultado
/// quase nunca tem a mesma proporção da célula: por isso a foto recortada
/// entra em "encaixar" e com o enquadramento zerado — aparece inteira,
/// centralizada e na horizontal, em vez de ser esticada/cortada pelo
/// "preencher" para caber na célula.
Future<void> openCropTool(
  int index,
  BuildContext context, {
  required CollageSettings Function() settings,
  required CollagePanelActions actions,
}) async {
  final cell = settings().cells[index];
  if (!cell.hasPhoto) return;
  final crop = await Navigator.of(context).push<CropRect>(
    MaterialPageRoute(
      builder: (_) => PhotoCropPage(
        photoPath: cell.photoPath!,
        photoWidth: cell.photoWidth,
        photoHeight: cell.photoHeight,
        cellAspectRatio: cellAspectRatioFor(
          index,
          context,
          settings: settings,
          actions: actions,
        ),
        initialCrop: cell.manualCrop,
      ),
    ),
  );
  if (crop == null || !context.mounted) return;
  actions.pushUndoCheckpoint();
  actions.update(
    settings().replacingCell(
      index,
      cell
          .copyWith(manualCrop: crop, fitMode: CollageCellFitMode.contain)
          .resetFraming(),
    ),
    pushUndo: false,
  );
}
