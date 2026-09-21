import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/collage_text.dart';
import '../models/default_colors.dart';
import '../services/imported_font_store.dart';
import 'collage_overlay_view.dart';
import '../../features/collage/painting/collage_painter.dart'
    show paintCollageTextBackground;
import 'color_picker_sheet.dart';

/// Caixas de texto arrastáveis sobre uma prévia — mesma interação e mesmo
/// visual da aba "Texto" de `CollagePage` (arrastar/pinçar move e redimensiona,
/// alças de um dedo giram/redimensionam, um painel escreve/estiliza),
/// generalizada aqui para qualquer tela que só precise de texto (sem
/// stickers): "Editar imagem" e "Editar GIF". [TextOverlayStack] entra na
/// pilha da prévia; [TextOverlayPanel] entra na aba/painel de baixo; as duas
/// compartilham estado efêmero (seleção, edição, campo de texto, fontes
/// importadas) através de um [TextOverlayController] comum, enquanto a
/// lista de [CollageTextItem] continua sendo dona de quem chama (mesmo
/// princípio de `FrameSettings.texts`/`ConversionSettings.frame.texts`, que
/// ficam vivos junto do resto do projeto enquanto o app roda).
class TextOverlayController extends ChangeNotifier {
  String? selectedId;
  String? editingId;
  final textController = TextEditingController();
  final textFocus = FocusNode();

  static const _fontStore = ImportedFontStore();
  List<ImportedFont> importedFonts = [];

  /// Gesto em andamento das alças de redimensionar/girar — mesma ideia de
  /// `CollagePage._resizeHandleCheckpointPushed`/`_rotatePointerPos`, só que
  /// guardados aqui para `TextOverlayStack` (um `StatelessWidget`) poder
  /// acumular entre quadros do arrasto sem precisar de `State` próprio.
  bool resizeCheckpointPushed = false;
  bool rotateCheckpointPushed = false;
  Offset? rotatePointerPos;
  double? lastRotateAngle;

  Future<void> loadFonts() async {
    final fonts = await _fontStore.loadAll();
    importedFonts = fonts;
    notifyListeners();
  }

  void select(String? id) {
    if (selectedId == id) return;
    selectedId = id;
    notifyListeners();
  }

  /// Tira a seleção quando o item selecionado some da lista (removido, ou a
  /// tela reiniciou o projeto) — mesma ideia de
  /// `CollagePage._dropSelectionIfGone`.
  void dropSelectionIfGone(List<CollageTextItem> texts) {
    final id = selectedId;
    if (id != null && texts.findText(id) == null) {
      selectedId = null;
      notifyListeners();
    }
  }

  void beginEdit(CollageTextItem item) {
    editingId = item.id;
    textController.text = item.text;
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: item.text.length,
    );
    notifyListeners();
    textFocus.requestFocus();
  }

  void cancelEdit() {
    editingId = null;
    textController.clear();
    notifyListeners();
  }

  /// Fecha a edição em andamento sem mexer no campo de texto — usado depois
  /// que [TextOverlayPanel] já salvou o texto editado.
  void finishEdit() {
    editingId = null;
    notifyListeners();
  }

  void addImportedFont(ImportedFont font) {
    importedFonts = [...importedFonts, font];
    notifyListeners();
  }

  @override
  void dispose() {
    textController.dispose();
    textFocus.dispose();
    super.dispose();
  }
}

/// Caixa colorida atrás de um texto — mesmo desenho de
/// `CollagePage._TextBackgroundBox`, reexposto aqui via [paintCollageTextBackground]
/// (já compartilhado com a exportação).
class TextOverlayBackgroundBox extends StatelessWidget {
  const TextOverlayBackgroundBox({
    super.key,
    required this.color,
    required this.cornerRatio,
    required this.padding,
    required this.child,
  });

  final Color color;
  final double cornerRatio;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BackgroundPainter(color: color, cornerRatio: cornerRatio),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter({required this.color, required this.cornerRatio});

  final Color color;
  final double cornerRatio;

  @override
  void paint(Canvas canvas, Size size) => paintCollageTextBackground(
    canvas,
    Offset.zero & size,
    color,
    cornerRatio,
  );

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.cornerRatio != cornerRatio;
}

/// Desenho de um texto sobreposto no tamanho do canvas dado — o mesmo
/// respiro e o mesmo arredondamento que a exportação pinta, então a prévia e
/// o arquivo final batem em qualquer tamanho de fonte.
///
/// Compartilhado entre a pilha desta biblioteca e a prévia da Montagem, que
/// desenha stickers e textos na mesma camada e por isso não usa
/// [TextOverlayStack].
Widget textOverlayArt(CollageTextItem item, Size canvasSize) {
  final fontSize = canvasSize.shortestSide * item.fontSizeRatio;
  final text = Text(
    item.text,
    textAlign: TextAlign.center,
    style: TextStyle(
      color: item.color,
      fontSize: fontSize,
      fontFamily: item.fontFamily,
      fontWeight: item.bold ? FontWeight.w700 : FontWeight.w400,
    ),
  );
  final background = item.backgroundColor;
  if (background == null) return text;
  final (padH, padV) = CollageTextItem.backgroundPaddingFor(fontSize);
  return TextOverlayBackgroundBox(
    color: background,
    cornerRatio: item.backgroundCornerRatio,
    padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
    child: text,
  );
}

/// Tamanho natural (escala 1) de um texto sobreposto, já com o respiro do
/// fundo quando ele existe. Calculado analiticamente, sem medir em tempo de
/// execução — é o que posiciona as alças de redimensionar/girar.
Size textOverlayNaturalSize(CollageTextItem item, Size canvasSize) {
  final fontSize = canvasSize.shortestSide * item.fontSizeRatio;
  final painter = TextPainter(
    text: TextSpan(
      text: item.text,
      style: TextStyle(
        fontSize: fontSize,
        fontFamily: item.fontFamily,
        fontWeight: item.bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();
  final size = Size(painter.width, painter.height);
  painter.dispose();
  if (item.backgroundColor == null) return size;
  final (padH, padV) = CollageTextItem.backgroundPaddingFor(fontSize);
  return Size(size.width + padH * 2, size.height + padV * 2);
}

/// A pilha de textos arrastáveis + as alças do item selecionado — entra por
/// cima da prévia já composta (dentro de um `Stack`/`LayoutBuilder` do
/// tamanho exato do canvas final), do mesmo jeito que `CropOverlay` entra
/// por cima da prévia na aba "Recorte".
class TextOverlayStack extends StatelessWidget {
  const TextOverlayStack({
    super.key,
    required this.controller,
    required this.texts,
    required this.onChanged,
    required this.canvasSize,
    required this.interactive,
    this.onGestureStart,
  });

  final TextOverlayController controller;
  final List<CollageTextItem> texts;
  final ValueChanged<List<CollageTextItem>> onChanged;
  final Size canvasSize;

  /// Só responde a toque/arrasto/pinça com a aba "Texto" aberta — mesma
  /// regra de `CollageOverlayView.interactive`.
  final bool interactive;
  final VoidCallback? onGestureStart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sorted = [...texts]..sort((a, b) => a.zIndex.compareTo(b.zIndex));
        return Stack(
          children: [
            for (final item in sorted) _overlayWidget(item),
            if (interactive) ..._selectedHandles(context),
          ],
        );
      },
    );
  }

  Widget _overlayWidget(CollageTextItem item) {
    return CollageOverlayView(
      key: ValueKey(item.id),
      centerX: item.centerX,
      centerY: item.centerY,
      scale: item.scale,
      rotation: item.rotation,
      minScale: CollageTextItem.minScale,
      maxScale: CollageTextItem.maxScale,
      canvasSize: canvasSize,
      selected: interactive && controller.selectedId == item.id,
      interactive: interactive,
      onSelect: () => controller.select(item.id),
      onGestureStart: onGestureStart,
      onTransformChanged: (cx, cy, scale, rotation) => onChanged(
        texts.replacingText(
          item.id,
          item.copyWith(
            centerX: cx,
            centerY: cy,
            scale: scale,
            rotation: rotation,
          ),
        ),
      ),
      child: textOverlayArt(item, canvasSize),
    );
  }

  List<Widget> _selectedHandles(BuildContext context) {
    final id = controller.selectedId;
    if (id == null) return const [];
    final item = texts.findText(id);
    if (item == null) return const [];

    final naturalSize = textOverlayNaturalSize(item, canvasSize);
    final center = Offset(
      item.centerX * canvasSize.width,
      item.centerY * canvasSize.height,
    );
    final halfW = naturalSize.width * item.scale / 2;
    final halfH = naturalSize.height * item.scale / 2;
    final cosR = math.cos(item.rotation);
    final sinR = math.sin(item.rotation);
    Offset rotate(Offset local) => Offset(
      local.dx * cosR - local.dy * sinR,
      local.dx * sinR + local.dy * cosR,
    );

    final resizeCenter = center + rotate(Offset(halfW, halfH));
    final rotateCenter = center + rotate(Offset(halfW, -halfH));

    void apply(double cx, double cy, double scale, double rotation) =>
        onChanged(
          texts.replacingText(
            id,
            item.copyWith(
              centerX: cx,
              centerY: cy,
              scale: scale,
              rotation: rotation,
            ),
          ),
        );

    return [
      _handleCircle(
        context: context,
        center: resizeCenter,
        icon: Icons.open_in_full_rounded,
        onPointerDown: (_) => controller.resizeCheckpointPushed = false,
        onPointerMove: (event) => _onResizeMove(event, item, apply),
      ),
      _handleCircle(
        context: context,
        center: rotateCenter,
        icon: Icons.rotate_right_rounded,
        onPointerDown: (_) {
          controller.rotateCheckpointPushed = false;
          controller.rotatePointerPos = rotateCenter;
          controller.lastRotateAngle = null;
        },
        onPointerMove: (event) => _onRotateMove(event, item, center, apply),
      ),
    ];
  }

  void _onResizeMove(
    PointerMoveEvent event,
    CollageTextItem item,
    void Function(double cx, double cy, double scale, double rotation) apply,
  ) {
    final reference = canvasSize.shortestSide;
    if (reference <= 0) return;
    final cosA = math.cos(item.rotation);
    final sinA = math.sin(item.rotation);
    final local = Offset(
      event.delta.dx * cosA + event.delta.dy * sinA,
      -event.delta.dx * sinA + event.delta.dy * cosA,
    );
    final scaleDelta = (local.dx + local.dy) / reference;
    if (scaleDelta == 0) return;
    final newScale = (item.scale + item.scale * scaleDelta).clamp(
      CollageTextItem.minScale,
      CollageTextItem.maxScale,
    );
    if (newScale == item.scale) return;
    if (!controller.resizeCheckpointPushed) {
      controller.resizeCheckpointPushed = true;
      onGestureStart?.call();
    }
    apply(item.centerX, item.centerY, newScale, item.rotation);
  }

  void _onRotateMove(
    PointerMoveEvent event,
    CollageTextItem item,
    Offset center,
    void Function(double cx, double cy, double scale, double rotation) apply,
  ) {
    final pos = (controller.rotatePointerPos ?? center) + event.delta;
    controller.rotatePointerPos = pos;
    final vector = pos - center;
    if (vector.distance < 1) return;
    final angle = math.atan2(vector.dy, vector.dx);
    final last = controller.lastRotateAngle;
    controller.lastRotateAngle = angle;
    if (last == null) return;
    var delta = angle - last;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    if (delta == 0) return;
    if (!controller.rotateCheckpointPushed) {
      controller.rotateCheckpointPushed = true;
      onGestureStart?.call();
    }
    apply(item.centerX, item.centerY, item.scale, item.rotation + delta);
  }

  Widget _handleCircle({
    required BuildContext context,
    required Offset center,
    required IconData icon,
    required void Function(PointerDownEvent) onPointerDown,
    required void Function(PointerMoveEvent) onPointerMove,
  }) {
    final theme = Theme.of(context);
    const diameter = 24.0;
    const tapSize = 48.0;
    return Positioned(
      left: center.dx - tapSize / 2,
      top: center.dy - tapSize / 2,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: onPointerDown,
        onPointerMove: onPointerMove,
        child: SizedBox(
          width: tapSize,
          height: tapSize,
          child: Center(
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Icon(
                icon,
                size: icon == Icons.rotate_right_rounded ? 14 : 12,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Painel de baixo: campo de escrever texto + (com um texto selecionado)
/// barra de ações e controles de cor/fundo — mesmo conteúdo da aba "Texto"
/// de `CollagePage`, sem a parte de layout/stickers que não existe aqui.
class TextOverlayPanel extends StatelessWidget {
  const TextOverlayPanel({
    super.key,
    required this.controller,
    required this.texts,
    required this.onChanged,
    required this.previewImageBuilder,
    this.onGestureStart,
  });

  final TextOverlayController controller;
  final List<CollageTextItem> texts;
  final ValueChanged<List<CollageTextItem>> onChanged;
  final Future<ui.Image> Function() previewImageBuilder;

  /// Chamado antes da primeira mudança de um gesto contínuo (slider, roda de
  /// cor) — a tela dona decide o que fazer (normalmente empilhar um
  /// checkpoint de desfazer), mesmo papel de `CollagePage._pushUndoCheckpoint`.
  final VoidCallback? onGestureStart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.selectedId == null
            ? null
            : texts.findText(controller.selectedId!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selected != null) _selectionToolbar(context, selected),
            _composer(context),
            if (selected != null) ...[
              const SizedBox(height: 8),
              _colorRow(
                context,
                'Cor do texto',
                selected.color,
                () => _pickColor(
                  context,
                  title: 'Cor do texto',
                  current: selected.color,
                  apply: (item, color) => item.copyWith(color: color),
                ),
              ),
              _switchRow(
                context,
                'Fundo do texto',
                selected.hasBackground,
                (on) => _toggleBackground(selected, on),
              ),
              if (selected.hasBackground) ...[
                const SizedBox(height: 4),
                _backgroundGroup(context, selected),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _selectionToolbar(BuildContext context, CollageTextItem selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Editar',
            onPressed: () => controller.beginEdit(selected),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Fonte',
            onPressed: () => _pickFont(context, selected),
            icon: const Icon(Icons.font_download_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Duplicar',
            onPressed: () => _duplicate(selected),
            icon: const Icon(Icons.copy_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Frente',
            onPressed: () => _bringToFront(selected),
            icon: const Icon(Icons.flip_to_front_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Trás',
            onPressed: () => _sendToBack(selected),
            icon: const Icon(Icons.flip_to_back_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Remover',
            onPressed: () => _remove(selected),
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final theme = Theme.of(context);
    final editing = controller.editingId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              editing ? 'Editar texto' : 'Novo texto',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (editing)
              TextButton(
                onPressed: controller.cancelEdit,
                child: const Text('Cancelar'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller.textController,
          builder: (context, value, _) {
            final canSubmit = value.text.trim().isNotEmpty;
            return TextField(
              controller: controller.textController,
              focusNode: controller.textFocus,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Digite seu texto...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.fromLTRB(18, 12, 4, 12),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    tooltip: editing ? 'Salvar texto' : 'Adicionar texto',
                    onPressed: canSubmit ? _submit : null,
                    icon: Icon(
                      editing ? Icons.check_rounded : Icons.add_rounded,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: canSubmit
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      foregroundColor: canSubmit
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _submit() {
    final text = controller.textController.text.trim();
    if (text.isEmpty) return;
    final editingId = controller.editingId;
    onGestureStart?.call();
    if (editingId != null) {
      final item = texts.findText(editingId);
      if (item != null) {
        onChanged(texts.replacingText(editingId, item.copyWith(text: text)));
      }
      controller.finishEdit();
    } else {
      final item = CollageTextItem(
        id: 't_${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        centerX: 0.5,
        centerY: 0.5,
        zIndex: texts.nextTextZIndex,
      );
      onChanged([...texts, item]);
      controller.select(item.id);
    }
    controller.textController.clear();
    controller.textFocus.requestFocus();
  }

  Widget _backgroundGroup(BuildContext context, CollageTextItem selected) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Column(
        children: [
          _colorRow(
            context,
            'Cor',
            selected.backgroundColor!,
            () => _pickColor(
              context,
              title: 'Cor do fundo do texto',
              current: selected.backgroundColor!,
              apply: (item, color) => item.copyWith(backgroundColor: color),
            ),
          ),
          const SizedBox(height: 4),
          _sliderRow(
            context,
            label: 'Opacidade',
            value: selected.backgroundColor!.a,
            min: 0,
            max: 1,
            display: '${(selected.backgroundColor!.a * 100).round()}%',
            onChanged: (v) => onChanged(
              texts.replacingText(
                selected.id,
                selected.copyWith(
                  backgroundColor: selected.backgroundColor!.withValues(
                    alpha: v,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _sliderRow(
            context,
            label: 'Arredondamento',
            value: selected.backgroundCornerRatio,
            min: 0,
            max: CollageTextItem.maxBackgroundCornerRatio,
            display:
                '${(selected.backgroundCornerRatio / CollageTextItem.maxBackgroundCornerRatio * 100).round()}%',
            onChanged: (v) => onChanged(
              texts.replacingText(
                selected.id,
                selected.copyWith(backgroundCornerRatio: v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleBackground(CollageTextItem item, bool on) {
    onGestureStart?.call();
    onChanged(
      texts.replacingText(
        item.id,
        on
            ? item.copyWith(
                backgroundColor: item.backgroundColor ?? defaultBackgroundColor,
              )
            : item.copyWith(clearBackgroundColor: true),
      ),
    );
  }

  void _pickColor(
    BuildContext context, {
    required String title,
    required Color current,
    required CollageTextItem Function(CollageTextItem item, Color color) apply,
  }) {
    var checkpointPushed = false;
    showCollageColorPickerSheet(
      context: context,
      title: title,
      initialColor: current,
      onColorSelected: (color) {
        final id = controller.selectedId;
        if (id == null) return;
        final latest = texts.findText(id);
        if (latest == null) return;
        if (!checkpointPushed) {
          checkpointPushed = true;
          onGestureStart?.call();
        }
        onChanged(texts.replacingText(id, apply(latest, color)));
      },
      previewImageBuilder: previewImageBuilder,
    );
  }

  void _pickFont(BuildContext context, CollageTextItem item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fonte',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final font in bundledCollageFonts)
                    _fontThumb(
                      sheetContext,
                      family: font.$1,
                      label: font.$2,
                      selected: item.fontFamily == font.$1,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _applyFont(item.id, font.$1);
                      },
                    ),
                  for (final font in controller.importedFonts)
                    _fontThumb(
                      sheetContext,
                      family: font.family,
                      label: font.label,
                      selected: item.fontFamily == font.family,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _applyFont(item.id, font.family);
                      },
                    ),
                  _fontThumb(
                    sheetContext,
                    family: null,
                    label: 'Importar',
                    selected: false,
                    icon: Icons.font_download_outlined,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _importFont(context, item.id);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fontThumb(
    BuildContext context, {
    required String? family,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 22, color: theme.colorScheme.primary)
            else
              Text('Aa', style: TextStyle(fontFamily: family, fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _applyFont(String id, String? family) {
    final item = texts.findText(id);
    if (item == null) return;
    onGestureStart?.call();
    onChanged(
      texts.replacingText(
        id,
        item.copyWith(fontFamily: family, clearFontFamily: family == null),
      ),
    );
  }

  Future<void> _importFont(BuildContext context, String textId) async {
    try {
      final font = await const ImportedFontStore().import();
      controller.addImportedFont(font);
      _applyFont(textId, font.family);
    } on ImportedFontException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _duplicate(CollageTextItem item) {
    onGestureStart?.call();
    final newItem = CollageTextItem(
      id: 't_${DateTime.now().microsecondsSinceEpoch}',
      text: item.text,
      color: item.color,
      backgroundColor: item.backgroundColor,
      backgroundCornerRatio: item.backgroundCornerRatio,
      fontSizeRatio: item.fontSizeRatio,
      bold: item.bold,
      centerX: (item.centerX + 0.05).clamp(0.0, 1.0),
      centerY: (item.centerY + 0.05).clamp(0.0, 1.0),
      scale: item.scale,
      rotation: item.rotation,
      zIndex: texts.nextTextZIndex,
      fontFamily: item.fontFamily,
    );
    onChanged([...texts, newItem]);
    controller.select(newItem.id);
  }

  void _bringToFront(CollageTextItem item) {
    onGestureStart?.call();
    onChanged(
      texts.replacingText(item.id, item.copyWith(zIndex: texts.nextTextZIndex)),
    );
  }

  void _sendToBack(CollageTextItem item) {
    onGestureStart?.call();
    onChanged(
      texts.replacingText(item.id, item.copyWith(zIndex: texts.minTextZIndex)),
    );
  }

  void _remove(CollageTextItem item) {
    onGestureStart?.call();
    onChanged(texts.removingText(item.id));
    controller.select(null);
  }

  Widget _sliderRow(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              display,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max),
          label: display,
          onChangeStart: (_) => onGestureStart?.call(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _switchRow(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _colorRow(
    BuildContext context,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                  width: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
