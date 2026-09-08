import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/collage_cell.dart';

/// Célula interativa de uma montagem: mostra a foto recortada ("cover") ou
/// inteira ("contain") com deslocamento/zoom/rotação livre/espelhamento/
/// ajustes de cor aplicados, permite arrastar com 1 dedo e dar pinça com 2
/// (mesmo callback `onScale*` do Flutter cobre reposicionar, girar e
/// redimensionar ao mesmo tempo) para manipular a foto dentro da célula,
/// duplo toque alterna entre preencher e ajustar, e um botão "..." abre o
/// menu de ações (substituir/trocar/ajustar cor/recortar/girar 90°/
/// espelhar/borda/recentralizar), fornecido pela tela que usa este widget.
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

  /// Chamado uma vez por gesto, imediatamente antes da primeira mudança de
  /// verdade — usado pela tela dona para empilhar o estado anterior no
  /// histórico de desfazer, sem empilhar de novo a cada quadro do arrasto e
  /// sem empilhar nada quando o gesto termina sem mexer em nada.
  final VoidCallback? onGestureStart;

  @override
  State<CollageCellView> createState() => _CollageCellViewState();
}

class _CollageCellViewState extends State<CollageCellView> {
  double _startZoom = CollageCellSettings.minZoom;
  double _startRotation = 0;

  /// O checkpoint de desfazer só é empilhado na primeira mudança real do
  /// gesto: empilhar já no [_onScaleStart] gastava um passo de desfazer em
  /// gestos que não mudam nada — arrastar uma foto que já preenche a célula
  /// sem folga em nenhum eixo, por exemplo.
  bool _checkpointPushed = false;

  /// Tamanho disponível para a FOTO em si, descontada a borda própria da
  /// célula (se houver) — a borda ocupa uma faixa fixa ao redor, então toda
  /// a matemática de recorte/enquadramento (e os próprios gestos) opera
  /// sobre esse tamanho menor, nunca sobre [CollageCellView.cellSize] cru.
  Size get _contentSize {
    final thickness = widget.cell.borderThicknessFor(widget.cellSize.width);
    final w = (widget.cellSize.width - thickness * 2).clamp(
      0.0,
      widget.cellSize.width,
    );
    final h = (widget.cellSize.height - thickness * 2).clamp(
      0.0,
      widget.cellSize.height,
    );
    return Size(w, h);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _checkpointPushed = false;
    _startZoom = widget.cell.zoom;
    _startRotation = widget.cell.rotation;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final cell = widget.cell;
    final contentSize = _contentSize;
    final newZoom = (_startZoom * details.scale).clamp(
      CollageCellSettings.minZoom,
      CollageCellSettings.maxZoom,
    );
    final newRotation = _startRotation + details.rotation;

    final probe = cell.copyWith(zoom: newZoom, rotation: newRotation);
    final delta = switch (cell.fitMode) {
      CollageCellFitMode.cover => probe.offsetDeltaForDrag(
        details.focalPointDelta,
        contentSize,
      ),
      CollageCellFitMode.contain => probe.containOffsetDeltaForDrag(
        details.focalPointDelta,
        contentSize,
      ),
    };
    final newOffsetX = (cell.offsetX + delta.dx).clamp(-1.0, 1.0);
    final newOffsetY = (cell.offsetY + delta.dy).clamp(-1.0, 1.0);

    if (newZoom == cell.zoom &&
        newRotation == cell.rotation &&
        newOffsetX == cell.offsetX &&
        newOffsetY == cell.offsetY) {
      return;
    }
    if (!_checkpointPushed) {
      _checkpointPushed = true;
      widget.onGestureStart?.call();
    }
    widget.onChanged(
      cell.copyWith(
        zoom: newZoom,
        rotation: newRotation,
        offsetX: newOffsetX,
        offsetY: newOffsetY,
      ),
    );
  }

  void _toggleFitMode() {
    widget.onGestureStart?.call();
    widget.onChanged(
      widget.cell.copyWith(
        fitMode: switch (widget.cell.fitMode) {
          CollageCellFitMode.cover => CollageCellFitMode.contain,
          CollageCellFitMode.contain => CollageCellFitMode.cover,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final theme = Theme.of(context);
    final outerRadius =
        widget.cellSize.shortestSide *
        cell.cornerRatio.clamp(0.0, CollageCellSettings.maxCornerRatio);
    final borderThickness = cell.borderThicknessFor(widget.cellSize.width);
    final innerRadius = (outerRadius - borderThickness).clamp(0.0, outerRadius);
    final contentSize = _contentSize;

    // Borda própria da foto: uma faixa sólida ao redor do conteúdo — o
    // mesmo truque de layout (cor de fundo do Container + padding
    // reservando a faixa) que a montagem inteira já usava antes de virar
    // pintura em canvas; aqui não tem o mesmo problema de "vazar" por baixo
    // de fotos vizinhas porque cada célula cuida só da própria borda.
    return Container(
      decoration: BoxDecoration(
        color: cell.hasPhoto && borderThickness > 0 ? cell.borderColor : null,
        borderRadius: BorderRadius.circular(outerRadius),
      ),
      padding: cell.hasPhoto && borderThickness > 0
          ? EdgeInsets.all(borderThickness)
          : EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerRadius),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: cell.hasPhoto ? _onScaleStart : null,
          onScaleUpdate: cell.hasPhoto ? _onScaleUpdate : null,
          onDoubleTap: cell.hasPhoto ? _toggleFitMode : null,
          onTap: cell.hasPhoto ? null : widget.onMenu,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // O placeholder cinza só aparece em células vazias ou em modo
              // "cover" (onde a foto sempre preenche 100% da célula, então é
              // inofensivo tê-lo por baixo). Em modo "contain" com foto, ele
              // TEM que sumir: a sobra ao redor da foto precisa mostrar o
              // fundo real da montagem (pintado por baixo, no mesmo Stack de
              // `_preview()`), não um cinza que a exportação não reproduz.
              if (!cell.hasPhoto || cell.fitMode == CollageCellFitMode.cover)
                ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
              if (cell.hasPhoto)
                _CellPhoto(cell: cell, cellSize: contentSize)
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

/// Foto de uma célula (recortada em modo "cover", inteira em modo
/// "contain") + rotação livre/espelhamento/cor. A ordem de composição
/// (espelhar por dentro, girar por fora via [Transform.rotate]) é a mesma
/// usada por `paintCollageCell` no compositor, para a prévia nunca divergir
/// visualmente da exportação. [Transform.rotate] (em vez do antigo
/// `RotatedBox`) aceita qualquer ângulo, não só múltiplos de 90°.
class _CellPhoto extends StatelessWidget {
  const _CellPhoto({required this.cell, required this.cellSize});

  final CollageCellSettings cell;
  final Size cellSize;

  @override
  Widget build(BuildContext context) {
    final content = switch (cell.fitMode) {
      CollageCellFitMode.cover => _coverContent(),
      CollageCellFitMode.contain => _containContent(),
    };
    if (content == null) return const SizedBox.shrink();

    Widget cropped = content;
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
      child: Transform.rotate(angle: cell.rotation, child: cropped),
    );
  }

  Widget? _coverContent() {
    final src = cell.coverSrcRect(cellSize);
    if (src == Rect.zero) return null;

    final (destWidth, destHeight) = rotatedFootprint(
      cellSize.width,
      cellSize.height,
      cell.rotation,
    );
    return _CroppedCover(
      photoPath: cell.photoPath!,
      photoWidth: cell.photoWidth,
      photoHeight: cell.photoHeight,
      src: src,
      destWidth: destWidth,
      destHeight: destHeight,
    );
  }

  Widget? _containContent() {
    final display = cell.containDisplaySize(cellSize);
    if (display == Size.zero) return null;
    final offset = cell.containDisplayOffset(cellSize);

    return SizedBox.fromSize(
      size: cellSize,
      child: Stack(
        children: [
          Positioned(
            left: cellSize.width / 2 + offset.dx - display.width / 2,
            top: cellSize.height / 2 + offset.dy - display.height / 2,
            width: display.width,
            height: display.height,
            child: Image.file(
              File(cell.photoPath!),
              fit: BoxFit.fill,
              width: display.width,
              height: display.height,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mostra apenas a janela [src] (em pixels nativos da foto — sempre
/// relativos à foto inteira, mesmo quando há um
/// [CollageCellSettings.manualCrop], que [CollageCellSettings.coverSrcRect]
/// já traduz de volta para essas coordenadas) esticada para preencher
/// exatamente [destWidth]x[destHeight] — mesma técnica de `CroppedView`
/// (usada para o recorte do vídeo): um [FittedBox] no modo `fill` escala a
/// janela de recorte para o tamanho de destino, e um
/// [OverflowBox]+[Transform.translate] extrai essa janela da imagem inteira
/// renderizada em seu tamanho nativo.
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
