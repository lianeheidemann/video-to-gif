import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/services/imported_asset_store.dart';
import '../../../../core/ui/color_picker_sheet.dart';
import '../../../../core/ui/panel_rows.dart';
import '../../models/background_image.dart';
import '../../models/collage_background.dart';
import '../asset_thumbs.dart';
import '../target_sub_panel.dart';

/// Painel da aba "Fundo": transparente, cor ou imagem, valendo para o alvo
/// escolhido no seletor "Montagem"/"Fotos".
///
/// Recebe o fundo do alvo já resolvido em [background] e devolve as mudanças
/// por [onApply] — resolver qual alvo vale, e aplicar na montagem ou em todas
/// as células, fica com a tela, que é quem guarda [targetsPhotos]. Importar e
/// remover também: os dois mexem na lista de assets importados, que a tela
/// carrega uma vez e três abas diferentes alteram.
class CollageBackgroundPanel extends StatelessWidget {
  const CollageBackgroundPanel({
    super.key,
    required this.targetBackground,
    required this.targetsPhotos,
    required this.onTargetChanged,
    required this.importedBackgrounds,
    required this.onApply,
    required this.onImport,
    required this.onRemoveImported,
    required this.onPushUndoCheckpoint,
    required this.previewImageBuilder,
  });

  /// Fundo do alvo selecionado — o da montagem, ou o da célula de referência.
  final CollageBackground targetBackground;

  final bool targetsPhotos;
  final ValueChanged<bool> onTargetChanged;
  final List<ImportedAsset> importedBackgrounds;
  final void Function(CollageBackground background, {bool pushUndo}) onApply;
  final VoidCallback onImport;
  final ValueChanged<ImportedAsset> onRemoveImported;
  final VoidCallback onPushUndoCheckpoint;

  /// Rasteriza a prévia atual para o conta-gotas da folha de cor.
  final Future<ui.Image> Function() previewImageBuilder;

  @override
  Widget build(BuildContext context) {
    final background = targetBackground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // O fundo da montagem (a área fora/entre as fotos) e o fundo de
        // dentro de cada foto (o que aparece na sobra do modo "encaixar") são
        // escolhas independentes — mesmo seletor de alvo da aba "Borda e
        // cantos". Transparente/Cor/Imagem valem para o alvo escolhido, por
        // isso ficam dentro da caixa dele (ver [TargetSubPanel]).
        TargetSubPanel(
          options: const ['Montagem', 'Fotos'],
          selectedIndex: targetsPhotos ? 1 : 0,
          onSelected: (index) => onTargetChanged(index == 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `ChoiceChip`s em vez de `SegmentedButton`: os 3 rótulos
              // ("Transparente" principalmente) não cabem lado a lado com
              // ícone dentro da largura do painel do rodapé sem quebrar linha
              // dentro do próprio botão — chip quebra para a linha de baixo
              // inteiro, nunca no meio de uma palavra.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final entry in const [
                    (
                      CollageBackgroundMode.transparent,
                      'Transparente',
                      Icons.check_box_outline_blank_rounded,
                    ),
                    (
                      CollageBackgroundMode.color,
                      'Cor',
                      Icons.palette_outlined,
                    ),
                    (
                      CollageBackgroundMode.image,
                      'Imagem',
                      Icons.image_outlined,
                    ),
                  ])
                    ChoiceChip(
                      avatar: Icon(entry.$3, size: 15),
                      label: Text(entry.$2),
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      selected: background.mode == entry.$1,
                      onSelected: (_) =>
                          onApply(background.copyWith(mode: entry.$1)),
                    ),
                ],
              ),
              if (background.mode == CollageBackgroundMode.color) ...[
                const SizedBox(height: 8),
                PanelColorRow(
                  label: 'Cor do fundo',
                  color: background.color,
                  onTap: () => _openBackgroundColorPicker(context),
                ),
              ],
              if (background.mode == CollageBackgroundMode.image) ...[
                const SizedBox(height: 12),
                _backgroundImagePicker(context),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _backgroundImagePicker(BuildContext context) {
    // Os fundos prontos vêm primeiro, depois os importados e por último o
    // "Importar" — mesma ordem dos stickers, onde os do app também abrem a
    // lista.
    const bundled = BackgroundImageLibrary.bundled;

    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: bundled.length + importedBackgrounds.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index < bundled.length) {
            final background = bundled[index];
            return GestureDetector(
              // Sem onLongPress: fundo que vem com o app não se remove, ao
              // contrário dos importados.
              onTap: () => onApply(
                targetBackground.copyWith(
                  mode: CollageBackgroundMode.image,
                  imagePath: background.assetPath,
                ),
              ),
              child: _bundledBackgroundThumb(
                context,
                background,
                selected: targetBackground.imagePath == background.assetPath,
              ),
            );
          }

          final importedIndex = index - bundled.length;
          if (importedIndex == importedBackgrounds.length) {
            return ImportAssetTile(onTap: onImport, label: 'Importar');
          }
          final asset = importedBackgrounds[importedIndex];
          final selected = targetBackground.imagePath == asset.filePath;
          return GestureDetector(
            onTap: () => onApply(
              targetBackground.copyWith(
                mode: CollageBackgroundMode.image,
                imagePath: asset.filePath,
              ),
            ),
            onLongPress: () => onRemoveImported(asset),
            child: ImportedAssetThumb(asset: asset, selected: selected),
          );
        },
      ),
    );
  }

  void _openBackgroundColorPicker(BuildContext context) {
    // Mesmo cuidado de [_pickBorderColor] com o histórico de desfazer.
    var checkpointPushed = false;
    showCollageColorPickerSheet(
      context: context,
      title: 'Cor do fundo',
      initialColor: targetBackground.color,
      onColorSelected: (color) {
        if (!checkpointPushed) {
          checkpointPushed = true;
          onPushUndoCheckpoint();
        }
        onApply(
          targetBackground.copyWith(
            mode: CollageBackgroundMode.color,
            color: color,
          ),
          pushUndo: false,
        );
      },
      previewImageBuilder: previewImageBuilder,
    );
  }

  /// Miniatura de um fundo pronto do app — mesma moldura de [ImportedAssetThumb],
  /// mas lendo de asset e preenchendo o quadro (`cover`), que é como a foto
  /// vai aparecer no fundo de verdade.
  Widget _bundledBackgroundThumb(
    BuildContext context,
    BundledBackground background, {
    required bool selected,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: 62,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 2 : 1,
        ),
      ),
      child: Image.asset(
        background.assetPath,
        fit: BoxFit.cover,
        semanticLabel: background.label,
      ),
    );
  }
}
