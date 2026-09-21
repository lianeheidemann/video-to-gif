import 'package:flutter/material.dart';

/// Linha de slider dos painéis de edição: rótulo à esquerda, valor em
/// destaque à direita e o slider embaixo.
///
/// [onChangeStart] marca o ponto de desfazer no começo do gesto, e
/// [onChanged] aplica sem empilhar — senão cada frame do arrasto viraria um
/// passo separado na pilha.
class PanelSliderRow extends StatelessWidget {
  const PanelSliderRow({
    super.key,
    this.sliderKey,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChangeStart,
    required this.onChanged,
  });

  final Key? sliderKey;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;

  /// `null` deixa o slider contínuo.
  final int? divisions;

  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              valueLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          key: sliderKey,
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          label: valueLabel,
          onChangeStart: (_) => onChangeStart(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Linha de liga/desliga no estilo dos painéis do rodapé.
///
/// Um `SwitchListTile` aqui dispara o aviso do Material de "fundo/ink
/// invisível" (o painel já tem cor de fundo própria) — e o visual ficaria
/// diferente das outras linhas.
class PanelSwitchRow extends StatelessWidget {
  const PanelSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Linha de cor: rótulo à esquerda e a bolinha da cor atual à direita,
/// abrindo a folha de cor ao tocar.
class PanelColorRow extends StatelessWidget {
  const PanelColorRow({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                  width: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
