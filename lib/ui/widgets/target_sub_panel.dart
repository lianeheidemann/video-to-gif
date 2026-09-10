import 'package:flutter/material.dart';

/// Seletor de alvo ("Montagem"/"Fotos") com os controles daquele alvo dentro
/// de uma caixa própria, ligada à opção escolhida por um bico.
///
/// Sem isso, os controles ficavam soltos logo abaixo dos chips e pareciam do
/// mesmo nível deles — mas "Transparente/Cor/Imagem" (ou a espessura da
/// borda) configuram *o alvo selecionado em cima*, não a aba inteira.
///
/// O bico é desenhado dentro da própria coluna do chip selecionado, então ele
/// fica alinhado sem medir nada em tempo de execução (nada de `GlobalKey` nem
/// `addPostFrameCallback`): quem escolhe a posição é o próprio layout da
/// linha de chips.
class TargetSubPanel extends StatelessWidget {
  const TargetSubPanel({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
  });

  /// Rótulos das opções de alvo, na ordem em que aparecem.
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Os controles que dependem do alvo — vão dentro da caixa.
  final Widget child;

  static const _notchWidth = 18.0;
  static const _notchHeight = 6.0;
  static const _radius = 14.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.5,
    );
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < options.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  right: i == options.length - 1 ? 0 : 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChoiceChip(
                      label: Text(options[i]),
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      selected: i == selectedIndex,
                      onSelected: (_) => onSelected(i),
                    ),
                    // O bico encosta 1px por cima da borda da caixa, para os
                    // dois lerem como uma peça só em vez de duas.
                    SizedBox(
                      height: _notchHeight,
                      child: i == selectedIndex
                          ? CustomPaint(
                              size: const Size(_notchWidth, _notchHeight),
                              painter: _NotchPainter(
                                fill: fill,
                                border: border,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: border),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// Triângulo do bico: preenchido na cor da caixa, com os dois lados
/// inclinados na cor da borda — a base fica aberta, encostada na borda de
/// cima da caixa, que continua a linha.
class _NotchPainter extends CustomPainter {
  const _NotchPainter({required this.fill, required this.border});

  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(
      Path.from(path)..close(),
      Paint()
        ..color = fill
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_NotchPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.border != border;
}
