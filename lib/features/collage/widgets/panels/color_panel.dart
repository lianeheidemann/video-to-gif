import 'package:flutter/material.dart';

import '../../../../core/ui/color_adjust_controls.dart';
import '../../models/collage_settings.dart';
import 'collage_panel_actions.dart';

/// Ajuste de cor de todas as fotos de uma vez. Mexe só no que é foto —
/// `CollageCellSettings` guarda os valores e o filtro de cor sai deles no
/// desenho da imagem da célula (ver `collage_painter.dart`), então fundo,
/// borda, stickers e texto ficam de fora por construção.
///
/// Os valores mostrados vêm da célula de referência
/// ([CollageSettings.cellStyleTemplate]), a mesma lógica das abas "Borda e
/// cantos" e "Fundo" quando o alvo é "Fotos": os controles aplicam em lote,
/// então uma célula representa todas.
class CollageColorPanel extends StatelessWidget {
  const CollageColorPanel({
    super.key,
    required this.settings,
    required this.actions,
  });

  final CollageSettings settings;
  final CollagePanelActions actions;

  @override
  Widget build(BuildContext context) {
    final reference = settings.cellStyleTemplate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ColorAdjustPanel(
          hasAdjustments: settings.cells.any((c) => c.hasColorAdjustments),
          valueOf: (adjustment) => adjustment.valueOf(reference),
          onChangeStart: actions.pushUndoCheckpoint,
          onChanged: (adjustment, value) => actions.update(
            settings.updatingAllCells((c) => adjustment.apply(c, value)),
            pushUndo: false,
          ),
          onReset: () {
            actions.pushUndoCheckpoint();
            actions.update(
              settings.updatingAllCells((c) => c.withoutColorAdjustments()),
              pushUndo: false,
            );
          },
        ),
      ],
    );
  }
}
