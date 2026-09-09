import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Um sticker ou texto posicionado livremente sobre a montagem: arrastar com
/// 1 dedo reposiciona, pinça com 2 dedos redimensiona e gira ao mesmo tempo
/// (mesmo callback `onScale*` do Flutter cobre os três gestos), e — quando
/// selecionado — duas alças fazem o mesmo com um dedo só: a do canto
/// inferior direito redimensiona (só escala) e a do canto superior direito
/// gira. A alça de girar existe porque a pinça só começa com os DOIS dedos
/// dentro da caixa: numa caixa de texto (larga e baixa) o segundo dedo quase
/// sempre cai fora dela, e girar texto ficava praticamente impossível. Toque simples seleciona
/// (a tela dona mostra então uma barra de ações — duplicar, trazer para
/// frente, enviar para trás, remover). Sem nenhum recorte/"clamp": um sticker
/// pode ficar parcial ou totalmente fora da montagem por escolha do usuário.
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
  /// toque/arrasto/pinça e à alça de redimensionar — usado para só permitir
  /// mover/girar/redimensionar um sticker ou texto enquanto a aba
  /// correspondente ("Stickers"/"Texto") estiver aberta no rodapé. A tela
  /// dona também deixa de passar [selected] nesse caso, para a moldura não
  /// ficar na prévia sem servir para nada.
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

  /// Chaves dos círculos das alças, usadas só para achar seus retângulos na
  /// tela em [_onScaleStart] — ver comentário ali sobre por que isso é
  /// necessário.
  final _handleKey = GlobalKey();
  final _rotateHandleKey = GlobalKey();

  /// Chave da caixa do conteúdo (já rotacionada e escalada), usada para achar
  /// o centro visual do overlay na tela — é em volta dele que a alça de
  /// girar mede o ângulo.
  final _contentKey = GlobalKey();

  /// `true` quando o gesto de pinça/arrasto do overlay inteiro (this) começou
  /// em cima da alça — nesse caso [_onScaleUpdate] vira no-op, deixando o
  /// redimensionamento inteiramente a cargo do [Listener] próprio da alça em
  /// [_onHandlePointerMove]. Um `GestureDetector` aninhado dentro de outro
  /// (a alça dentro da área toda do overlay) entra na MESMA arena de gestos
  /// do pai para aquele ponteiro — não há garantia de qual dos dois
  /// "ganha", e um arrasto de 1 dedo na alça podia ser interpretado como o
  /// pan do overlay inteiro (a alça não reagia, só o overlay se movia).
  /// Um `Listener` recebe eventos de ponteiro sempre, independente da
  /// disputa de arena, então a alça responde de verdade; e ignorar aqui o
  /// gesto do overlay quando ele nasceu sobre a alça evita o efeito duplo
  /// (mover E redimensionar ao mesmo tempo) sem precisar de um
  /// `GestureRecognizer` customizado.
  bool _ignoreOuterGesture = false;

  /// Posição (global) do último `PointerDownEvent` visto por [_onPointerDown]
  /// — capturada ali, e não em [ScaleStartDetails.focalPoint], porque por
  /// essa altura o dedo já andou (a arena só aceita o gesto depois de passar
  /// da folga/`touch slop`, então o foco relatado no início já pode estar
  /// bem longe de onde o toque realmente começou).
  Offset? _lastPointerDown;

  void _onPointerDown(PointerDownEvent event) {
    _lastPointerDown = event.position;
  }

  bool _pointOverHandle(Offset globalPosition) =>
      _pointOverKey(_handleKey, globalPosition) ||
      _pointOverKey(_rotateHandleKey, globalPosition);

  bool _pointOverKey(GlobalKey key, Offset globalPosition) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    return (topLeft & box.size).contains(globalPosition);
  }

  /// Quanto o dedo andou entre o toque e o momento em que a arena de gestos
  /// aceitou o arrasto — ver [_onScaleUpdate], que soma isso ao primeiro
  /// deslocamento e zera em seguida.
  Offset _pendingSlop = Offset.zero;

  void _onScaleStart(ScaleStartDetails details) {
    final downPosition = _lastPointerDown ?? details.focalPoint;
    _ignoreOuterGesture = widget.selected && _pointOverHandle(downPosition);
    if (_ignoreOuterGesture) return;
    widget.onSelect();
    _checkpointPushed = false;
    _startScale = widget.scale;
    _startRotation = widget.rotation;
    _pendingSlop = details.focalPoint - downPosition;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_ignoreOuterGesture) return;
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

  bool _handleCheckpointPushed = false;

  void _onHandlePointerDown(PointerDownEvent event) {
    _handleCheckpointPushed = false;
  }

  /// Converte o arrasto da alça (canto inferior direito) numa variação de
  /// escala: desfaz a rotação atual do vetor de arrasto (mesmo padrão
  /// `cos`/`sin` usado em `collage_cell.dart`) e soma as duas componentes
  /// locais — arrastar para longe do centro (direita/baixo, sem girar)
  /// cresce; para perto, encolhe — como uma fração de [canvasSize].
  /// shortestSide, o mesmo tipo de unidade proporcional usado no resto do
  /// app (nunca pixels fixos). Usa `PointerMoveEvent.delta` (via [Listener],
  /// não `GestureDetector.onPanUpdate`) — ver [_ignoreOuterGesture].
  void _onHandlePointerMove(PointerMoveEvent event) {
    final reference = widget.canvasSize.shortestSide;
    if (reference <= 0) return;
    final cosA = math.cos(widget.rotation);
    final sinA = math.sin(widget.rotation);
    final local = Offset(
      event.delta.dx * cosA + event.delta.dy * sinA,
      -event.delta.dx * sinA + event.delta.dy * cosA,
    );
    final scaleDelta = (local.dx + local.dy) / reference;
    if (scaleDelta == 0) return;
    final newScale = (widget.scale + widget.scale * scaleDelta).clamp(
      widget.minScale,
      widget.maxScale,
    );
    if (newScale == widget.scale) return;
    if (!_handleCheckpointPushed) {
      _handleCheckpointPushed = true;
      widget.onGestureStart?.call();
    }
    widget.onTransformChanged(
      widget.centerX,
      widget.centerY,
      newScale,
      widget.rotation,
    );
  }

  bool _rotateCheckpointPushed = false;

  /// Ângulo do último ponto visto pela alça de girar, medido a partir do
  /// centro do overlay — a rotação aplicada é a diferença entre um ponto e o
  /// seguinte, então a alça pode ser agarrada de qualquer lado sem o
  /// conteúdo dar um pulo no primeiro movimento.
  double? _lastRotateAngle;

  double? _angleFromCenter(Offset globalPosition) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    final vector = globalPosition - center;
    // Em cima do próprio centro não há ângulo definido — ignora até o dedo
    // sair de lá.
    if (vector.distance < 1) return null;
    return math.atan2(vector.dy, vector.dx);
  }

  void _onRotatePointerDown(PointerDownEvent event) {
    _rotateCheckpointPushed = false;
    _lastRotateAngle = _angleFromCenter(event.position);
  }

  void _onRotatePointerMove(PointerMoveEvent event) {
    final angle = _angleFromCenter(event.position);
    if (angle == null) return;
    final last = _lastRotateAngle;
    _lastRotateAngle = angle;
    if (last == null) return;
    var delta = angle - last;
    // Normaliza a virada de -pi/pi, senão passar por trás do overlay daria um
    // giro de volta inteira num quadro só.
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    if (delta == 0) return;
    if (!_rotateCheckpointPushed) {
      _rotateCheckpointPushed = true;
      widget.onGestureStart?.call();
    }
    widget.onTransformChanged(
      widget.centerX,
      widget.centerY,
      widget.scale,
      widget.rotation + delta,
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
                    key: _contentKey,
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        widget.child,
                        if (widget.selected)
                          Positioned(
                            // Encostada por dentro do canto (não pendurada
                            // para fora, como um `right`/`bottom` negativo
                            // faria): um `Stack` sem filho "solto" (todos
                            // `Positioned`) do tamanho do conteúdo não
                            // hit-testa fora da própria caixa mesmo com
                            // `clipBehavior: Clip.none` (isso só afeta o
                            // desenho) — a alça ficaria visível mas
                            // impossível de tocar na metade que sobrasse
                            // para fora.
                            right: 0,
                            bottom: 0,
                            child: Transform.scale(
                              scale: 1 / widget.scale,
                              // Ancorada no canto: com o alinhamento padrão
                              // (centro), um sticker/texto pequeno — onde
                              // `1/scale` é grande — fazia a alça crescer
                              // para dentro e cobrir o conteúdo em vez de
                              // ficar no canto inferior direito.
                              alignment: Alignment.bottomRight,
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: _onHandlePointerDown,
                                onPointerMove: _onHandlePointerMove,
                                child: Container(
                                  key: _handleKey,
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.open_in_full_rounded,
                                    size: 12,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (widget.selected)
                          Positioned(
                            // Mesmo cuidado da alça de redimensionar: por
                            // dentro do canto, para continuar tocável.
                            right: 0,
                            top: 0,
                            child: Transform.scale(
                              scale: 1 / widget.scale,
                              alignment: Alignment.topRight,
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: _onRotatePointerDown,
                                onPointerMove: _onRotatePointerMove,
                                child: Container(
                                  key: _rotateHandleKey,
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.rotate_right_rounded,
                                    size: 14,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
