import 'package:flutter/material.dart';

import '../../models/collage_color_adjustment.dart';

/// Bolinha de um ajuste na folha "Ajustar cor": ícone dentro de um círculo,
/// nome embaixo e um ponto de destaque quando aquele ajuste está fora do
/// neutro — assim dá para ver de relance o que já foi mexido sem abrir cada
/// um.
class ColorAdjustButton extends StatelessWidget {
  const ColorAdjustButton({
    super.key,
    required this.adjustment,
    required this.selected,
    required this.value,
    required this.onTap,
    this.onDoubleTap,
  });

  final CollageColorAdjustment adjustment;
  final bool selected;
  final double value;
  final VoidCallback onTap;

  /// Duplo toque zera este ajuste específico — mesmo atalho que a régua de
  /// intensidade já oferece, só que sem precisar selecionar o ajuste antes.
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touched = value != 0;
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: touched && !selected
                    ? Border.all(color: theme.colorScheme.primary, width: 2)
                    : null,
              ),
              child: Icon(
                adjustment.icon,
                size: 22,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              adjustment.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão de zerar todos os ajustes de uma vez, no fim da fileira de
/// ícones — depois das opções, e não acima delas como antes. Mesma forma de
/// [ColorAdjustButton] (círculo + rótulo embaixo), só com o ícone de
/// "redefinir" em vez de um ajuste, para entrar na fileira sem destoar.
class _ResetAllButton extends StatelessWidget {
  const _ResetAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.refresh_rounded,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Redefinir',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fileira de ajustes + régua de intensidade: o conteúdo de "Ajustar cor",
/// sem saber sobre o que ele age. A tela passa como ler e como gravar cada
/// valor, então o mesmo painel serve para uma foto da montagem, para todas
/// elas de uma vez, para a moldura e para o GIF.
///
/// A seleção do ajuste é estado só de tela (qual bolinha está aberta), por
/// isso mora aqui e não sobe para quem chamou.
class ColorAdjustPanel extends StatefulWidget {
  const ColorAdjustPanel({
    super.key,
    required this.valueOf,
    required this.onChanged,
    required this.onChangeStart,
    required this.onReset,
    required this.hasAdjustments,
    this.title,
  });

  final double Function(CollageColorAdjustment adjustment) valueOf;
  final void Function(CollageColorAdjustment adjustment, double value)
  onChanged;

  /// Chamado uma vez no início de um arrasto (ou antes de zerar um ajuste),
  /// para o gesto inteiro virar um passo só de desfazer.
  final VoidCallback onChangeStart;

  /// Zera todos os ajustes de uma vez — o botão só aparece com
  /// [hasAdjustments].
  final VoidCallback onReset;
  final bool hasAdjustments;

  /// Cabeçalho opcional: a folha por foto mostra "Ajustar cor" aqui, o painel
  /// de aba não precisa (o rodapé já diz onde está).
  final String? title;

  @override
  State<ColorAdjustPanel> createState() => _ColorAdjustPanelState();
}

class _ColorAdjustPanelState extends State<ColorAdjustPanel> {
  CollageColorAdjustment _current = CollageColorAdjustment.brightness;

  /// Duplo toque num ícone zera só aquele ajuste (mesmo atalho que a régua
  /// tem) e o seleciona, sem gastar um passo de desfazer quando ele já
  /// estava zerado.
  void _reset(CollageColorAdjustment adjustment) {
    if (widget.valueOf(adjustment) != 0) {
      widget.onChangeStart();
      widget.onChanged(adjustment, 0);
    }
    setState(() => _current = adjustment);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(widget.title!, style: theme.textTheme.titleMedium),
          ),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final adjustment in CollageColorAdjustment.values)
                // O Builder dá a cada ícone o próprio BuildContext, que
                // Scrollable.ensureVisible usa para centralizar exatamente
                // esse ícone na fileira ao selecioná-lo — sem isso o ícone
                // escolhido podia ficar escondido perto da borda.
                Builder(
                  builder: (itemContext) {
                    void show() => Scrollable.ensureVisible(
                      itemContext,
                      alignment: 0.5,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                    return ColorAdjustButton(
                      adjustment: adjustment,
                      selected: adjustment == _current,
                      value: widget.valueOf(adjustment),
                      onTap: () {
                        setState(() => _current = adjustment);
                        show();
                      },
                      onDoubleTap: () {
                        _reset(adjustment);
                        show();
                      },
                    );
                  },
                ),
              // Depois das opções, não acima delas — mesmo lugar em botão
              // que "Zerar margens" ocupa na aba "Margem". Só aparece
              // havendo algo para zerar.
              if (widget.hasAdjustments) _ResetAllButton(onTap: widget.onReset),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Sem repetir o nome do ajuste aqui: o ícone escolhido logo acima já
        // fica roxo e com o rótulo em destaque, e a régua mostra só o valor.
        IntensityRuler(
          value: widget.valueOf(_current),
          onChangeStart: widget.onChangeStart,
          onChanged: (value) => widget.onChanged(_current, value),
        ),
      ],
    );
  }
}

/// Régua de intensidade de `-1` a `1`, com o zero no centro: os tracinhos
/// deslizam sob um marcador fixo, e o valor atual aparece em cima. É o
/// controle da referência que a Liane mandou — arrastar para os lados em vez
/// de mirar num "polegar" pequeno, o que dá bem mais precisão no celular.
class IntensityRuler extends StatefulWidget {
  const IntensityRuler({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.ticks = 41,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;

  /// Quantos tracinhos a régua inteira tem (ímpar, para existir um tracinho
  /// exatamente no zero).
  final int ticks;

  @override
  State<IntensityRuler> createState() => _IntensityRulerState();
}

class _IntensityRulerState extends State<IntensityRuler> {
  double? _dragStartValue;

  void _onDragStart(DragStartDetails details) {
    _dragStartValue = widget.value;
    widget.onChangeStart?.call();
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (width <= 0) return;
    // A régua inteira (de -1 a 1) ocupa a largura disponível: arrastar a
    // largura toda vai de um extremo ao outro.
    final delta = -details.primaryDelta! / width * 2;
    final next = ((_dragStartValue ?? widget.value) + delta).clamp(-1.0, 1.0);
    _dragStartValue = next;
    if (next == widget.value) return;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // Em percentual: é como a pessoa pensa a intensidade ("+40%"), e o
          // sinal deixa claro para que lado o ajuste foi.
          '${widget.value > 0 ? '+' : ''}${(widget.value * 100).round()}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: widget.value == 0
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.primary,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: (details) =>
                  _onDragUpdate(details, width),
              onDoubleTap: () {
                widget.onChangeStart?.call();
                widget.onChanged(0);
              },
              child: SizedBox(
                height: 56,
                width: width,
                child: CustomPaint(
                  painter: _RulerPainter(
                    value: widget.value,
                    ticks: widget.ticks,
                    tickColor: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                    markerColor: theme.colorScheme.primary,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.value,
    required this.ticks,
    required this.tickColor,
    required this.markerColor,
  });

  final double value;
  final int ticks;
  final Color tickColor;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final spacing = size.width / (ticks - 1);
    // O tracinho do zero fica no centro quando o valor é 0 e desliza junto
    // com o arrasto — o marcador é que fica parado, como numa régua de
    // câmera.
    final offset = -value * (size.width / 2);
    final paint = Paint()
      ..color = tickColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < ticks; i++) {
      final x = offset + size.width / 2 + (i - (ticks - 1) / 2) * spacing;
      if (x < 0 || x > size.width) continue;
      // Um tracinho a cada 5 é mais alto, para dar noção de escala.
      final tall = (i - (ticks - 1) ~/ 2) % 5 == 0;
      final half = tall ? 14.0 : 8.0;
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }

    canvas.drawLine(
      Offset(size.width / 2, size.height / 2 - 18),
      Offset(size.width / 2, size.height / 2 + 18),
      Paint()
        ..color = markerColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.ticks != ticks ||
      oldDelegate.tickColor != tickColor ||
      oldDelegate.markerColor != markerColor;
}
