import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/collage_background.dart';
import '../../models/collage_cell.dart';

/// Célula interativa de uma montagem: mostra a foto recortada ("cover") ou
/// inteira ("contain") com deslocamento/zoom/rotação livre/espelhamento/
/// ajustes de cor aplicados, permite arrastar com 1 dedo e dar pinça com 2
/// (mesmo callback `onScale*` do Flutter cobre reposicionar, girar e
/// redimensionar ao mesmo tempo) para manipular a foto dentro da célula,
/// duplo toque alterna entre preencher e ajustar recentralizando a foto (ver
/// [_CollageCellViewState._toggleFitMode]), e um botão "..." abre o menu de
/// ações (substituir/trocar/ajustar cor/recortar/girar 90°/espelhar/borda/
/// recentralizar), fornecido pela tela que usa este widget.
class CollageCellView extends StatefulWidget {
  const CollageCellView({
    super.key,
    required this.cell,
    required this.cellSize,
    required this.onChanged,
    required this.onMenu,
    this.onGestureStart,
    this.interactive = true,
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

  /// Quando `false`, a foto continua visível mas para de responder a
  /// toque/arrasto/pinça/duplo toque e o botão "..." some do alcance de
  /// toque — mesmo tratamento que [CollageOverlayView.interactive] dá a
  /// stickers/texto. Usado para só permitir mover/recortar a foto de uma
  /// célula enquanto nenhuma das abas "Stickers"/"Texto" estiver aberta,
  /// evitando que um arrasto pensado para um sticker ou texto acabe
  /// reposicionando a foto por baixo.
  final bool interactive;

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

  /// Posição do toque que iniciou o gesto e o quanto o dedo andou dali até a
  /// arena aceitar o arrasto — ver [_onScaleUpdate].
  Offset? _lastPointerDown;
  Offset _pendingSlop = Offset.zero;

  void _onPointerDown(PointerDownEvent event) {
    _lastPointerDown = event.position;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _checkpointPushed = false;
    _startZoom = widget.cell.zoom;
    _startRotation = widget.cell.rotation;
    _pendingSlop =
        details.focalPoint - (_lastPointerDown ?? details.focalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final cell = widget.cell;
    final contentSize = _contentSize;
    final newZoom = (_startZoom * details.scale).clamp(
      CollageCellSettings.minZoom,
      CollageCellSettings.maxZoom,
    );
    final newRotation = _startRotation + details.rotation;

    // Recupera o trecho que a arena de gestos engoliu antes de aceitar o
    // arrasto (o `touch slop`), pelo mesmo motivo de `CollageOverlayView`:
    // sem isso a foto começa atrasada em relação ao dedo e fica assim até o
    // fim do gesto.
    final movement = details.focalPointDelta + _pendingSlop;
    _pendingSlop = Offset.zero;

    final probe = cell.copyWith(zoom: newZoom, rotation: newRotation);
    final delta = switch (cell.fitMode) {
      CollageCellFitMode.cover => probe.offsetDeltaForDrag(
        movement,
        contentSize,
      ),
      CollageCellFitMode.contain => probe.containOffsetDeltaForDrag(
        movement,
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

  /// Duplo toque: alterna encaixar/expandir E devolve a foto ao enquadramento
  /// padrão do modo de destino — centralizada, sem zoom e de volta à posição
  /// horizontal (0°). Girar a foto e depois alternar o modo deixava um
  /// enquadramento herdado do modo anterior, que raramente é o que se quer ao
  /// pedir "encaixa isso aqui"; [CollageCellSettings.resetFraming] é o mesmo
  /// reset que o item "Recentralizar" do menu "..." já usa.
  void _toggleFitMode() {
    widget.onGestureStart?.call();
    widget.onChanged(
      widget.cell.resetFraming().copyWith(
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

    // Borda própria da foto: um anel ao redor do conteúdo, desenhado com
    // `border` (não com uma cor de fundo por baixo de tudo, como era antes) —
    // pintar a célula inteira da cor da borda deixava a sobra do modo
    // "encaixar" com a cor da borda mesmo com o fundo transparente. Mesma
    // correção que `paintCollageCell` recebeu na exportação. O `Container` já
    // afasta o filho pela espessura do próprio `Border` (a
    // `decoration.padding`), então a faixa continua reservada sem um
    // `padding` explícito — que agora somaria duas vezes.
    final hasBorder = cell.hasPhoto && borderThickness > 0;
    return IgnorePointer(
      // Mesmo tratamento que CollageOverlayView.interactive dá a
      // stickers/texto: com a aba "Stickers" ou "Texto" aberta, um gesto
      // sobre a foto (ou o botão "...") não deve mexer nela.
      ignoring: !widget.interactive,
      child: Stack(
        // O botão "..." fica fora deste Stack clip-none, pousado sobre o
        // canto do retângulo em vez de encolhido dentro dele — por isso não
        // pode morar no Stack recortado pelo ClipRRect abaixo, ou o recorte
        // cortaria a metade dele que sai para fora da célula.
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              border: hasBorder
                  ? Border.all(color: cell.borderColor, width: borderThickness)
                  : null,
              borderRadius: BorderRadius.circular(outerRadius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              // O [Listener] registra onde o dedo tocou antes de a arena
              // decidir de quem é o gesto — [_onScaleStart] usa isso para
              // não perder o começo do arrasto (ver [_onScaleUpdate]).
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: cell.hasPhoto ? _onScaleStart : null,
                  onScaleUpdate: cell.hasPhoto ? _onScaleUpdate : null,
                  onDoubleTap: cell.hasPhoto ? _toggleFitMode : null,
                  onTap: cell.hasPhoto ? null : widget.onMenu,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // O placeholder cinza só aparece em células vazias ou
                      // em modo "cover" (onde a foto sempre preenche 100% da
                      // célula, então é inofensivo tê-lo por baixo). Em modo
                      // "contain" com foto, ele TEM que sumir: a sobra ao
                      // redor da foto precisa mostrar o fundo real da
                      // montagem (pintado por baixo, no mesmo Stack de
                      // `_preview()`), não um cinza que a exportação não
                      // reproduz.
                      if (!cell.hasPhoto ||
                          cell.fitMode == CollageCellFitMode.cover)
                        ColoredBox(
                          color: theme.colorScheme.surfaceContainerHigh,
                        ),
                      // Fundo próprio da foto, por baixo dela e por cima do
                      // placeholder — mesma camada que `paintCollageCell`
                      // pinta na área de conteúdo da célula antes da foto.
                      _cellBackground(cell.background),
                      if (cell.hasPhoto)
                        _CellPhoto(cell: cell, cellSize: contentSize)
                      else
                        Center(
                          child: Icon(
                            Icons.add_photo_alternate_outlined,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.6,
                            ),
                            size: 28,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Pousado sobre o canto do retângulo, poucos pixels para fora dele
          // — não pode ir tão longe quanto o centro geométrico do canto
          // (offset -15 = metade do botão de 30px): o hit-test do Flutter só
          // enxerga toques dentro do próprio tamanho do Stack (o
          // `clipBehavior: Clip.none` acima só afeta pintura, nunca
          // hit-test), então um botão centralizado exatamente na quina tem
          // seu centro geométrico bem na borda excludente do retângulo e
          // nunca é tocável. -6 deixa o centro do botão com folga (~21px)
          // dentro da célula, mantendo a metade dele visível para fora.
          if (cell.hasPhoto)
            Positioned(
              right: -6,
              top: -6,
              child: _MenuButton(onTap: widget.onMenu),
            ),
        ],
      ),
    );
  }

  /// Espelho de `CollagePage._backgroundPreview()` para o fundo de uma única
  /// foto: nada quando transparente (o fundo da montagem continua aparecendo
  /// por baixo), a cor escolhida, ou a imagem recortada em "cover" — o mesmo
  /// enquadramento que `paintCollageBackground` usa na exportação.
  Widget _cellBackground(CollageBackground background) {
    switch (background.mode) {
      case CollageBackgroundMode.transparent:
        return const SizedBox.shrink();
      case CollageBackgroundMode.color:
        return ColoredBox(color: background.color);
      case CollageBackgroundMode.image:
        final path = background.imagePath;
        if (path == null) return const SizedBox.shrink();
        return Image.file(File(path), fit: BoxFit.cover);
    }
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
    return _Unclipped(
      child: _CroppedCover(
        photoPath: cell.photoPath!,
        photoWidth: cell.photoWidth,
        photoHeight: cell.photoHeight,
        src: src,
        destWidth: destWidth,
        destHeight: destHeight,
      ),
    );
  }

  Widget? _containContent() {
    final display = cell.containDisplaySize(cellSize);
    if (display == Size.zero) return null;
    final offset = cell.containDisplayOffset(cellSize);

    // O deslocamento entra por dentro da rotação (este widget já é filho do
    // `Transform.rotate` de [build]), igual ao `translate` que
    // `paintCollageCell` aplica antes de girar o canvas na exportação.
    return Transform.translate(
      offset: offset,
      child: _Unclipped(
        child: SizedBox(
          width: display.width,
          height: display.height,
          child: Image.file(File(cell.photoPath!), fit: BoxFit.fill),
        ),
      ),
    );
  }
}

/// Deixa [child] ser medido no tamanho que ele mesmo pede — centralizado no
/// espaço da célula —, mesmo quando esse tamanho passa do tamanho da célula.
///
/// Sem isso, as restrições apertadas que o `Stack(fit: StackFit.expand)` de
/// [CollageCellView] impõe encolhiam o conteúdo de volta ao tamanho da
/// célula, e a caixa resultante girava junto com a foto (é filha do
/// [Transform.rotate]): em "cover" a foto girada saía espremida (a prévia
/// divergia de `paintCollageCell`, que desenha no tamanho do
/// [rotatedFootprint]) e em "contain" ela era cortada por um retângulo
/// girado ao ampliar depois de girar. Quem recorta é só o [ClipRRect] da
/// célula, que não gira.
class _Unclipped extends StatelessWidget {
  const _Unclipped({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OverflowBox(
      alignment: Alignment.center,
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: child,
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
