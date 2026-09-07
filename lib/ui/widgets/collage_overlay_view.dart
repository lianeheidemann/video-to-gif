import 'package:flutter/material.dart';

/// Um sticker ou texto posicionado livremente sobre a montagem: arrastar com
/// 1 dedo reposiciona, pinça com 2 dedos redimensiona e gira ao mesmo tempo
/// (mesmo callback `onScale*` do Flutter cobre os três gestos). Toque simples
/// seleciona (a tela dona mostra então uma barra de ações — duplicar, trazer
/// para frente, enviar para trás, remover). Sem nenhum recorte/"clamp": um
/// sticker pode ficar parcial ou totalmente fora da montagem por escolha do
/// usuário.
///
/// `details.focalPointDelta` é incremental (delta desde a última chamada),
/// por isso soma direto no valor atual; já `details.scale`/`details.rotation`
/// são cumulativos desde o início do gesto, por isso multiplicam/somam sobre
/// o valor capturado em [onScaleStart].
class CollageOverlayView extends StatefulWidget {
  const CollageOverlayView({
    super.key,
    required this.centerX,
    required this.centerY,
    required this.scale,
    required this.rotation,
    required this.minScale,
    required this.maxScale,
    required this.canvasSize,
    required this.selected,
    required this.onSelect,
    required this.onTransformChanged,
    this.onGestureStart,
    required this.child,
  });

  /// Centro normalizado ao tamanho do canvas (`0..1`) — pode sair de `[0,1]`.
  final double centerX;
  final double centerY;
  final double scale;
  final double rotation;
  final double minScale;
  final double maxScale;
  final Size canvasSize;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double centerX, double centerY, double scale, double rotation)
  onTransformChanged;

  /// Chamado uma vez no início de cada gesto — mesma finalidade de
  /// [CollageCellView.onGestureStart].
  final VoidCallback? onGestureStart;
  final Widget child;

  @override
  State<CollageOverlayView> createState() => _CollageOverlayViewState();
}

class _CollageOverlayViewState extends State<CollageOverlayView> {
  double _startScale = 1;
  double _startRotation = 0;

  void _onScaleStart(ScaleStartDetails details) {
    widget.onSelect();
    widget.onGestureStart?.call();
    _startScale = widget.scale;
    _startRotation = widget.rotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newScale = (_startScale * details.scale).clamp(widget.minScale, widget.maxScale);
    final newRotation = _startRotation + details.rotation;
    final currentCenterPx = Offset(
      widget.centerX * widget.canvasSize.width,
      widget.centerY * widget.canvasSize.height,
    );
    final newCenterPx = currentCenterPx + details.focalPointDelta;
    widget.onTransformChanged(
      widget.canvasSize.width == 0 ? widget.centerX : newCenterPx.dx / widget.canvasSize.width,
      widget.canvasSize.height == 0 ? widget.centerY : newCenterPx.dy / widget.canvasSize.height,
      newScale,
      newRotation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: widget.centerX * widget.canvasSize.width,
      top: widget.centerY * widget.canvasSize.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onSelect,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          child: Transform.rotate(
            angle: widget.rotation,
            child: Transform.scale(
              scale: widget.scale,
              child: Container(
                decoration: widget.selected
                    ? BoxDecoration(
                        border: Border.all(color: theme.colorScheme.primary, width: 2),
                      )
                    : null,
                padding: widget.selected ? const EdgeInsets.all(2) : EdgeInsets.zero,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
