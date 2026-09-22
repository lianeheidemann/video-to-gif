import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/eraser_mask.dart';

/// Zoom máximo da prévia da borracha. Oito vezes já deixa pincelar em cima
/// de um detalhe pequeno numa foto de 12 MP sem virar uma sopa de pixels.
const _maxZoom = 8.0;

/// A prévia da aba "Borracha": a foto, o véu da seleção por cima, e os
/// gestos que desenham e dão zoom.
///
/// Gestos, que é onde isto podia dar errado: **um dedo pinta, dois dedos dão
/// zoom e arrastam**. A decisão é tomada por contagem de ponteiros no início
/// do gesto, não por arena de reconhecedores — um `InteractiveViewer` por
/// fora brigaria com o arrasto do pincel pelo mesmo ponteiro, e quem ganha aí
/// depende de detalhe de ordem na árvore. Contar dedo é chato de escrever uma
/// vez e previsível para sempre.
///
/// Se um segundo dedo encosta no meio de uma pincelada, o traço em andamento
/// é descartado e o gesto vira zoom: é quase sempre o que a pessoa queria, e
/// deixar meia pincelada na seleção seria pior.
class EraserCanvas extends StatefulWidget {
  const EraserCanvas({
    super.key,
    required this.photoWidth,
    required this.photoHeight,
    required this.mask,
    required this.tool,
    required this.brushRadius,
    required this.onMaskChanged,
    required this.child,
    this.enabled = true,
    this.onZoomChanged,
  });

  final int photoWidth;
  final int photoHeight;

  /// A seleção já confirmada. O traço em andamento fica no estado do widget
  /// e só entra aqui quando o dedo sai da tela — assim cada traço vira
  /// exatamente um passo de desfazer.
  final EraserMask mask;

  final EraserTool tool;

  /// Raio do pincel em **pixels da foto**, não da tela: assim a pincelada
  /// cobre a mesma área independentemente do zoom.
  final double brushRadius;

  final ValueChanged<EraserMask> onMaskChanged;

  /// A foto, desenhada no tamanho da caixa.
  final Widget child;

  final bool enabled;

  /// Avisa quando a prévia passa de enquadrada para ampliada e vice-versa.
  /// Sem isso o botão "Enquadrar" do painel só apareceria na próxima vez que
  /// a tela se reconstruísse por outro motivo — o zoom acontece no estado
  /// deste widget, que a tela não observa.
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<EraserCanvas> createState() => EraserCanvasState();
}

class EraserCanvasState extends State<EraserCanvas> {
  double _zoom = 1;
  Offset _pan = Offset.zero;

  /// Traço sendo desenhado agora, em pixels da foto.
  List<Offset>? _drawing;

  /// Estado do gesto de dois dedos, congelado no início para o cálculo ser
  /// relativo e não acumular erro.
  double _zoomAtGestureStart = 1;
  Offset _panAtGestureStart = Offset.zero;
  Offset _focalAtGestureStart = Offset.zero;
  bool _transforming = false;

  /// `true` quando a prévia está ampliada — a tela usa isso para mostrar o
  /// botão de voltar ao enquadramento.
  bool get isZoomed => _zoom > 1.001 || _pan != Offset.zero;

  void resetZoom() {
    if (!isZoomed) return;
    setState(() {
      _zoom = 1;
      _pan = Offset.zero;
    });
    widget.onZoomChanged?.call(false);
  }

  /// Aplica um novo enquadramento e avisa a tela só quando o estado
  /// "ampliado ou não" realmente virou.
  void _setZoom(double zoom, Offset pan) {
    final was = isZoomed;
    setState(() {
      _zoom = zoom;
      _pan = pan;
    });
    if (isZoomed != was) widget.onZoomChanged?.call(isZoomed);
  }

  /// Escala entre pixel da foto e pixel da caixa (antes do zoom).
  double _baseScale(Size box) => box.width / widget.photoWidth;

  /// Tela → pixel da foto. Desfaz o zoom e depois a escala da prévia.
  Offset _toPhoto(Offset local, Size box) {
    final unzoomed = (local - _pan) / _zoom;
    return unzoomed / _baseScale(box);
  }

  /// Mantém a foto ancorada: nunca dá para arrastá-la para fora da caixa.
  Offset _clampPan(Offset pan, Size box, double zoom) {
    final slackX = box.width * (zoom - 1);
    final slackY = box.height * (zoom - 1);
    return Offset(pan.dx.clamp(-slackX, 0.0), pan.dy.clamp(-slackY, 0.0));
  }

  void _onScaleStart(ScaleStartDetails details, Size box) {
    _zoomAtGestureStart = _zoom;
    _panAtGestureStart = _pan;
    _focalAtGestureStart = details.localFocalPoint;

    if (details.pointerCount >= 2) {
      _transforming = true;
      return;
    }
    _transforming = false;
    setState(() => _drawing = [_toPhoto(details.localFocalPoint, box)]);
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size box) {
    // Segundo dedo no meio da pincelada: o traço em andamento é jogado fora
    // e o gesto vira zoom.
    if (details.pointerCount >= 2 && !_transforming) {
      _transforming = true;
      setState(() => _drawing = null);
      _zoomAtGestureStart = _zoom;
      _panAtGestureStart = _pan;
      _focalAtGestureStart = details.localFocalPoint;
      return;
    }

    if (_transforming) {
      final zoom = (_zoomAtGestureStart * details.scale).clamp(1.0, _maxZoom);
      // O ponto sob os dedos tem que continuar sob os dedos: é o que faz o
      // zoom parecer que gruda na foto em vez de escorregar.
      final anchor =
          (_focalAtGestureStart - _panAtGestureStart) / _zoomAtGestureStart;
      final pan = details.localFocalPoint - anchor * zoom;
      _setZoom(zoom, _clampPan(pan, box, zoom));
      return;
    }

    final drawing = _drawing;
    if (drawing == null) return;
    final point = _toPhoto(details.localFocalPoint, box);
    // Descarta micro-movimentos: sem isso um arrasto lento vira centenas de
    // pontos praticamente iguais, e o caminho fica caro de desenhar à toa.
    if (drawing.isNotEmpty && (drawing.last - point).distance < 1) return;
    setState(() => drawing.add(point));
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_transforming) {
      _transforming = false;
      return;
    }
    final drawing = _drawing;
    setState(() => _drawing = null);
    if (drawing == null || drawing.isEmpty) return;

    widget.onMaskChanged(widget.mask.add(_strokeFrom(drawing)));
  }

  /// Converte os pontos crus do gesto no traço definitivo, conforme a
  /// ferramenta: o retângulo só guarda os quatro cantos da caixa arrastada; o
  /// laço fecha o contorno; o pincel mantém a linha com espessura.
  EraserStroke _strokeFrom(List<Offset> points) {
    switch (widget.tool) {
      case EraserTool.rectangle:
        final first = points.first;
        final last = points.last;
        final rect = Rect.fromPoints(first, last);
        return EraserStroke(
          points: [
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
          ],
          closed: true,
        );
      case EraserTool.lasso:
        return EraserStroke(points: points, closed: true);
      case EraserTool.brush:
      case EraserTool.unbrush:
        return EraserStroke(
          points: points,
          radius: widget.brushRadius,
          subtract: widget.tool.subtracts,
        );
    }
  }

  /// O que desenhar agora: a seleção confirmada mais o traço em andamento.
  EraserMask get _previewMask {
    final drawing = _drawing;
    if (drawing == null || drawing.isEmpty) return widget.mask;
    return widget.mask.add(_strokeFrom(drawing));
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.photoWidth / widget.photoHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final box = Size(constraints.maxWidth, constraints.maxHeight);
          final content = ClipRect(
            child: Transform(
              transform: Matrix4.identity()
                ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
                ..scaleByDouble(_zoom, _zoom, 1, 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  CustomPaint(
                    painter: _MaskPainter(
                      mask: _previewMask,
                      scale: _baseScale(box),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          );

          if (!widget.enabled) return content;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) => _onScaleStart(d, box),
            onScaleUpdate: (d) => _onScaleUpdate(d, box),
            onScaleEnd: _onScaleEnd,
            child: content,
          );
        },
      ),
    );
  }
}

/// Desenha o véu da seleção. A pintura em si sai de [paintEraserMask], a
/// mesma função que a rasterização usa — se as duas divergissem, a pessoa
/// marcaria uma coisa e apagaria outra.
class _MaskPainter extends CustomPainter {
  const _MaskPainter({
    required this.mask,
    required this.scale,
    required this.color,
  });

  final EraserMask mask;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (mask.strokes.isEmpty) return;
    // Uma camada própria: o "apagar seleção" usa `BlendMode.clear`, que
    // precisa de algo para limpar.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(scale);
    paintEraserMask(
      canvas,
      mask,
      addColor: color.withValues(alpha: 0.45),
      subtractColor: const Color(0x00000000),
      subtractBlendMode: BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.mask != mask || old.scale != scale || old.color != color;
}

/// Ponto de referência para o slider de pincel: um raio em pixels da foto,
/// derivado de uma fração do menor lado. Assim o mesmo "tamanho 30" cobre a
/// mesma proporção numa foto de 1 MP e numa de 12 MP — um raio fixo em
/// pixels seria um respingo numa e um borrão na outra.
double brushRadiusFor(double percent, int photoWidth, int photoHeight) {
  final shortest = math.min(photoWidth, photoHeight);
  return (shortest * percent / 100).clamp(1.0, shortest.toDouble());
}
