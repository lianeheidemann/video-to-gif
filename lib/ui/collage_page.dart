import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

import '../models/collage_background.dart';
import '../models/collage_cell.dart';
import '../models/collage_layout.dart';
import '../models/collage_settings.dart';
import '../models/collage_sticker.dart';
import '../models/collage_text.dart';
import '../models/photo_info.dart';
import '../services/collage_compositor.dart';
import '../services/imported_asset_store.dart';
import '../services/output_service.dart';
import 'widgets/collage_cell_view.dart';
import 'widgets/collage_overlay_view.dart';
import 'widgets/collage_painter.dart';
import 'widgets/color_picker_sheet.dart';
import 'widgets/labeled_section.dart';

/// Tela do editor de montagem de fotos: agrupa [photos] num layout (linha,
/// coluna ou grade), com margem/proporção/borda/cantos configuráveis, fundo
/// transparente/cor/imagem, stickers e texto sobrepostos, reposicionamento
/// por toque de cada foto, e opções de trocar/substituir/ajustar cor/girar/
/// espelhar cada célula. Mesma estrutura de `PhotoFramePage` (lista de
/// `LabeledSection`s + ações de salvar/compartilhar no fim), generalizada
/// para N fotos.
class CollagePage extends StatefulWidget {
  const CollagePage({super.key, required this.photos});

  final List<PhotoInfo> photos;

  @override
  State<CollagePage> createState() => _CollagePageState();
}

class _CollagePageState extends State<CollagePage> {
  static const _output = OutputService();
  static const _stickerStore = ImportedAssetStore(ImportedAssetKind.sticker);
  static const _backgroundStore = ImportedAssetStore(ImportedAssetKind.backgroundImage);

  late CollageSettings _settings = CollageSettings.forLayout(
    _defaultLayoutFor(widget.photos.length),
    widget.photos,
  );

  List<ImportedAsset> _importedStickers = [];
  List<ImportedAsset> _importedBackgrounds = [];

  final List<CollageSettings> _undoStack = [];
  final List<CollageSettings> _redoStack = [];

  String? _selectedOverlayId;

  bool _saving = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadImportedAssets();
  }

  static CollageLayout _defaultLayoutFor(int count) {
    if (count <= 2) return CollageLayout.row(count < 2 ? 2 : count);
    if (count == 3) return CollageLayout.row(3);
    if (count == 4) return const CollageLayout(kind: CollageLayoutKind.grid2x2);
    if (count <= 6) return const CollageLayout(kind: CollageLayoutKind.grid2x3);
    return const CollageLayout(kind: CollageLayoutKind.grid3x3);
  }

  Future<void> _loadImportedAssets() async {
    final stickers = await _stickerStore.loadAll();
    final backgrounds = await _backgroundStore.loadAll();
    if (!mounted) return;
    setState(() {
      _importedStickers = stickers;
      _importedBackgrounds = backgrounds;
    });
  }

  // ---------------------------------------------------------------------
  // Estado / desfazer-refazer
  // ---------------------------------------------------------------------

  /// Aplica uma nova [CollageSettings]. Por padrão empilha o estado anterior
  /// no histórico de desfazer — passe `pushUndo: false` para mudanças
  /// contínuas (arrastar, sliders) já precedidas por [_pushUndoCheckpoint]
  /// no início do gesto, para não empilhar um estado por quadro.
  void _update(CollageSettings settings, {bool pushUndo = true}) {
    if (pushUndo) {
      _undoStack.add(_settings);
      _redoStack.clear();
    }
    setState(() => _settings = settings);
  }

  void _pushUndoCheckpoint() {
    _undoStack.add(_settings);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    setState(() {
      _redoStack.add(_settings);
      _settings = previous;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    setState(() {
      _undoStack.add(_settings);
      _settings = next;
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final toolbar = _selectionToolbar();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Montagem de fotos'),
        actions: [
          IconButton(
            tooltip: 'Desfazer',
            onPressed: _undoStack.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Refazer',
            onPressed: _redoStack.isEmpty ? null : _redo,
            icon: const Icon(Icons.redo_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _preview(),
            if (toolbar != null) toolbar,
            const SizedBox(height: 20),
            _layoutSection(),
            _marginSection(),
            _aspectSection(),
            _borderSection(),
            _backgroundSection(),
            _stickersSection(),
            _textSection(),
            const SizedBox(height: 4),
            _actions(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Prévia
  // ---------------------------------------------------------------------

  Widget _preview() {
    return AspectRatio(
      aspectRatio: _settings.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final geometry = CollageGeometry.of(size, _settings);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (geometry.borderThickness > 0)
                Container(
                  decoration: BoxDecoration(
                    color: _settings.borderColor,
                    borderRadius: BorderRadius.circular(geometry.outerRadius),
                  ),
                ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(geometry.borderThickness),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(geometry.innerRadius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _backgroundPreview(),
                        for (var i = 0; i < _settings.cells.length; i++)
                          Positioned.fromRect(
                            rect: geometry.cellRects[i].translate(
                              -geometry.borderThickness,
                              -geometry.borderThickness,
                            ),
                            child: CollageCellView(
                              cell: _settings.cells[i],
                              cellSize: geometry.cellRects[i].size,
                              onGestureStart: _pushUndoCheckpoint,
                              onChanged: (cell) => _update(
                                _settings.replacingCell(i, cell),
                                pushUndo: false,
                              ),
                              onMenu: () => _openCellMenu(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              ..._overlayWidgets(size),
            ],
          );
        },
      ),
    );
  }

  Widget _backgroundPreview() {
    final background = _settings.background;
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

  /// Sticker e texto entram na mesma lista, ordenados por `zIndex` (menor
  /// primeiro) — mesma ordem usada por `collage_compositor.dart`'s
  /// `_paintOverlays`, para "Frente"/"Trás" terem o mesmo efeito visual na
  /// prévia e na exportação. As `Key`s estáveis (`ValueKey(id)`) garantem
  /// que reordenar a lista a cada rebuild não recrie os widgets nem perca o
  /// estado local de gesto em andamento.
  List<Widget> _overlayWidgets(Size size) {
    final entries = <(int zIndex, Widget widget)>[
      for (final sticker in _settings.stickers)
        (sticker.zIndex, _stickerOverlayWidget(sticker, size)),
      for (final text in _settings.texts) (text.zIndex, _textOverlayWidget(text, size)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final entry in entries) entry.$2];
  }

  Widget _stickerOverlayWidget(CollageSticker sticker, Size size) {
    return CollageOverlayView(
      key: ValueKey(sticker.id),
      centerX: sticker.centerX,
      centerY: sticker.centerY,
      scale: sticker.scale,
      rotation: sticker.rotation,
      minScale: CollageSticker.minScale,
      maxScale: CollageSticker.maxScale,
      canvasSize: size,
      selected: _selectedOverlayId == sticker.id,
      onSelect: () => setState(() => _selectedOverlayId = sticker.id),
      onGestureStart: _pushUndoCheckpoint,
      onTransformChanged: (cx, cy, scale, rotation) => _update(
        _settings.replacingSticker(
          sticker.id,
          sticker.copyWith(centerX: cx, centerY: cy, scale: scale, rotation: rotation),
        ),
        pushUndo: false,
      ),
      child: _stickerArt(sticker, size),
    );
  }

  Widget _textOverlayWidget(CollageTextItem text, Size size) {
    return CollageOverlayView(
      key: ValueKey(text.id),
      centerX: text.centerX,
      centerY: text.centerY,
      scale: text.scale,
      rotation: text.rotation,
      minScale: CollageTextItem.minScale,
      maxScale: CollageTextItem.maxScale,
      canvasSize: size,
      selected: _selectedOverlayId == text.id,
      onSelect: () => setState(() => _selectedOverlayId = text.id),
      onGestureStart: _pushUndoCheckpoint,
      onTransformChanged: (cx, cy, scale, rotation) => _update(
        _settings.replacingText(
          text.id,
          text.copyWith(centerX: cx, centerY: cy, scale: scale, rotation: rotation),
        ),
        pushUndo: false,
      ),
      child: _textArt(text, size),
    );
  }

  Widget _stickerArt(CollageSticker sticker, Size canvasSize) {
    final refSize = canvasSize.shortestSide * CollageSticker.referenceSizeRatio;
    final content = switch (sticker.source) {
      CollageStickerSource.bundledSvg => SvgPicture.asset(sticker.assetPath!, fit: BoxFit.contain),
      CollageStickerSource.importedSvg =>
        SvgPicture.file(File(sticker.imageFilePath!), fit: BoxFit.contain),
      CollageStickerSource.importedImage =>
        Image.file(File(sticker.imageFilePath!), fit: BoxFit.contain),
    };
    return SizedBox(width: refSize, height: refSize, child: content);
  }

  Widget _textArt(CollageTextItem item, Size canvasSize) {
    final fontSize = canvasSize.shortestSide * item.fontSizeRatio;
    return Text(
      item.text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: item.color,
        fontSize: fontSize,
        fontWeight: item.bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }

  Widget? _selectionToolbar() {
    final id = _selectedOverlayId;
    if (id == null) return null;
    final isText = id.startsWith('t_');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 4,
        children: [
          if (isText)
            TextButton.icon(
              onPressed: () => _editSelectedText(id),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar'),
            ),
          TextButton.icon(
            onPressed: () => _duplicateSelected(id, isText),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Duplicar'),
          ),
          TextButton.icon(
            onPressed: () => _bringToFront(id, isText),
            icon: const Icon(Icons.flip_to_front_outlined, size: 18),
            label: const Text('Frente'),
          ),
          TextButton.icon(
            onPressed: () => _sendToBack(id, isText),
            icon: const Icon(Icons.flip_to_back_outlined, size: 18),
            label: const Text('Trás'),
          ),
          TextButton.icon(
            onPressed: () => _removeSelected(id, isText),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remover'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Layout"
  // ---------------------------------------------------------------------

  Widget _layoutSection() {
    return LabeledSection(
      icon: Icons.grid_view_outlined,
      title: 'Layout',
      value: _settings.layout.kind.label,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: CollageLayoutKind.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _layoutThumb(CollageLayoutKind.values[index]),
            ),
          ),
          if (_settings.layout.kind == CollageLayoutKind.freeGrid) ...[
            const SizedBox(height: 14),
            _freeGridSteppers(),
          ],
        ],
      ),
    );
  }

  Widget _layoutThumb(CollageLayoutKind kind) {
    final theme = Theme.of(context);
    final selected = _settings.layout.kind == kind;
    return GestureDetector(
      onTap: () => _selectLayoutKind(kind),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 72,
              height: 56,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Icon(_layoutIcon(kind), color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text(
              kind.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  IconData _layoutIcon(CollageLayoutKind kind) => switch (kind) {
    CollageLayoutKind.row => Icons.view_column_outlined,
    CollageLayoutKind.column => Icons.table_rows_outlined,
    CollageLayoutKind.grid2x2 => Icons.grid_view_outlined,
    CollageLayoutKind.grid2x3 => Icons.grid_on_outlined,
    CollageLayoutKind.grid3x3 => Icons.apps_rounded,
    CollageLayoutKind.freeGrid => Icons.dashboard_customize_outlined,
  };

  Widget _freeGridSteppers() {
    final layout = _settings.layout;
    return Row(
      children: [
        Expanded(
          child: _stepperRow(
            'Colunas',
            layout.columns < 1 ? 2 : layout.columns,
            (v) => _applyLayout(layout.copyWith(columns: v)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _stepperRow(
            'Linhas',
            layout.rows < 1 ? 2 : layout.rows,
            (v) => _applyLayout(layout.copyWith(rows: v)),
          ),
        ),
      ],
    );
  }

  Widget _stepperRow(String label, int value, ValueChanged<int> onChanged) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          onPressed: value > CollageLayout.minFreeGridSpan ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$value', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        IconButton(
          onPressed: value < CollageLayout.maxFreeGridSpan ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  void _selectLayoutKind(CollageLayoutKind kind) {
    final currentCount = _settings.cells.length.clamp(2, 8);
    final layout = switch (kind) {
      CollageLayoutKind.row => CollageLayout.row(currentCount),
      CollageLayoutKind.column => CollageLayout.column(currentCount),
      CollageLayoutKind.grid2x2 => const CollageLayout(kind: CollageLayoutKind.grid2x2),
      CollageLayoutKind.grid2x3 => const CollageLayout(kind: CollageLayoutKind.grid2x3),
      CollageLayoutKind.grid3x3 => const CollageLayout(kind: CollageLayoutKind.grid3x3),
      CollageLayoutKind.freeGrid => CollageLayout.grid(2, 2),
    };
    _applyLayout(layout);
  }

  /// Troca o layout mantendo as fotos já escolhidas nas primeiras células —
  /// células novas (quando o layout cresce) nascem vazias, prontas para
  /// receber uma foto ao toque (ver [CollageCellView]'s `+`); células
  /// excedentes (quando o layout encolhe) são descartadas.
  void _applyLayout(CollageLayout layout) {
    final oldCells = _settings.cells;
    final cells = List<CollageCellSettings>.generate(
      layout.cellCount,
      (i) => i < oldCells.length ? oldCells[i] : const CollageCellSettings(),
    );
    _update(_settings.copyWith(layout: layout, cells: cells));
  }

  // ---------------------------------------------------------------------
  // Seção "Margem" / "Proporção" / "Borda e cantos"
  // ---------------------------------------------------------------------

  Widget _marginSection() {
    final percent = (_settings.marginRatio / CollageSettings.maxMarginRatio * 100).round();
    return LabeledSection(
      icon: Icons.space_dashboard_outlined,
      title: 'Margem',
      value: '$percent%',
      child: Slider(
        min: CollageSettings.minMarginRatio,
        max: CollageSettings.maxMarginRatio,
        value: _settings.marginRatio.clamp(
          CollageSettings.minMarginRatio,
          CollageSettings.maxMarginRatio,
        ),
        label: '$percent%',
        onChangeStart: (_) => _pushUndoCheckpoint(),
        onChanged: (v) => _update(_settings.copyWith(marginRatio: v), pushUndo: false),
      ),
    );
  }

  Widget _aspectSection() {
    return LabeledSection(
      icon: Icons.aspect_ratio_rounded,
      title: 'Proporção',
      value: _aspectLabel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in CollageSettings.aspectPresets)
                ChoiceChip(
                  label: Text(preset.$1),
                  selected: (_settings.aspectRatio - preset.$2).abs() < 0.001,
                  onSelected: (_) => _update(_settings.copyWith(aspectRatio: preset.$2)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            min: 0.4,
            max: 2.5,
            value: _settings.aspectRatio.clamp(0.4, 2.5),
            onChangeStart: (_) => _pushUndoCheckpoint(),
            onChanged: (v) => _update(_settings.copyWith(aspectRatio: v), pushUndo: false),
          ),
        ],
      ),
    );
  }

  String _aspectLabel() {
    for (final preset in CollageSettings.aspectPresets) {
      if ((preset.$2 - _settings.aspectRatio).abs() < 0.001) return preset.$1;
    }
    return _settings.aspectRatio.toStringAsFixed(2);
  }

  Widget _borderSection() {
    final theme = Theme.of(context);
    return LabeledSection(
      icon: Icons.crop_din_rounded,
      title: 'Borda e cantos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sliderRow(
            label: 'Espessura da borda',
            value: _settings.borderThicknessAtReference,
            min: 0,
            max: CollageSettings.maxBorderThickness,
            display: '${_settings.borderThicknessAtReference.round()}px',
            onChanged: (v) => _update(_settings.copyWith(borderThicknessAtReference: v), pushUndo: false),
          ),
          const SizedBox(height: 12),
          _sliderRow(
            label: 'Arredondamento dos cantos',
            value: _settings.cornerRatio,
            min: 0,
            max: CollageSettings.maxCornerRatio,
            display:
                '${(_settings.cornerRatio / CollageSettings.maxCornerRatio * 100).round()}%',
            onChanged: (v) => _update(_settings.copyWith(cornerRatio: v), pushUndo: false),
          ),
          if (_settings.borderThicknessAtReference > 0) ...[
            const SizedBox(height: 4),
            Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
            _colorRow('Cor da borda', _settings.borderColor, _pickBorderColor),
          ],
        ],
      ),
    );
  }

  Widget _sliderRow({
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
          onChangeStart: (_) => _pushUndoCheckpoint(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _colorRow(String label, Color color, VoidCallback onTap) {
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
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant, width: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickBorderColor() {
    _pushUndoCheckpoint();
    showCollageColorPickerSheet(
      context: context,
      title: 'Cor da borda',
      initialColor: _settings.borderColor,
      onColorSelected: (color) => _update(_settings.copyWith(borderColor: color), pushUndo: false),
      previewImageBuilder: _renderPreviewImage,
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Fundo"
  // ---------------------------------------------------------------------

  Widget _backgroundSection() {
    final background = _settings.background;
    return LabeledSection(
      icon: Icons.wallpaper_rounded,
      title: 'Fundo',
      value: switch (background.mode) {
        CollageBackgroundMode.transparent => 'Transparente',
        CollageBackgroundMode.color => 'Cor',
        CollageBackgroundMode.image => 'Imagem',
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<CollageBackgroundMode>(
            segments: const [
              ButtonSegment(
                value: CollageBackgroundMode.transparent,
                label: Text('Transparente'),
                icon: Icon(Icons.check_box_outline_blank_rounded),
              ),
              ButtonSegment(
                value: CollageBackgroundMode.color,
                label: Text('Cor'),
                icon: Icon(Icons.palette_outlined),
              ),
              ButtonSegment(
                value: CollageBackgroundMode.image,
                label: Text('Imagem'),
                icon: Icon(Icons.image_outlined),
              ),
            ],
            selected: {background.mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => _update(
              _settings.copyWith(background: background.copyWith(mode: selection.single)),
            ),
          ),
          if (background.mode == CollageBackgroundMode.color) ...[
            const SizedBox(height: 8),
            _colorRow('Cor do fundo', background.color, _openBackgroundColorPicker),
          ],
          if (background.mode == CollageBackgroundMode.image) ...[
            const SizedBox(height: 12),
            _backgroundImagePicker(),
          ],
        ],
      ),
    );
  }

  Widget _backgroundImagePicker() {
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _importedBackgrounds.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == _importedBackgrounds.length) {
            return _importTile(onTap: _importBackgroundImage, label: 'Importar');
          }
          final asset = _importedBackgrounds[index];
          final selected = _settings.background.imagePath == asset.filePath;
          return GestureDetector(
            onTap: () => _update(
              _settings.copyWith(
                background: _settings.background.copyWith(
                  mode: CollageBackgroundMode.image,
                  imagePath: asset.filePath,
                ),
              ),
            ),
            onLongPress: () => _confirmRemoveBackground(asset),
            child: _assetThumb(asset, selected: selected),
          );
        },
      ),
    );
  }

  void _openBackgroundColorPicker() {
    _pushUndoCheckpoint();
    showCollageColorPickerSheet(
      context: context,
      title: 'Cor do fundo',
      initialColor: _settings.background.color,
      onColorSelected: (color) => _update(
        _settings.copyWith(
          background: _settings.background.copyWith(
            mode: CollageBackgroundMode.color,
            color: color,
          ),
        ),
        pushUndo: false,
      ),
      previewImageBuilder: _renderPreviewImage,
    );
  }

  Future<void> _importBackgroundImage() async {
    try {
      final asset = await _backgroundStore.import();
      if (!mounted) return;
      setState(() => _importedBackgrounds = [..._importedBackgrounds, asset]);
      _update(
        _settings.copyWith(
          background: _settings.background.copyWith(
            mode: CollageBackgroundMode.image,
            imagePath: asset.filePath,
          ),
        ),
      );
    } on ImportedAssetException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _confirmRemoveBackground(ImportedAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover imagem de fundo?'),
        content: Text('"${asset.label}" vai ser removida da lista.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _backgroundStore.remove(asset.id);
    if (!mounted) return;
    setState(() {
      _importedBackgrounds = _importedBackgrounds.where((a) => a.id != asset.id).toList();
    });
    if (_settings.background.imagePath == asset.filePath) {
      _update(
        _settings.copyWith(
          background: _settings.background.copyWith(
            mode: CollageBackgroundMode.transparent,
            clearImagePath: true,
          ),
        ),
      );
    }
  }

  Future<ui.Image> _renderPreviewImage() async {
    final bytes = await composeCollage(settings: _settings, outputWidth: _previewSampleWidth());
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  int _previewSampleWidth() => 480;

  // ---------------------------------------------------------------------
  // Seção "Stickers" / "Texto"
  // ---------------------------------------------------------------------

  Widget _stickersSection() {
    return LabeledSection(
      icon: Icons.emoji_emotions_outlined,
      title: 'Stickers',
      hint: 'Toque para adicionar um sticker à montagem.',
      child: SizedBox(
        height: 70,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _importedStickers.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            if (index == _importedStickers.length) {
              return _importTile(onTap: _importSticker, label: 'Importar');
            }
            final asset = _importedStickers[index];
            return GestureDetector(
              onTap: () => _addStickerFromAsset(asset),
              onLongPress: () => _confirmRemoveSticker(asset),
              child: _assetThumb(asset, selected: false),
            );
          },
        ),
      ),
    );
  }

  Future<void> _importSticker() async {
    try {
      final asset = await _stickerStore.import();
      if (!mounted) return;
      setState(() => _importedStickers = [..._importedStickers, asset]);
      _addStickerFromAsset(asset);
    } on ImportedAssetException catch (e) {
      _message(e.message);
    }
  }

  void _addStickerFromAsset(ImportedAsset asset) {
    final sticker = CollageSticker(
      id: 's_${DateTime.now().microsecondsSinceEpoch}',
      source: asset.isVector
          ? CollageStickerSource.importedSvg
          : CollageStickerSource.importedImage,
      imageFilePath: asset.filePath,
      label: asset.label,
      centerX: 0.5,
      centerY: 0.5,
      zIndex: _settings.nextZIndex,
    );
    _update(_settings.addingSticker(sticker));
    setState(() => _selectedOverlayId = sticker.id);
  }

  Future<void> _confirmRemoveSticker(ImportedAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover sticker?'),
        content: Text('"${asset.label}" vai ser removido da lista.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _stickerStore.remove(asset.id);
    if (!mounted) return;
    setState(() => _importedStickers = _importedStickers.where((a) => a.id != asset.id).toList());
  }

  Widget _textSection() {
    return LabeledSection(
      icon: Icons.text_fields_rounded,
      title: 'Texto',
      child: OutlinedButton.icon(
        onPressed: _addText,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Adicionar texto'),
      ),
    );
  }

  Future<void> _addText() async {
    final text = await _promptTextInput(initial: '');
    if (text == null || text.trim().isEmpty) return;
    final item = CollageTextItem(
      id: 't_${DateTime.now().microsecondsSinceEpoch}',
      text: text.trim(),
      centerX: 0.5,
      centerY: 0.5,
      zIndex: _settings.nextZIndex,
    );
    _update(_settings.addingText(item));
    setState(() => _selectedOverlayId = item.id);
  }

  Future<void> _editSelectedText(String id) async {
    final item = _findText(id);
    if (item == null) return;
    final text = await _promptTextInput(initial: item.text);
    if (text == null || text.trim().isEmpty) return;
    _update(_settings.replacingText(id, item.copyWith(text: text.trim())));
  }

  Future<String?> _promptTextInput({required String initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Texto'),
        content: TextField(controller: controller, autofocus: true, maxLines: 3),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _importTile({required VoidCallback onTap, required String label}) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Icon(Icons.add_photo_alternate_outlined, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _assetThumb(ImportedAsset asset, {required bool selected}) {
    final theme = Theme.of(context);
    return Container(
      width: 62,
      height: 46,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 2 : 1,
        ),
      ),
      child: asset.isVector
          ? SvgPicture.file(File(asset.filePath), fit: BoxFit.contain)
          : Image.file(File(asset.filePath), fit: BoxFit.contain),
    );
  }

  // ---------------------------------------------------------------------
  // Overlays selecionados: duplicar / frente / trás / remover
  // ---------------------------------------------------------------------

  CollageSticker? _findSticker(String id) {
    for (final sticker in _settings.stickers) {
      if (sticker.id == id) return sticker;
    }
    return null;
  }

  CollageTextItem? _findText(String id) {
    for (final text in _settings.texts) {
      if (text.id == id) return text;
    }
    return null;
  }

  int get _minOverlayZIndex {
    var min = 0;
    for (final sticker in _settings.stickers) {
      if (sticker.zIndex < min) min = sticker.zIndex;
    }
    for (final text in _settings.texts) {
      if (text.zIndex < min) min = text.zIndex;
    }
    return min;
  }

  void _duplicateSelected(String id, bool isText) {
    if (isText) {
      final item = _findText(id);
      if (item == null) return;
      final newItem = CollageTextItem(
        id: 't_${DateTime.now().microsecondsSinceEpoch}',
        text: item.text,
        color: item.color,
        fontSizeRatio: item.fontSizeRatio,
        bold: item.bold,
        centerX: (item.centerX + 0.05).clamp(0.0, 1.0),
        centerY: (item.centerY + 0.05).clamp(0.0, 1.0),
        scale: item.scale,
        rotation: item.rotation,
        zIndex: _settings.nextZIndex,
      );
      _update(_settings.addingText(newItem));
      setState(() => _selectedOverlayId = newItem.id);
    } else {
      final sticker = _findSticker(id);
      if (sticker == null) return;
      final newSticker = CollageSticker(
        id: 's_${DateTime.now().microsecondsSinceEpoch}',
        source: sticker.source,
        assetPath: sticker.assetPath,
        imageFilePath: sticker.imageFilePath,
        label: sticker.label,
        centerX: (sticker.centerX + 0.05).clamp(0.0, 1.0),
        centerY: (sticker.centerY + 0.05).clamp(0.0, 1.0),
        scale: sticker.scale,
        rotation: sticker.rotation,
        zIndex: _settings.nextZIndex,
      );
      _update(_settings.addingSticker(newSticker));
      setState(() => _selectedOverlayId = newSticker.id);
    }
  }

  void _bringToFront(String id, bool isText) {
    if (isText) {
      final item = _findText(id);
      if (item == null) return;
      _update(_settings.replacingText(id, item.copyWith(zIndex: _settings.nextZIndex)));
    } else {
      final sticker = _findSticker(id);
      if (sticker == null) return;
      _update(_settings.replacingSticker(id, sticker.copyWith(zIndex: _settings.nextZIndex)));
    }
  }

  void _sendToBack(String id, bool isText) {
    final z = _minOverlayZIndex - 1;
    if (isText) {
      final item = _findText(id);
      if (item == null) return;
      _update(_settings.replacingText(id, item.copyWith(zIndex: z)));
    } else {
      final sticker = _findSticker(id);
      if (sticker == null) return;
      _update(_settings.replacingSticker(id, sticker.copyWith(zIndex: z)));
    }
  }

  void _removeSelected(String id, bool isText) {
    _update(isText ? _settings.removingText(id) : _settings.removingSticker(id));
    setState(() => _selectedOverlayId = null);
  }

  // ---------------------------------------------------------------------
  // Menu por célula: substituir / trocar / ajustar cor / girar / espelhar
  // ---------------------------------------------------------------------

  void _openCellMenu(int index) {
    final cell = _settings.cells[index];
    if (!cell.hasPhoto) {
      _pickPhotoForCell(index);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Substituir foto'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickPhotoForCell(index);
                },
              ),
              if (_settings.cells.where((c) => c.hasPhoto).length > 1)
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: const Text('Trocar com…'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openSwapPicker(index);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Ajustar cor'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openCellColorAdjust(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.rotate_90_degrees_ccw_rounded),
                title: const Text('Girar 90°'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _rotateCell(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flip_rounded),
                title: const Text('Espelhar horizontal'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _flipCell(index, horizontal: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flip_rounded),
                title: const Text('Espelhar vertical'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _flipCell(index, horizontal: false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhotoForCell(int index) async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Escolha uma foto');
      final path = picked?.path;
      if (path == null) return;

      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();

      final cell = _settings.cells[index];
      final replaced = cell
          .copyWith(photoPath: path, photoWidth: width, photoHeight: height)
          .resetFraming();
      _update(_settings.replacingCell(index, replaced));
    } catch (_) {
      _message('Não foi possível abrir esta foto.');
    }
  }

  void _openSwapPicker(int index) {
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
              Text('Trocar com qual foto?', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < _settings.cells.length; i++)
                    if (i != index && _settings.cells[i].hasPhoto)
                      GestureDetector(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _update(_settings.swappingCells(index, i));
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 62,
                            height: 62,
                            child: Image.file(
                              File(_settings.cells[i].photoPath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCellColorAdjust(int index) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            final cell = _settings.cells[index];

            void applyAdjustment(CollageCellSettings updated) {
              _update(_settings.replacingCell(index, updated), pushUndo: false);
              sheetSetState(() {});
            }

            Widget adjustSlider(String label, double value, CollageCellSettings Function(double) apply) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(sheetContext).textTheme.bodyMedium),
                  Slider(
                    min: -1,
                    max: 1,
                    value: value.clamp(-1.0, 1.0),
                    onChangeStart: (_) => _pushUndoCheckpoint(),
                    onChanged: (v) => applyAdjustment(apply(v)),
                  ),
                ],
              );
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ajustar cor', style: Theme.of(sheetContext).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    adjustSlider('Brilho', cell.brightness, (v) => cell.copyWith(brightness: v)),
                    adjustSlider('Contraste', cell.contrast, (v) => cell.copyWith(contrast: v)),
                    adjustSlider(
                      'Saturação',
                      cell.saturation,
                      (v) => cell.copyWith(saturation: v),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _rotateCell(int index) {
    final cell = _settings.cells[index];
    _update(_settings.replacingCell(index, cell.copyWith(rotation: cell.rotation.next)));
  }

  void _flipCell(int index, {required bool horizontal}) {
    final cell = _settings.cells[index];
    _update(
      _settings.replacingCell(
        index,
        horizontal
            ? cell.copyWith(flipHorizontal: !cell.flipHorizontal)
            : cell.copyWith(flipVertical: !cell.flipVertical),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------

  int _exportWidth() {
    var maxSide = 0;
    for (final cell in _settings.cells) {
      if (cell.photoWidth > maxSide) maxSide = cell.photoWidth;
      if (cell.photoHeight > maxSide) maxSide = cell.photoHeight;
    }
    if (maxSide < 480) maxSide = 480;
    return maxSide.clamp(480, 2200);
  }

  Future<File> _writeTempPng(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/montagem_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await composeCollage(settings: _settings, outputWidth: _exportWidth());
      final file = await _writeTempPng(bytes);
      await _output.saveToGallery(file);
      if (!mounted) return;
      _message('Montagem salva na galeria.');
    } on OutputException catch (e) {
      if (!mounted) return;
      _message(e.message);
    } catch (_) {
      if (!mounted) return;
      _message('Não foi possível gerar a imagem.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final bytes = await composeCollage(settings: _settings, outputWidth: _exportWidth());
      final file = await _writeTempPng(bytes);
      await _output.share(
        file,
        mimeType: 'image/png',
        text: 'Montagem de fotos feita com o app Video to GIF',
      );
    } catch (_) {
      if (!mounted) return;
      _message('Não foi possível gerar a imagem.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _actions() {
    final busy = _saving || _sharing;
    return Column(
      children: [
        FilledButton.icon(
          onPressed: busy ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded),
          label: Text(_saving ? 'Salvando…' : 'Salvar na galeria'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy ? null : _share,
          icon: _sharing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.share_outlined),
          label: Text(_sharing ? 'Preparando…' : 'Compartilhar'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
      ],
    );
  }
}
