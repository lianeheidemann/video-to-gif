import 'package:flutter/material.dart';

import '../../models/collage_settings.dart';
import 'collage_panel_actions.dart';

/// Painel da aba "Margem": três sliders — tudo, externa e entre fotos — mais
/// o botão de zerar.
///
/// [marginAllValue] é o valor próprio do slider "Tudo", guardado pela tela em
/// vez de recalculado como média a cada rebuild: sem isso, arrastar "Externa"
/// ou "Entre fotos" faria o slider de cima se mexer sozinho. A tela o escreve
/// fora de `setState`, contando com o rebuild do `update` logo em seguida, e
/// por isso as duas mudanças que o tocam saem daqui como callbacks
/// ([onMarginAllChanged] e [onResetMargins]) em vez de passarem por
/// [CollagePanelActions].
class CollageMarginPanel extends StatelessWidget {
  const CollageMarginPanel({
    super.key,
    required this.settings,
    required this.actions,
    required this.marginAllValue,
    required this.onMarginAllChanged,
    required this.onResetMargins,
  });

  final CollageSettings settings;
  final CollagePanelActions actions;
  final double marginAllValue;
  final ValueChanged<double> onMarginAllChanged;
  final VoidCallback onResetMargins;

  @override
  Widget build(BuildContext context) {
    final outer = settings.outerMarginRatio;
    final inner = settings.innerMarginRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // As três de uma vez, uma embaixo da outra: antes eram chips que
        // trocavam qual delas o único slider controlava, então ver a margem
        // externa e a de entre fotos ao mesmo tempo era impossível.
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _marginRow(
                    context,
                    icon: Icons.border_all_rounded,
                    label: 'Tudo',
                    // Valor próprio (ver [marginAllValue]) — não recalcula
                    // a média a cada rebuild, então arrastar "Externa"/
                    // "Entre fotos" não move este slider.
                    value: marginAllValue,
                    onChanged: onMarginAllChanged,
                  ),
                  _marginRow(
                    context,
                    icon: Icons.border_outer_rounded,
                    label: 'Externa',
                    value: outer,
                    onChanged: (v) => actions.update(
                      settings.copyWith(outerMarginRatio: v),
                      pushUndo: false,
                    ),
                  ),
                  _marginRow(
                    context,
                    icon: Icons.border_inner_rounded,
                    label: 'Entre fotos',
                    value: inner,
                    onChanged: (v) => actions.update(
                      settings.copyWith(innerMarginRatio: v),
                      pushUndo: false,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Zerar margens',
              onPressed: outer == 0 && inner == 0 ? null : onResetMargins,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ],
    );
  }

  /// Uma linha da aba "Margem": ícone, slider e o valor em porcentagem. O
  /// nome fica no tooltip do ícone — escrito por extenso, as três linhas não
  /// caberiam sem espremer o slider.
  Widget _marginRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    final clamped = value.clamp(
      CollageSettings.minMarginRatio,
      CollageSettings.maxMarginRatio,
    );
    final percent = (clamped / CollageSettings.maxMarginRatio * 100).round();
    return Row(
      children: [
        Tooltip(
          message: label,
          child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: Slider(
            min: CollageSettings.minMarginRatio,
            max: CollageSettings.maxMarginRatio,
            value: clamped,
            label: '$percent%',
            onChangeStart: (_) => actions.pushUndoCheckpoint(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$percent%',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
