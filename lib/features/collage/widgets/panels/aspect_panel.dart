import 'package:flutter/material.dart';

import '../../models/collage_settings.dart';
import '../aspect_ratio_number_input.dart';
import 'collage_panel_actions.dart';

/// Painel da aba "Proporção": os chips de formato pronto, o chip "x:y" da
/// proporção livre, o slider e — só com "x:y" escolhido — os campos de
/// largura e altura.
///
/// [customSelected] mora na tela, não aqui: o chip escolhido tem que
/// sobreviver à troca de aba, e um `StatefulWidget` perderia o valor ao sair
/// e voltar, já que cada aba devolve um widget diferente.
class CollageAspectPanel extends StatelessWidget {
  const CollageAspectPanel({
    super.key,
    required this.settings,
    required this.actions,
    required this.customSelected,
    required this.onCustomSelected,
  });

  final CollageSettings settings;
  final CollagePanelActions actions;
  final bool customSelected;
  final ValueChanged<bool> onCustomSelected;

  @override
  Widget build(BuildContext context) {
    final custom = _isCustom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelValueLine(context, _customAspectLabel()),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in CollageSettings.aspectPresets)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                labelStyle: Theme.of(context).textTheme.bodySmall,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                label: Text(preset.$1),
                // Com "x:y" escolhido, nenhum chip pronto fica marcado —
                // senão dois apareceriam marcados ao mesmo tempo quando os
                // campos formassem justo a proporção de um deles.
                selected:
                    !custom && (settings.aspectRatio - preset.$2).abs() < 0.001,
                onSelected: (_) {
                  onCustomSelected(false);
                  actions.update(settings.copyWith(aspectRatio: preset.$2));
                },
              ),
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              labelStyle: Theme.of(context).textTheme.bodySmall,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              label: const Text('x:y'),
              selected: custom,
              onSelected: (_) => onCustomSelected(true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Slider(
          min: CollageSettings.minAspectRatio,
          max: CollageSettings.maxAspectRatio,
          value: settings.aspectRatio.clamp(
            CollageSettings.minAspectRatio,
            CollageSettings.maxAspectRatio,
          ),
          onChangeStart: (_) => actions.pushUndoCheckpoint(),
          onChanged: (v) => actions.update(
            settings.copyWith(aspectRatio: v),
            pushUndo: false,
          ),
        ),
        // Largura e altura só entram na tela com "x:y" escolhido — antes
        // ficavam sempre lá, ocupando espaço mesmo para quem só queria um
        // dos formatos prontos.
        if (custom) ...[
          const SizedBox(height: 8),
          CustomAspectRatioInput(
            onApply: (ratio) {
              actions.pushUndoCheckpoint();
              actions.update(
                settings.copyWith(
                  aspectRatio: ratio.clamp(
                    CollageSettings.minAspectRatio,
                    CollageSettings.maxAspectRatio,
                  ),
                ),
                pushUndo: false,
              );
            },
          ),
        ],
      ],
    );
  }

  /// "x:y" é o chip da proporção livre: ou o usuário o escolheu, ou a
  /// proporção atual não corresponde a nenhum chip pronto.
  bool get _isCustom => customSelected || _customAspectLabel() != null;

  /// `null` quando a proporção atual bate com um dos chips (o chip
  /// selecionado já mostra esse rótulo — repetir no cabeçalho do painel só
  /// duplicaria o mesmo texto na tela). Só devolve algo para uma proporção
  /// customizada pelo slider, sem chip equivalente para mostrá-la.
  String? _customAspectLabel() {
    for (final preset in CollageSettings.aspectPresets) {
      if ((preset.$2 - settings.aspectRatio).abs() < 0.001) return null;
    }
    return settings.aspectRatio.toStringAsFixed(2);
  }

  /// Valor atual de uma seção, alinhado à direita — sem repetir o nome da
  /// aba: a própria aba do rodapé já fica marcada em cor diferente e em
  /// negrito quando selecionada (`_footerTabButton`), então escrevê-lo de
  /// novo aqui só custava espaço vertical num painel com teto de 200px.
  /// `null` (a maioria das abas, que não tem um valor de resumo) não
  /// desenha nada.
  Widget _panelValueLine(BuildContext context, String? value) {
    if (value == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
