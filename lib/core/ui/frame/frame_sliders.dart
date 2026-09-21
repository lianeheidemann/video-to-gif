import 'package:flutter/material.dart';

import '../../models/frame_settings.dart';

/// Linha de slider das telas de moldura: rótulo à esquerda, valor em
/// destaque à direita e o slider embaixo.
///
/// [onChangeStart] marca o ponto de desfazer no começo do gesto, e
/// [onChanged] aplica sem empilhar — senão cada frame do arrasto viraria um
/// passo separado na pilha.
class FrameSliderRow extends StatelessWidget {
  const FrameSliderRow({
    super.key,
    this.sliderKey,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChangeStart,
    required this.onChanged,
  });

  final Key? sliderKey;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
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
          value: value,
          label: valueLabel,
          onChangeStart: (_) => onChangeStart(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Espessura da borda da moldura procedural, em pixels na resolução de
/// referência.
class FrameThicknessRow extends StatelessWidget {
  const FrameThicknessRow({
    super.key,
    required this.frame,
    required this.onChangeStart,
    required this.onChanged,
  });

  final FrameSettings frame;
  final VoidCallback onChangeStart;
  final ValueChanged<FrameSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final thickness = frame.thicknessAtReference.clamp(0, 24).toDouble();
    return FrameSliderRow(
      label: 'Espessura da borda',
      valueLabel: '${thickness.round()}px',
      value: thickness,
      min: 0,
      max: 24,
      divisions: 24,
      onChangeStart: onChangeStart,
      onChanged: (v) => onChanged(frame.copyWith(thicknessAtReference: v)),
    );
  }
}

/// Arredondamento dos cantos: no mínimo o canto é reto; no máximo
/// ([FrameSettings.maxCornerRatio]) a moldura fica completamente arredondada.
/// O valor aparece como porcentagem desse máximo, não em pixels — o
/// arredondamento é proporcional ao canvas, não absoluto.
class CornerRadiusRow extends StatelessWidget {
  const CornerRadiusRow({
    super.key,
    required this.frame,
    required this.onChangeStart,
    required this.onChanged,
  });

  final FrameSettings frame;
  final VoidCallback onChangeStart;
  final ValueChanged<FrameSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    const max = FrameSettings.maxCornerRatio;
    final ratio = frame.cornerRatio.clamp(0.0, max).toDouble();
    return FrameSliderRow(
      label: 'Arredondamento dos cantos',
      valueLabel: '${(ratio / max * 100).round()}%',
      value: ratio,
      min: 0,
      max: max,
      divisions: 25,
      onChangeStart: onChangeStart,
      onChanged: (v) => onChanged(frame.copyWith(cornerRatio: v)),
    );
  }
}

/// Zoom do conteúdo dentro da moldura de imagem.
class ContentZoomRow extends StatelessWidget {
  const ContentZoomRow({
    super.key,
    required this.frame,
    required this.onChangeStart,
    required this.onChanged,
  });

  final FrameSettings frame;
  final VoidCallback onChangeStart;
  final ValueChanged<FrameSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final zoom = frame.contentZoom
        .clamp(FrameSettings.minContentZoom, FrameSettings.maxContentZoom)
        .toDouble();
    final percent = (zoom * 100).round();
    return FrameSliderRow(
      sliderKey: const ValueKey('frameContentZoomSlider'),
      label: 'Zoom do conteúdo',
      valueLabel: '$percent%',
      value: zoom,
      min: FrameSettings.minContentZoom,
      max: FrameSettings.maxContentZoom,
      divisions: 58,
      onChangeStart: onChangeStart,
      onChanged: (v) => onChanged(frame.copyWith(contentZoom: v)),
    );
  }
}
