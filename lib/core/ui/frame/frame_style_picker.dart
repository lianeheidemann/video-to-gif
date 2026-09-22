import 'package:flutter/material.dart';

import '../../models/frame_settings.dart';
import '../../painting/frame_painter.dart';
import 'frame_thumb_shell.dart';

/// Fileira horizontal de miniaturas dos estilos de moldura procedural.
class FrameStylePicker extends StatelessWidget {
  const FrameStylePicker({
    super.key,
    required this.active,
    required this.onSelected,
  });

  final FrameStyle active;
  final ValueChanged<FrameStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: FrameStyle.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final style = FrameStyle.values[index];
          return FrameStyleThumb(
            style: style,
            selected: style == active,
            onTap: () => onSelected(style),
          );
        },
      ),
    );
  }
}

/// Miniatura de um estilo procedural.
class FrameStyleThumb extends StatelessWidget {
  const FrameStyleThumb({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final FrameStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FrameThumbShell(
      key: ValueKey('frameStyleThumb_${style.name}'),
      label: style.label,
      selected: selected,
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: FrameStyleGlyph(
        style: style,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Desenho do estilo dentro da miniatura: a própria moldura pintada pelo
/// [FramePainter], com um retângulo escuro no miolo fazendo as vezes do
/// conteúdo.
class FrameStyleGlyph extends StatelessWidget {
  const FrameStyleGlyph({super.key, required this.style, required this.color});

  final FrameStyle style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (style == FrameStyle.none) {
      return Icon(
        Icons.crop_free_rounded,
        size: 16,
        color: color.withValues(alpha: 0.6),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final outerRadius = style.defaultCornerRatio * size.shortestSide;
        final inset = size.shortestSide * 0.22;
        final innerRadius = (outerRadius - inset).clamp(0.0, outerRadius);
        return Stack(
          children: [
            CustomPaint(
              size: size,
              painter: FramePainter(
                FrameSettings(
                  style: style,
                  color: color,
                  thicknessAtReference: style.defaultThickness,
                  cornerRatio: style.defaultCornerRatio,
                  transparentBackground: true,
                ),
              ),
            ),
            Positioned(
              left: inset,
              top: inset,
              right: inset,
              bottom: inset,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(innerRadius),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Aplica um estilo procedural, trazendo junto a espessura e o
/// arredondamento padrão dele e descartando a moldura de imagem — as duas
/// famílias são exclusivas.
FrameSettings frameWithStyle(FrameSettings frame, FrameStyle style) =>
    frame.copyWith(
      style: style,
      cornerRatio: style.defaultCornerRatio,
      thicknessAtReference: style.defaultThickness,
      clearImageFrame: true,
    );
