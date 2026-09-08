import 'dart:io';
import 'dart:math' as math;
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
import '../models/crop_rect.dart';
import '../models/photo_info.dart';
import '../services/collage_compositor.dart';
import '../services/imported_asset_store.dart';
import '../services/output_service.dart';
import 'photo_crop_page.dart';
import 'widgets/collage_cell_view.dart';
import 'widgets/collage_overlay_view.dart';
import 'widgets/collage_painter.dart';
import 'widgets/color_picker_sheet.dart';

/// Abas fixas no rodapé da tela de montagem — cada uma abre um painel com o
/// conteúdo daquela seção logo acima da barra de abas, substituindo a antiga
/// lista rolável de cards expansíveis.
enum _CollageTab { layout, aspect, margin, border, background, stickers, text }

/// Tela do editor de montagem de fotos: agrupa [photos] num layout (linha,
/// coluna ou grade), com margem/proporção/borda/cantos configuráveis (da
/// montagem inteira e de cada foto), fundo transparente/cor/imagem, stickers
/// e texto sobrepostos, reposicionamento/rotação/zoom por toque de cada
/// foto, recorte de uma foto específica e opções de trocar/substituir/
/// ajustar cor/espelhar/recentralizar cada célula. Prévia fixa em cima,
/// abas de edição fixas no rodapé (estilo CapCut/Canva).
class CollagePage extends StatefulWidget {
  const CollagePage({super.key, required this.photos});

  final List<PhotoInfo> photos;

  @override
  State<CollagePage> createState() => _CollagePageState();
}

class _CollagePageState extends State<CollagePage> {
  static const _output = OutputService();
  static const _stickerStore = ImportedAssetStore(ImportedAssetKind.sticker);
  static const _backgroundStore = ImportedAssetStore(
    ImportedAssetKind.backgroundImage,
  );

  /// Stickers prontos, embutidos no app (`assets/sticker/`) — aparecem antes
  /// dos importados pelo usuário na seção "Stickers".
  static const _bundledStickers = <(String path, String label)>[
    ('assets/sticker/heart.svg', 'Coração'),
    ('assets/sticker/star.svg', 'Estrela'),
    ('assets/sticker/thumbs_up.svg', 'Joinha'),
    ('assets/sticker/smiley.svg', 'Sorriso'),
    ('assets/sticker/sparkle.svg', 'Brilho'),
  ];

  late CollageSettings _settings = CollageSettings.forLayout(
    _defaultLayoutFor(widget.photos.length),
    widget.photos,
  );

  List<ImportedAsset> _importedStickers = [];
  List<ImportedAsset> _importedBackgrounds = [];

  final List<CollageSettings> _undoStack = [];
  final List<CollageSettings> _redoStack = [];

  String? _selectedOverlayId;

  /// Aba aberta no rodapé — `null` fecha o painel e deixa a prévia com o
  /// máximo de espaço. Começa em `layout`, equivalente ao
  /// `initiallyExpanded: true` que a seção de layout já tinha antes.
  _CollageTab? _activeTab = _CollageTab.layout;

  /// Alvo dos controles da aba "Borda e cantos": `false` = a montagem
  /// inteira, `true` = todas as fotos de uma vez. Só estado de UI (qual
  /// seletor está tocado agora) — não faz parte de [CollageSettings].
  bool _borderTargetsPhotos = false;

  bool _saving = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadImportedAssets();
    final ignored = widget.photos.length - _settings.cells.length;
    if (ignored > 0) {
      // Mais fotos do que cabe até no maior layout: avisa em vez de deixar o
      // usuário achar que elas entraram na montagem.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _message(
          ignored == 1
              ? 'A última foto escolhida não coube na montagem.'
              : 'As últimas $ignored fotos escolhidas não couberam na montagem.',
        );
      });
    }
  }

  /// Layout inicial com células suficientes para todas as [count] fotos
  /// escolhidas. Acima de 9 fotos cai na grade livre (até 4x4 = 16 células, o
  /// máximo dela) em vez de sempre na grade 3x3 — que descartava em silêncio
  /// tudo o que passasse da nona foto.
  static CollageLayout _defaultLayoutFor(int count) {
    if (count <= 2) return CollageLayout.row(count < 2 ? 2 : count);
    if (count == 3) return CollageLayout.row(3);
    if (count == 4) return const CollageLayout(kind: CollageLayoutKind.grid2x2);
    if (count <= 6) return const CollageLayout(kind: CollageLayoutKind.grid2x3);
    if (count <= 9) return const CollageLayout(kind: CollageLayoutKind.grid3x3);
    const maxSpan = CollageLayout.maxFreeGridSpan;
    final rows = ((count + maxSpan - 1) ~/ maxSpan).clamp(1, maxSpan);
    return CollageLayout.grid(maxSpan, rows);
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
      _dropSelectionIfGone();
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    setState(() {
      _undoStack.add(_settings);
      _settings = next;
      _dropSelectionIfGone();
    });
  }

  /// Solta a seleção quando a sobreposição selecionada não existe mais no
  /// estado atual — desfazer a criação de um sticker/texto deixava a barra de
  /// ações na tela apontando para algo que já tinha sumido, com todos os
  /// botões sem efeito nenhum.
  void _dropSelectionIfGone() {
    final id = _selectedOverlayId;
    if (id == null) return;
    if (_findSticker(id) == null && _findText(id) == null) {
      _selectedOverlayId = null;
    }
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
    final busy = _saving || _sharing;
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
          IconButton(
            tooltip: _saving ? 'Salvando…' : 'Salvar na galeria',
            onPressed: busy ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: _sharing ? 'Preparando…' : 'Compartilhar',
            onPressed: busy ? null : _share,
            icon: _sharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: Center(child: _preview())),
            ?toolbar,
            ?_activeTabPanel(),
            _footerTabs(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Rodapé de abas
  // ---------------------------------------------------------------------

  /// Painel da aba aberta: altura limitada com rolagem própria (seções mais
  /// longas, como Fundo, não estouram a tela), animado ao trocar/fechar aba.
  Widget? _activeTabPanel() {
    final tab = _activeTab;
    if (tab == null) return null;
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: _panelContentFor(tab),
        ),
      ),
    );
  }

  Widget _panelContentFor(_CollageTab tab) => switch (tab) {
    _CollageTab.layout => _layoutPanelContent(),
    _CollageTab.aspect => _aspectPanelContent(),
    _CollageTab.margin => _marginPanelContent(),
    _CollageTab.border => _borderPanelContent(),
    _CollageTab.background => _backgroundPanelContent(),
    _CollageTab.stickers => _stickersPanelContent(),
    _CollageTab.text => _textPanelContent(),
  };

  /// Título + valor atual de uma seção — mesmo resumo que o `LabeledSection`
  /// antigo mostrava, agora no topo do próprio painel em vez de no
  /// cabeçalho de um card expansível.
  Widget _panelHeader(String title, [String? value]) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (value != null)
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _footerTabs() {
    final theme = Theme.of(context);
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [for (final tab in _CollageTab.values) _footerTabButton(tab)],
      ),
    );
  }

  Widget _footerTabButton(_CollageTab tab) {
    final theme = Theme.of(context);
    final selected = _activeTab == tab;
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => setState(() => _activeTab = selected ? null : tab),
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_tabIcon(tab), color: color),
            const SizedBox(height: 4),
            Text(
              _tabLabel(tab),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _tabIcon(_CollageTab tab) => switch (tab) {
    _CollageTab.layout => Icons.grid_view_outlined,
    _CollageTab.aspect => Icons.aspect_ratio_rounded,
    _CollageTab.margin => Icons.space_dashboard_outlined,
    _CollageTab.border => Icons.crop_din_rounded,
    _CollageTab.background => Icons.wallpaper_rounded,
    _CollageTab.stickers => Icons.emoji_emotions_outlined,
    _CollageTab.text => Icons.text_fields_rounded,
  };

  String _tabLabel(_CollageTab tab) => switch (tab) {
    _CollageTab.layout => 'Layout',
    _CollageTab.aspect => 'Proporção',
    _CollageTab.margin => 'Margem',
    _CollageTab.border => 'Borda',
    _CollageTab.background => 'Fundo',
    _CollageTab.stickers => 'Stickers',
    _CollageTab.text => 'Texto',
  };

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
              // A borda da prévia é desenhada pelo mesmo `paintCollageBorder`
              // da exportação (antes era um Container pintado à mão aqui, que
              // podia divergir do PNG final).
              if (geometry.borderThickness > 0)
                Positioned.fill(
                  child: CustomPaint(painter: CollageBorderPainter(_settings)),
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
      for (final text in _settings.texts)
        (text.zIndex, _textOverlayWidget(text, size)),
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
      interactive: _activeTab == _CollageTab.stickers,
      onSelect: () => setState(() => _selectedOverlayId = sticker.id),
      onGestureStart: _pushUndoCheckpoint,
      onTransformChanged: (cx, cy, scale, rotation) => _update(
        _settings.replacingSticker(
          sticker.id,
          sticker.copyWith(
            centerX: cx,
            centerY: cy,
            scale: scale,
            rotation: rotation,
          ),
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
      interactive: _activeTab == _CollageTab.text,
      onSelect: () => setState(() => _selectedOverlayId = text.id),
      onGestureStart: _pushUndoCheckpoint,
      onTransformChanged: (cx, cy, scale, rotation) => _update(
        _settings.replacingText(
          text.id,
          text.copyWith(
            centerX: cx,
            centerY: cy,
            scale: scale,
            rotation: rotation,
          ),
        ),
        pushUndo: false,
      ),
      child: _textArt(text, size),
    );
  }

  Widget _stickerArt(CollageSticker sticker, Size canvasSize) {
    final refSize = canvasSize.shortestSide * CollageSticker.referenceSizeRatio;
    final content = switch (sticker.source) {
      CollageStickerSource.bundledSvg => SvgPicture.asset(
        sticker.assetPath!,
        fit: BoxFit.contain,
      ),
      CollageStickerSource.importedSvg => SvgPicture.file(
        File(sticker.imageFilePath!),
        fit: BoxFit.contain,
      ),
      CollageStickerSource.importedImage => Image.file(
        File(sticker.imageFilePath!),
        fit: BoxFit.contain,
      ),
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
        fontFamily: item.fontFamily,
        fontWeight: item.bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }

  Widget? _selectionToolbar() {
    final id = _selectedOverlayId;
    if (id == null) return null;
    final text = _findText(id);
    if (text == null && _findSticker(id) == null) return null;
    final isText = text != null;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 4,
        children: [
          if (isText)
            IconButton(
              tooltip: 'Editar',
              onPressed: () => _editSelectedText(id),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
          if (isText)
            IconButton(
              tooltip: 'Fonte',
              onPressed: () => _pickTextFont(id),
              icon: const Icon(Icons.font_download_outlined, size: 20),
            ),
          IconButton(
            tooltip: 'Duplicar',
            onPressed: () => _duplicateSelected(id, isText),
            icon: const Icon(Icons.copy_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Frente',
            onPressed: () => _bringToFront(id, isText),
            icon: const Icon(Icons.flip_to_front_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Trás',
            onPressed: () => _sendToBack(id, isText),
            icon: const Icon(Icons.flip_to_back_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Remover',
            onPressed: () => _removeSelected(id, isText),
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Layout"
  // ---------------------------------------------------------------------

  Widget _layoutPanelContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Layout'),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: CollageLayoutKind.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) =>
                _layoutThumb(CollageLayoutKind.values[index]),
          ),
        ),
        if (_settings.layout.kind == CollageLayoutKind.freeGrid) ...[
          const SizedBox(height: 14),
          _freeGridSteppers(),
        ],
        if (_settings.layout.kind == CollageLayoutKind.row ||
            _settings.layout.kind == CollageLayoutKind.column) ...[
          const SizedBox(height: 14),
          _rowColumnStepper(),
        ],
      ],
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
              child: _layoutIcon(kind, theme.colorScheme.primary),
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

  /// Ícone de cada opção de layout: uma grade de pontinhos desenhada com o
  /// número EXATO de colunas/linhas de cada uma — em vez de escolher entre
  /// os ícones prontos do Material (nenhum bate exatamente com "2 colunas
  /// por 3 linhas", por exemplo; `Icons.grid_on_outlined` usado antes para
  /// "Grade 2x3" na real parece uma grade 3x3, confundindo com a opção
  /// vizinha), garante que o ícone sempre corresponda ao layout real.
  Widget _layoutIcon(CollageLayoutKind kind, Color color) {
    final (columns, rows) = switch (kind) {
      CollageLayoutKind.row => (4, 1),
      CollageLayoutKind.column => (1, 4),
      CollageLayoutKind.grid2x2 => (2, 2),
      CollageLayoutKind.grid2x3 => (2, 3),
      CollageLayoutKind.grid3x3 => (3, 3),
      CollageLayoutKind.freeGrid => (0, 0),
    };
    if (kind == CollageLayoutKind.freeGrid) {
      return Icon(Icons.dashboard_customize_outlined, color: color);
    }
    const dot = 6.0;
    const gap = 3.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: gap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _freeGridSteppers() {
    final layout = _settings.layout;
    return Row(
      children: [
        Expanded(
          child: _stepperRow(
            'Colunas',
            layout.columns < 1 ? 2 : layout.columns,
            min: CollageLayout.minFreeGridSpan,
            max: CollageLayout.maxFreeGridSpan,
            onChanged: (v) => _applyLayout(layout.copyWith(columns: v)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _stepperRow(
            'Linhas',
            layout.rows < 1 ? 2 : layout.rows,
            min: CollageLayout.minFreeGridSpan,
            max: CollageLayout.maxFreeGridSpan,
            onChanged: (v) => _applyLayout(layout.copyWith(rows: v)),
          ),
        ),
      ],
    );
  }

  /// Contador de quantas fotos entram na linha/coluna única — mesmo padrão
  /// visual de [_freeGridSteppers], só que controlando o total de células em
  /// vez de colunas/linhas separadas (linha/coluna só tem um eixo com mais
  /// de uma célula).
  Widget _rowColumnStepper() {
    final layout = _settings.layout;
    final count = layout.cellCount < CollageLayout.minRowColumnCount
        ? CollageLayout.minRowColumnCount
        : layout.cellCount;
    return _stepperRow(
      'Fotos',
      count,
      min: CollageLayout.minRowColumnCount,
      max: CollageLayout.maxRowColumnCount,
      onChanged: (v) => _applyLayout(
        layout.kind == CollageLayoutKind.row
            ? CollageLayout.row(v)
            : CollageLayout.column(v),
      ),
    );
  }

  Widget _stepperRow(
    String label,
    int value, {
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(
          '$value',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
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
      CollageLayoutKind.grid2x2 => const CollageLayout(
        kind: CollageLayoutKind.grid2x2,
      ),
      CollageLayoutKind.grid2x3 => const CollageLayout(
        kind: CollageLayoutKind.grid2x3,
      ),
      CollageLayoutKind.grid3x3 => const CollageLayout(
        kind: CollageLayoutKind.grid3x3,
      ),
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

  Widget _marginPanelContent() {
    final percent =
        (_settings.marginRatio / CollageSettings.maxMarginRatio * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Margem', '$percent%'),
        Slider(
          min: CollageSettings.minMarginRatio,
          max: CollageSettings.maxMarginRatio,
          value: _settings.marginRatio.clamp(
            CollageSettings.minMarginRatio,
            CollageSettings.maxMarginRatio,
          ),
          label: '$percent%',
          onChangeStart: (_) => _pushUndoCheckpoint(),
          onChanged: (v) =>
              _update(_settings.copyWith(marginRatio: v), pushUndo: false),
        ),
      ],
    );
  }

  Widget _aspectPanelContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Proporção', _customAspectLabel()),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in CollageSettings.aspectPresets)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                labelStyle: Theme.of(context).textTheme.bodySmall,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                label: Text(preset.$1),
                selected: (_settings.aspectRatio - preset.$2).abs() < 0.001,
                onSelected: (_) =>
                    _update(_settings.copyWith(aspectRatio: preset.$2)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Slider(
          min: 0.4,
          max: 2.5,
          value: _settings.aspectRatio.clamp(0.4, 2.5),
          onChangeStart: (_) => _pushUndoCheckpoint(),
          onChanged: (v) =>
              _update(_settings.copyWith(aspectRatio: v), pushUndo: false),
        ),
        const SizedBox(height: 8),
        _CustomAspectRatioInput(
          onApply: (ratio) {
            _pushUndoCheckpoint();
            _update(
              _settings.copyWith(aspectRatio: ratio.clamp(0.4, 2.5)),
              pushUndo: false,
            );
          },
        ),
      ],
    );
  }

  /// `null` quando a proporção atual bate com um dos chips (o chip
  /// selecionado já mostra esse rótulo — repetir no cabeçalho do painel só
  /// duplicaria o mesmo texto na tela). Só devolve algo para uma proporção
  /// customizada pelo slider, sem chip equivalente para mostrá-la.
  String? _customAspectLabel() {
    for (final preset in CollageSettings.aspectPresets) {
      if ((preset.$2 - _settings.aspectRatio).abs() < 0.001) return null;
    }
    return _settings.aspectRatio.toStringAsFixed(2);
  }

  /// Espessura/arredondamento/cor atuais para o alvo escolhido no seletor
  /// "Montagem"/"Fotos" — quando o alvo é "Fotos", os 3 controles mexem em
  /// todas as células de uma vez ([CollageSettings.updatingAllCells]), então
  /// a primeira célula representa bem todas (não sobra mais nenhum jeito de
  /// uma foto divergir da outra, já que "Borda da foto" saiu do menu "...").
  CollageCellSettings? get _firstCell =>
      _settings.cells.isEmpty ? null : _settings.cells.first;

  Widget _borderPanelContent() {
    final theme = Theme.of(context);
    final targetsPhotos = _borderTargetsPhotos;
    final firstCell = _firstCell;
    final thickness = targetsPhotos
        ? (firstCell?.borderThicknessAtReference ?? 0)
        : _settings.borderThicknessAtReference;
    final maxThickness = targetsPhotos
        ? CollageCellSettings.maxBorderThickness
        : CollageSettings.maxBorderThickness;
    final cornerRatio = targetsPhotos
        ? (firstCell?.cornerRatio ?? 0)
        : _settings.cornerRatio;
    final maxCornerRatio = targetsPhotos
        ? CollageCellSettings.maxCornerRatio
        : CollageSettings.maxCornerRatio;
    final borderColor = targetsPhotos
        ? (firstCell?.borderColor ?? _settings.borderColor)
        : _settings.borderColor;
    void applyThickness(double v) {
      if (targetsPhotos) {
        _update(
          _settings.updatingAllCells(
            (c) => c.copyWith(borderThicknessAtReference: v),
          ),
          pushUndo: false,
        );
      } else {
        _update(
          _settings.copyWith(borderThicknessAtReference: v),
          pushUndo: false,
        );
      }
    }

    void applyCornerRatio(double v) {
      if (targetsPhotos) {
        _update(
          _settings.updatingAllCells((c) => c.copyWith(cornerRatio: v)),
          pushUndo: false,
        );
      } else {
        _update(_settings.copyWith(cornerRatio: v), pushUndo: false);
      }
    }

    void applyBorderColor(Color color) {
      if (targetsPhotos) {
        _update(
          _settings.updatingAllCells((c) => c.copyWith(borderColor: color)),
          pushUndo: false,
        );
      } else {
        _update(_settings.copyWith(borderColor: color), pushUndo: false);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Borda e cantos'),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Montagem'),
              selected: !targetsPhotos,
              onSelected: (_) => setState(() => _borderTargetsPhotos = false),
            ),
            ChoiceChip(
              label: const Text('Fotos'),
              selected: targetsPhotos,
              onSelected: (_) => setState(() => _borderTargetsPhotos = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sliderRow(
          label: 'Espessura da borda',
          value: thickness,
          min: 0,
          max: maxThickness,
          display: '${thickness.round()}px',
          onChanged: applyThickness,
        ),
        const SizedBox(height: 12),
        _sliderRow(
          label: 'Arredondamento dos cantos',
          value: cornerRatio,
          min: 0,
          max: maxCornerRatio,
          display: '${(cornerRatio / maxCornerRatio * 100).round()}%',
          onChanged: applyCornerRatio,
        ),
        if (thickness > 0) ...[
          const SizedBox(height: 4),
          Divider(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          _colorRow(
            'Cor da borda',
            borderColor,
            () => _pickBorderColor(
              current: borderColor,
              onSelected: applyBorderColor,
            ),
          ),
        ],
      ],
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

  /// Cor da borda — [current]/[onSelected] deixam esta mesma folha servir a
  /// borda da montagem inteira ou a borda de todas as fotos de uma vez,
  /// dependendo do alvo escolhido em [_borderPanelContent].
  void _pickBorderColor({
    required Color current,
    required ValueChanged<Color> onSelected,
  }) {
    // O checkpoint entra na primeira cor escolhida, não na abertura do painel:
    // abrir e fechar sem escolher nada não pode deixar um passo de desfazer
    // que aparenta não fazer nada.
    var checkpointPushed = false;
    showCollageColorPickerSheet(
      context: context,
      title: 'Cor da borda',
      initialColor: current,
      onColorSelected: (color) {
        if (!checkpointPushed) {
          checkpointPushed = true;
          _pushUndoCheckpoint();
        }
        onSelected(color);
      },
      previewImageBuilder: _renderPreviewImage,
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Fundo"
  // ---------------------------------------------------------------------

  Widget _backgroundPanelContent() {
    final background = _settings.background;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Fundo'),
        // `ChoiceChip`s em vez de `SegmentedButton`: os 3 rótulos
        // ("Transparente" principalmente) não cabem lado a lado com ícone
        // dentro da largura do painel do rodapé sem quebrar linha dentro do
        // próprio botão — chip quebra para a linha de baixo inteiro, nunca
        // no meio de uma palavra.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              (
                CollageBackgroundMode.transparent,
                'Transparente',
                Icons.check_box_outline_blank_rounded,
              ),
              (CollageBackgroundMode.color, 'Cor', Icons.palette_outlined),
              (CollageBackgroundMode.image, 'Imagem', Icons.image_outlined),
            ])
              ChoiceChip(
                avatar: Icon(entry.$3, size: 18),
                label: Text(entry.$2),
                selected: background.mode == entry.$1,
                onSelected: (_) => _update(
                  _settings.copyWith(
                    background: background.copyWith(mode: entry.$1),
                  ),
                ),
              ),
          ],
        ),
        if (background.mode == CollageBackgroundMode.color) ...[
          const SizedBox(height: 8),
          _colorRow(
            'Cor do fundo',
            background.color,
            _openBackgroundColorPicker,
          ),
        ],
        if (background.mode == CollageBackgroundMode.image) ...[
          const SizedBox(height: 12),
          _backgroundImagePicker(),
        ],
      ],
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
            return _importTile(
              onTap: _importBackgroundImage,
              label: 'Importar',
            );
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
    // Mesmo cuidado de [_pickBorderColor] com o histórico de desfazer.
    var checkpointPushed = false;
    showCollageColorPickerSheet(
      context: context,
      title: 'Cor do fundo',
      initialColor: _settings.background.color,
      onColorSelected: (color) {
        if (!checkpointPushed) {
          checkpointPushed = true;
          _pushUndoCheckpoint();
        }
        _update(
          _settings.copyWith(
            background: _settings.background.copyWith(
              mode: CollageBackgroundMode.color,
              color: color,
            ),
          ),
          pushUndo: false,
        );
      },
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
      _importedBackgrounds = _importedBackgrounds
          .where((a) => a.id != asset.id)
          .toList();
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
    final bytes = await composeCollage(
      settings: _settings,
      outputWidth: _previewSampleWidth(),
    );
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  int _previewSampleWidth() => 480;

  // ---------------------------------------------------------------------
  // Seção "Stickers" / "Texto"
  // ---------------------------------------------------------------------

  Widget _stickersPanelContent() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Stickers'),
        Text(
          'Toque para adicionar um sticker à montagem.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _bundledStickers.length + _importedStickers.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index < _bundledStickers.length) {
                final sticker = _bundledStickers[index];
                return GestureDetector(
                  onTap: () => _addBundledSticker(sticker),
                  child: _bundledStickerThumb(sticker),
                );
              }
              final importedIndex = index - _bundledStickers.length;
              if (importedIndex == _importedStickers.length) {
                return _importTile(onTap: _importSticker, label: 'Importar');
              }
              final asset = _importedStickers[importedIndex];
              return GestureDetector(
                onTap: () => _addStickerFromAsset(asset),
                onLongPress: () => _confirmRemoveSticker(asset),
                child: _assetThumb(asset, selected: false),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _bundledStickerThumb((String path, String label) sticker) {
    final theme = Theme.of(context);
    return Container(
      width: 62,
      height: 46,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: SvgPicture.asset(sticker.$1, fit: BoxFit.contain),
    );
  }

  void _addBundledSticker((String path, String label) sticker) {
    final item = CollageSticker(
      id: 's_${DateTime.now().microsecondsSinceEpoch}',
      source: CollageStickerSource.bundledSvg,
      assetPath: sticker.$1,
      label: sticker.$2,
      centerX: 0.5,
      centerY: 0.5,
      zIndex: _settings.nextZIndex,
    );
    _update(_settings.addingSticker(item));
    setState(() => _selectedOverlayId = item.id);
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
    final inUse = _settings.stickers
        .where((s) => s.imageFilePath == asset.filePath)
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover sticker?'),
        content: Text(
          inUse.isEmpty
              ? '"${asset.label}" vai ser removido da lista.'
              : '"${asset.label}" vai ser removido da lista e também da '
                    'montagem, onde está usado ${inUse.length} '
                    '${inUse.length == 1 ? 'vez' : 'vezes'}.',
        ),
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
    setState(
      () => _importedStickers = _importedStickers
          .where((a) => a.id != asset.id)
          .toList(),
    );
    if (inUse.isEmpty) return;
    // O arquivo acabou de ser apagado do aparelho: deixar as cópias já
    // colocadas na montagem apontando para ele quebrava a prévia e fazia a
    // exportação inteira falhar com "Não foi possível gerar a imagem".
    var updated = _settings;
    for (final sticker in inUse) {
      updated = updated.removingSticker(sticker.id);
    }
    _update(updated);
    setState(_dropSelectionIfGone);
  }

  Widget _textPanelContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Texto'),
        OutlinedButton.icon(
          onPressed: _addText,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Adicionar texto'),
        ),
      ],
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

  Future<String?> _promptTextInput({required String initial}) =>
      showDialog<String>(
        context: context,
        builder: (dialogContext) => _TextInputDialog(initial: initial),
      );

  /// Folha com as [bundledCollageFonts] em miniaturas "Aa", cada uma
  /// renderizada na própria fonte — mesmo padrão visual dos outros sheets
  /// de escolha (`showModalBottomSheet` + `Wrap`).
  void _pickTextFont(String id) {
    final item = _findText(id);
    if (item == null) return;
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
                    _FontThumb(
                      family: font.$1,
                      label: font.$2,
                      selected: item.fontFamily == font.$1,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _pushUndoCheckpoint();
                        _update(
                          _settings.replacingText(
                            id,
                            item.copyWith(
                              fontFamily: font.$1,
                              clearFontFamily: font.$1 == null,
                            ),
                          ),
                          pushUndo: false,
                        );
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
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: theme.colorScheme.primary,
              ),
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
      _update(
        _settings.replacingText(
          id,
          item.copyWith(zIndex: _settings.nextZIndex),
        ),
      );
    } else {
      final sticker = _findSticker(id);
      if (sticker == null) return;
      _update(
        _settings.replacingSticker(
          id,
          sticker.copyWith(zIndex: _settings.nextZIndex),
        ),
      );
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
    _update(
      isText ? _settings.removingText(id) : _settings.removingSticker(id),
    );
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
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          // Numa tela baixa (ou com a barra de navegação do sistema
          // ocupando espaço), a lista de itens pode não caber na altura
          // disponível — sem isto o `Column` simplesmente estourava por
          // baixo em vez de rolar (`isScrollControlled: true` deixa a folha
          // crescer até a tela quase inteira antes disso ser preciso).
          child: SingleChildScrollView(
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
                  leading: const Icon(Icons.crop_rounded),
                  title: const Text('Recortar'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openCropTool(index);
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
                ListTile(
                  leading: const Icon(Icons.center_focus_strong_outlined),
                  title: const Text('Recentralizar'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _recenterCell(index);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhotoForCell(int index) async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: 'Escolha uma foto',
      );
      final path = picked?.path;
      if (path == null) return;

      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final int width;
      final int height;
      try {
        final frame = await codec.getNextFrame();
        width = frame.image.width;
        height = frame.image.height;
        frame.image.dispose();
      } finally {
        codec.dispose();
      }

      final cell = _settings.cells[index];
      final replaced = cell
          .copyWith(
            photoPath: path,
            photoWidth: width,
            photoHeight: height,
            clearManualCrop: true,
          )
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
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          // Uma montagem com muitas células (grade livre até 9) pode ter
          // miniaturas demais para caber na altura da folha sem rolar.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trocar com qual foto?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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

            Widget adjustSlider(
              String label,
              double value,
              CollageCellSettings Function(double) apply,
            ) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
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
                    Text(
                      'Ajustar cor',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    adjustSlider(
                      'Brilho',
                      cell.brightness,
                      (v) => cell.copyWith(brightness: v),
                    ),
                    adjustSlider(
                      'Contraste',
                      cell.contrast,
                      (v) => cell.copyWith(contrast: v),
                    ),
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

  /// Mais um quarto de volta a partir de onde a foto já estiver — continua
  /// útil como atalho rápido mesmo depois de girar livremente com o dedo.
  void _rotateCell(int index) {
    final cell = _settings.cells[index];
    _update(
      _settings.replacingCell(
        index,
        cell.copyWith(rotation: cell.rotation + math.pi / 2),
      ),
    );
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

  /// Volta ao enquadramento padrão (deslocamento/zoom/rotação/espelhamento),
  /// mantendo foto, recorte manual, cor e borda — o antigo comportamento do
  /// duplo toque, agora um item do menu já que o duplo toque passa a
  /// alternar preencher/ajustar.
  void _recenterCell(int index) {
    final cell = _settings.cells[index];
    _pushUndoCheckpoint();
    _update(
      _settings.replacingCell(index, cell.resetFraming()),
      pushUndo: false,
    );
  }

  /// Proporção que a célula [index] tem no layout atual — todas as células de
  /// um mesmo layout compartilham a mesma proporção (a grade sempre gera
  /// larguras/alturas uniformes), então basta calcular contra um canvas de
  /// referência do mesmo formato da montagem (`_settings.aspectRatio`) em vez
  /// de depender do tamanho real da prévia na tela.
  double _cellAspectRatioFor(int index) {
    const refWidth = 1000.0;
    final refHeight = refWidth / _settings.aspectRatio;
    final rects = _settings.layout.cellRectsFor(
      Size(refWidth, refHeight),
      _settings.marginRatio,
    );
    if (index >= rects.length) return 1.0;
    final rect = rects[index];
    if (rect.width <= 0 || rect.height <= 0) return 1.0;
    return rect.width / rect.height;
  }

  /// Abre o recorte de uma foto específica, travado na proporção da própria
  /// célula (o resultado sempre precisa preencher a célula sem sobra).
  Future<void> _openCropTool(int index) async {
    final cell = _settings.cells[index];
    if (!cell.hasPhoto) return;
    final crop = await Navigator.of(context).push<CropRect>(
      MaterialPageRoute(
        builder: (_) => PhotoCropPage(
          photoPath: cell.photoPath!,
          photoWidth: cell.photoWidth,
          photoHeight: cell.photoHeight,
          aspectRatio: _cellAspectRatioFor(index),
          initialCrop: cell.manualCrop,
        ),
      ),
    );
    if (crop == null || !mounted) return;
    _pushUndoCheckpoint();
    _update(
      _settings.replacingCell(index, cell.copyWith(manualCrop: crop)),
      pushUndo: false,
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
    final path =
        '${dir.path}/montagem_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await composeCollage(
        settings: _settings,
        outputWidth: _exportWidth(),
      );
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
      final bytes = await composeCollage(
        settings: _settings,
        outputWidth: _exportWidth(),
      );
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
}

/// Diálogo de texto que é dono do próprio [TextEditingController]. O
/// controller precisa viver e morrer junto com o State do diálogo: solto num
/// método `async`, ou vazava (nunca era liberado) ou era liberado assim que
/// `showDialog` retornava — ainda durante a animação de saída, com o campo
/// montado e usando um controller já descartado.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({required this.initial});

  final String initial;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Texto'),
      content: TextField(controller: _controller, autofocus: true, maxLines: 3),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Campo para digitar uma proporção W:H exata, além dos chips de preset e do
/// slider livre já existentes na aba "Proporção". Os dois `TextEditingController`
/// têm ciclo de vida próprio (criar/liberar), por isso este pequeno
/// `StatefulWidget` privado — mesmo padrão de [_TextInputDialog] — em vez de
/// controllers soltos em `_CollagePageState`, que é rebuilda a cada
/// `setState` da tela inteira e não é a dona natural desse estado.
class _CustomAspectRatioInput extends StatefulWidget {
  const _CustomAspectRatioInput({required this.onApply});

  final ValueChanged<double> onApply;

  @override
  State<_CustomAspectRatioInput> createState() =>
      _CustomAspectRatioInputState();
}

class _CustomAspectRatioInputState extends State<_CustomAspectRatioInput> {
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _apply() {
    final w = double.tryParse(_widthController.text.replaceAll(',', '.'));
    final h = double.tryParse(_heightController.text.replaceAll(',', '.'));
    if (w == null || h == null || w <= 0 || h <= 0) return;
    widget.onApply(w / h);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _widthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Largura',
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('：', style: theme.textTheme.titleMedium),
        ),
        Expanded(
          child: TextField(
            controller: _heightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Altura',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Aplicar proporção',
          onPressed: _apply,
          icon: const Icon(Icons.check_rounded),
        ),
      ],
    );
  }
}

/// Miniatura "Aa" de uma fonte, renderizada na própria [family] — mesma
/// forma de miniatura em grade usada por [_bundledStickerThumb].
class _FontThumb extends StatelessWidget {
  const _FontThumb({
    required this.family,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String? family;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
}
