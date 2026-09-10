import 'package:flutter/material.dart';

/// Um sticker ou texto posicionado livremente sobre a montagem: arrastar com
/// 1 dedo reposiciona, pinça com 2 dedos redimensiona e gira ao mesmo tempo
/// (mesmo callback `onScale*` do Flutter cobre os três gestos). Toque simples
/// seleciona (a tela dona mostra então uma barra de ações — duplicar, trazer
/// para frente, enviar para trás, remover). Sem nenhum recorte/"clamp": um
/// sticker pode ficar parcial ou totalmente fora da montagem por escolha do
/// usuário.
///
/// As duas alças de um dedo só (redimensionar/girar) **não** moram aqui —
/// ver `CollagePage._selectedHandlesLayer`. Moraram, mas uma alça é filha do
/// próprio item na pilha de sobreposições, ordenada por `zIndex`; com dois
/// ou mais itens, um item mais novo (zIndex maior, pintado por cima) que
/// passasse a cobrir o canto de um item mais antigo selecionado bloqueava o
/// toque na alça por baixo — o `Stack` para de testar o que está atrás do
/// primeiro filho que "acerta" o toque. Por isso as alças agora vivem numa
/// camada própria, sempre por cima de tudo na pilha principal, independente
/// do `zIndex` de quem está selecionado.
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
    required this.interactive,
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

  /// Quando `false`, o conteúdo continua visível mas para de responder a
  /// toque/arrasto/pinça — usado para só permitir mover/girar/redimensionar
  /// um sticker ou texto enquanto a aba correspondente ("Stickers"/"Texto")
  /// estiver aberta no rodapé. A tela dona também deixa de passar [selected]
  /// nesse caso, para a moldura não ficar na prévia sem servir para nada.
  final bool interactive;
  final VoidCallback onSelect;
  final void Function(
    double centerX,
    double centerY,
    double scale,
    double rotation,
  )
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

  /// Igual a [CollageCellView]: o checkpoint de desfazer só entra quando o
  /// gesto muda mesmo alguma coisa, para um gesto que esbarra nos limites
  /// (escala já no máximo e nenhum movimento, por exemplo) não gastar um
  /// passo de desfazer que não desfaz nada.
  bool _checkpointPushed = false;

  /// Posição (global) do último `PointerDownEvent` visto por [_onPointerDown]
  /// — capturada ali, e não em [ScaleStartDetails.focalPoint], porque por
  /// essa altura o dedo já andou (a arena só aceita o gesto depois de passar
  /// da folga/`touch slop`, então o foco relatado no início já pode estar
  /// bem longe de onde o toque realmente começou).
  Offset? _lastPointerDown;

  void _onPointerDown(PointerDownEvent event) {
    _lastPointerDown = event.position;
  }

  /// Quanto o dedo andou entre o toque e o momento em que a arena de gestos
  /// aceitou o arrasto — ver [_onScaleUpdate], que soma isso ao primeiro
  /// deslocamento e zera em seguida.
  Offset _pendingSlop = Offset.zero;

  void _onScaleStart(ScaleStartDetails details) {
    final downPosition = _lastPointerDown ?? details.focalPoint;
    widget.onSelect();
    _checkpointPushed = false;
    _startScale = widget.scale;
    _startRotation = widget.rotation;
    _pendingSlop = details.focalPoint - downPosition;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newScale = (_startScale * details.scale).clamp(
      widget.minScale,
      widget.maxScale,
    );
    final newRotation = _startRotation + details.rotation;
    final currentCenterPx = Offset(
      widget.centerX * widget.canvasSize.width,
      widget.centerY * widget.canvasSize.height,
    );
    // `focalPointDelta` só começa a ser entregue DEPOIS que a arena aceita o
    // gesto: os ~18px que o dedo anda até lá (o `touch slop`) nunca chegavam
    // aqui, e o sticker/texto ficava atrasado em relação ao dedo pelo arrasto
    // inteiro — medido, 100px de arrasto viravam 80px de deslocamento, o que
    // se sente como "está se movendo devagar". Somar essa sobra no primeiro
    // deslocamento faz o objeto colar no dedo sem mexer no resto do gesto
    // (a pinça e a rotação continuam contando a partir do início aceito).
    final movement = details.focalPointDelta + _pendingSlop;
    _pendingSlop = Offset.zero;
    final newCenterPx = currentCenterPx + movement;
    final newCenterX = widget.canvasSize.width == 0
        ? widget.centerX
        : newCenterPx.dx / widget.canvasSize.width;
    final newCenterY = widget.canvasSize.height == 0
        ? widget.centerY
        : newCenterPx.dy / widget.canvasSize.height;
    if (newScale == widget.scale &&
        newRotation == widget.rotation &&
        newCenterX == widget.centerX &&
        newCenterY == widget.centerY) {
      return;
    }
    if (!_checkpointPushed) {
      _checkpointPushed = true;
      widget.onGestureStart?.call();
    }
    widget.onTransformChanged(newCenterX, newCenterY, newScale, newRotation);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: widget.centerX * widget.canvasSize.width,
      top: widget.centerY * widget.canvasSize.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: IgnorePointer(
          ignoring: !widget.interactive,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
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
                            border: Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          )
                        : null,
                    padding: widget.selected
                        ? const EdgeInsets.all(2)
                        : EdgeInsets.zero,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
