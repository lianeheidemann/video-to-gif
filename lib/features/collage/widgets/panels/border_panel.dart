import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/ui/color_picker_sheet.dart';
import '../../../../core/ui/panel_rows.dart';
import '../../models/collage_cell.dart';
import '../../models/collage_settings.dart';
import '../target_sub_panel.dart';
import 'collage_panel_actions.dart';

/// Painel da aba "Borda e cantos": espessura, arredondamento e cor, valendo
/// para o alvo escolhido no seletor "Montagem"/"Fotos".
///
/// [firstCell] é a célula de referência: com o alvo em "Fotos" os controles
/// mexem em todas as células de uma vez, então a primeira representa bem
/// todas. [targetsPhotos] mora na tela para sobreviver à troca de aba.
class CollageBorderPanel extends StatelessWidget {
  const CollageBorderPanel({
    super.key,
    required this.settings,
    required this.actions,
    required this.targetsPhotos,
    required this.onTargetChanged,
    required this.firstCell,
    required this.previewImageBuilder,
  });

  final CollageSettings settings;
  final CollagePanelActions actions;
  final bool targetsPhotos;
  final ValueChanged<bool> onTargetChanged;
  final CollageCellSettings? firstCell;

  /// Rasteriza a prévia atual para o conta-gotas da folha de cor.
  final Future<ui.Image> Function() previewImageBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetsPhotos = this.targetsPhotos;
    final firstCell = this.firstCell;
    final thickness = targetsPhotos
        ? (firstCell?.borderThicknessAtReference ?? 0)
        : settings.borderThicknessAtReference;
    final maxThickness = targetsPhotos
        ? CollageCellSettings.maxBorderThickness
        : CollageSettings.maxBorderThickness;
    final cornerRatio = targetsPhotos
        ? (firstCell?.cornerRatio ?? 0)
        : settings.cornerRatio;
    final maxCornerRatio = targetsPhotos
        ? CollageCellSettings.maxCornerRatio
        : CollageSettings.maxCornerRatio;
    final borderColor = targetsPhotos
        ? (firstCell?.borderColor ?? settings.borderColor)
        : settings.borderColor;
    void applyThickness(double v) {
      if (targetsPhotos) {
        actions.update(
          settings.updatingAllCells(
            (c) => c.copyWith(borderThicknessAtReference: v),
          ),
          pushUndo: false,
        );
      } else {
        actions.update(
          settings.copyWith(borderThicknessAtReference: v),
          pushUndo: false,
        );
      }
    }

    void applyCornerRatio(double v) {
      if (targetsPhotos) {
        actions.update(
          settings.updatingAllCells((c) => c.copyWith(cornerRatio: v)),
          pushUndo: false,
        );
      } else {
        actions.update(settings.copyWith(cornerRatio: v), pushUndo: false);
      }
    }

    void applyBorderColor(Color color) {
      if (targetsPhotos) {
        actions.update(
          settings.updatingAllCells((c) => c.copyWith(borderColor: color)),
          pushUndo: false,
        );
      } else {
        actions.update(settings.copyWith(borderColor: color), pushUndo: false);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Espessura, arredondamento e cor valem para o alvo escolhido em
        // cima (a montagem inteira ou todas as fotos), então ficam dentro da
        // caixa dele — ver [TargetSubPanel].
        TargetSubPanel(
          options: const ['Montagem', 'Fotos'],
          selectedIndex: targetsPhotos ? 1 : 0,
          onSelected: (index) => onTargetChanged(index == 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PanelSliderRow(
                onChangeStart: actions.pushUndoCheckpoint,
                label: 'Espessura da borda',
                value: thickness,
                min: 0,
                max: maxThickness,
                valueLabel: '${thickness.round()}px',
                onChanged: applyThickness,
              ),
              const SizedBox(height: 12),
              PanelSliderRow(
                onChangeStart: actions.pushUndoCheckpoint,
                label: 'Arredondamento dos cantos',
                value: cornerRatio,
                min: 0,
                max: maxCornerRatio,
                valueLabel: '${(cornerRatio / maxCornerRatio * 100).round()}%',
                onChanged: applyCornerRatio,
              ),
              if (thickness > 0) ...[
                const SizedBox(height: 4),
                Divider(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
                PanelColorRow(
                  label: 'Cor da borda',
                  color: borderColor,
                  onTap: () => _pickBorderColor(
                    context,
                    current: borderColor,
                    onSelected: applyBorderColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Cor da borda — [current]/[onSelected] deixam esta mesma folha servir a
  /// borda da montagem inteira ou a borda de todas as fotos de uma vez,
  /// dependendo do alvo escolhido no seletor "Montagem"/"Fotos".
  void _pickBorderColor(
    BuildContext context, {
    required Color current,
    required ValueChanged<Color> onSelected,
  }) {
    // O checkpoint entra na primeira cor escolhida, não na abertura do painel:
    // abrir e fechar sem escolher nada não pode deixar um passo de desfazer
    // que aparenta não fazer nada.
    var checkpointPushed = false;
    showCollageColorPickerSheet(
      context: context,
      title: 'Cor da borda',
      initialColor: current,
      onColorSelected: (color) {
        if (!checkpointPushed) {
          checkpointPushed = true;
          actions.pushUndoCheckpoint();
        }
        onSelected(color);
      },
      previewImageBuilder: previewImageBuilder,
    );
  }
}
