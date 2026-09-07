import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/collage_cell.dart';

/// Célula interativa de uma montagem: mostra a foto recortada ("cover") com
/// deslocamento/zoom/rotação/espelhamento/ajustes de cor aplicados, permite
/// arrastar com 1 dedo e dar pinça com 2 (mesmo callback `onScale*` do
/// Flutter cobre os dois casos) para reposicionar/redimensionar a foto
/// dentro da célula, duplo toque recentraliza, e um botão "..." abre o menu
/// de ações (substituir/trocar/ajustar cor/girar/espelhar), fornecido pela
/// tela que usa este widget.
class CollageCellView extends StatefulWidget {
  const CollageCellView({
    super.key,
    required this.cell,
    required this.cellSize,
    required this.onChanged,
    required this.onMenu,
    this.onGestureStart,
  });

  final CollageCellSettings cell;
  final Size cellSize;
  final ValueChanged<CollageCellSettings> onChanged;
  final VoidCallback onMenu;

  /// Chamado uma vez no início de cada gesto (antes da primeira mudança) —
  /// usado pela tela dona para empilhar o estado anterior no histórico de
  /// desfazer, sem empilhar de novo a cada frame do arrasto.
  final VoidCallback? onGestureStart;

  @override
  State<CollageCellView> createState() => _CollageCellViewState();
}

class _CollageCellViewState extends State<CollageCellView> {
  double _startZoom = CollageCellSettings.minZoom;

  void _onScaleStart(ScaleStartDetails details) {
    widget.onGestureStart?.call();
    _startZoom = widget.cell.zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final cell = widget.cell;
    final newZoom = (_startZoom * details.scale).clamp(
      CollageCellSettings.minZoom,
      CollageCellSettings.maxZoom,
    );
    final delta = cell
        .copyWith(zoom: newZoom)
        .offsetDeltaForDrag(details.focalPointDelta, widget.cellSize);
    widget.onChanged(
      cell.copyWith(
        zoom: newZoom,
        offsetX: (cell.offsetX + delta.dx).clamp(-1.0, 1.0),
        offsetY: (cell.offsetY + delta.dy).clamp(-1.0, 1.0),
      ),
    );
  }

  void _resetFraming() {
    widget.onGestureStart?.call();
    widget.onChanged(widget.cell.resetFraming());
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final theme = Theme.of(context);
    final radius = widget.cellSize.shortestSide *
        cell.cornerRatio.clamp(0.0, CollageCellSettings.maxCornerRatio);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: cell.hasPhoto ? _onScaleStart : null,
        onScaleUpdate: cell.hasPhoto ? _onScaleUpdate : null,
        onDoubleTap: cell.hasPhoto ? _resetFraming : null,
        onTap: cell.hasPhoto ? null : widget.onMenu,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
            if (cell.hasPhoto)
              _CellPhoto(cell: cell, cellSize: widget.cellSize)
            else
              Center(
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  size: 28,
                ),
              ),
            if (cell.hasPhoto)
              Positioned(
                right: 4,
                top: 4,
                child: _MenuButton(onTap: widget.onMenu),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Foto recortada ("cover") + rotação/espelhamento/cor de uma célula. A
/// ordem de composição (espelhar por dentro, girar por fora via
/// [RotatedBox]) é a mesma usada por `paintCollageCell` no compositor, para
/// a prévia nunca divergir visualmente da exportação. [RotatedBox] (em vez
/// de `Transform.rotate`) troca a própria caixa de layout nos giros de 90°/
/// 270°, então não é preciso compensar manualmente a troca de largura por
/// altura — o Flutter já faz isso.
class _CellPhoto extends StatelessWidget {
  const _CellPhoto({required this.cell, required this.cellSize});

  final CollageCellSettings cell;
  final Size cellSize;

  @override
  Widget build(BuildContext context) {
    final src = cell.coverSrcRect(cellSize);
    if (src == Rect.zero) return const SizedBox.shrink();

    final destWidth = cell.rotation.swapsAxes ? cellSize.height : cellSize.width;
    final destHeight = cell.rotation.swapsAxes ? cellSize.width : cellSize.height;

    Widget cropped = _CroppedCover(
      photoPath: cell.photoPath!,
      photoWidth: cell.photoWidth,
      photoHeight: cell.photoHeight,
      src: src,
      destWidth: destWidth,
      destHeight: destHeight,
    );

    if (cell.flipHorizontal || cell.flipVertical) {
      cropped = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          cell.flipHorizontal ? -1.0 : 1.0,
          cell.flipVertical ? -1.0 : 1.0,
          1.0,
        ),
        child: cropped,
      );
    }

    return ColorFiltered(
      colorFilter: cell.colorFilter,
      child: RotatedBox(quarterTurns: cell.rotation.quarterTurns, child: cropped),
    );
  }
}

/// Mostra apenas a janela [src] (em pixels nativos da foto) esticada para
/// preencher exatamente [destWidth]x[destHeight] — mesma técnica de
/// `CroppedView` (usada para o recorte do vídeo): um [FittedBox] no modo
/// `fill` escala a janela de recorte para o tamanho de destino, e um
/// [OverflowBox]+[Transform.translate] extrai essa janela da imagem
/// inteira renderizada em seu tamanho nativo.
class _CroppedCover extends StatelessWidget {
  const _CroppedCover({
    required this.photoPath,
    required this.photoWidth,
    required this.photoHeight,
    required this.src,
    required this.destWidth,
    required this.destHeight,
  });

  final String photoPath;
  final int photoWidth;
  final int photoHeight;
  final Rect src;
  final double destWidth;
  final double destHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: destWidth,
      height: destHeight,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: src.width,
          height: src.height,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: photoWidth.toDouble(),
              maxHeight: photoHeight.toDouble(),
              child: Transform.translate(
                offset: Offset(-src.left, -src.top),
                child: SizedBox(
                  width: photoWidth.toDouble(),
                  height: photoHeight.toDouble(),
                  child: Image.file(File(photoPath), fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
