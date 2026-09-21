import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_svg/flutter_svg.dart';

import 'models/collage_background.dart';
import 'models/sticker_catalog.dart';
import 'models/collage_cell.dart';
import 'models/collage_export.dart';
import 'models/collage_layout.dart';
import 'models/collage_settings.dart';
import 'models/collage_sticker.dart';
import '../../core/models/collage_text.dart';
import '../../core/models/default_colors.dart';
import '../../core/models/photo_info.dart';
import 'services/collage_animation.dart';
import 'services/collage_export_runner.dart';
import 'services/collage_compositor.dart';
import '../../core/ffmpeg/ffmpeg_service.dart';
import '../../core/services/imported_asset_store.dart';
import '../../core/services/imported_font_store.dart';
import '../../core/services/output_service.dart';
import '../../core/services/sticker_folder_store.dart';
import '../../core/ui/app_bar_title.dart';
import 'widgets/background_image_view.dart';
import '../../core/ui/checkerboard_background.dart';
import 'widgets/collage_cell_view.dart';
import '../../core/ui/collage_overlay_view.dart';
import '../../core/ui/panel_rows.dart';
import '../../core/ui/text_overlay_editor.dart';
import 'painting/collage_painter.dart';
import '../../core/ui/color_picker_sheet.dart';
import 'widgets/export_progress_dialog.dart';
import 'widgets/folder_tab.dart';
import 'widgets/asset_thumbs.dart';
import 'widgets/cell_actions.dart';
import 'widgets/font_thumb.dart';
import 'widgets/panels/collage_panel_actions.dart';
import 'widgets/panels/aspect_panel.dart';
import 'widgets/panels/background_panel.dart';
import 'widgets/panels/border_panel.dart';
import 'widgets/panels/color_panel.dart';
import 'widgets/panels/margin_panel.dart';
import '../../core/ui/text_input_dialog.dart';
import 'widgets/panels/layout_panel.dart';
import '../../core/ui/preview_settings_panel.dart';

/// Geometria do sticker/texto selecionado, na medida necessária para
/// posicionar as alças de redimensionar/girar por fora dele (ver
/// `_CollagePageState._selectedHandlesLayer`) — junto de como escrever a
/// transformação de volta no item certo, já que sticker e texto usam
/// `copyWith`/`replacingSticker`/`replacingText` diferentes.
class _SelectedOverlayGeometry {
  const _SelectedOverlayGeometry({
    required this.centerX,
    required this.centerY,
    required this.scale,
    required this.rotation,
    required this.minScale,
    required this.maxScale,
    required this.naturalSize,
    required this.apply,
  });

  final double centerX;
  final double centerY;
  final double scale;
  final double rotation;
  final double minScale;
  final double maxScale;

  /// Tamanho do conteúdo em escala 1 — o efetivo na tela é
  /// `naturalSize * scale`.
  final Size naturalSize;

  final void Function(
    double centerX,
    double centerY,
    double scale,
    double rotation,
  )
  apply;
}

/// Abas fixas no rodapé da tela de montagem — cada uma abre um painel com o
/// conteúdo daquela seção logo acima da barra de abas, substituindo a antiga
/// lista rolável de cards expansíveis.
enum _CollageTab {
  layout,
  aspect,
  margin,
  border,
  background,
  color,
  stickers,
  text,
  // Última aba da barra nas três telas de edição (vídeo, foto e montagem) —
  // configurações gerais, não desta montagem em si. Como a barra itera
  // `_CollageTab.values` direto, ser o último valor do enum já garante que
  // fica por último na barra.
  settings,
}

class CollagePage extends StatefulWidget {
  const CollagePage({super.key, required this.photos});

  final List<PhotoInfo> photos;

  @override
  State<CollagePage> createState() => _CollagePageState();
}

class _CollagePageState extends State<CollagePage> {
  static const _output = OutputService();

  /// Exportação da montagem: tamanhos, progresso, cancelamento e a geração
  /// do arquivo final. A tela fica só com as folhas de escolha e o pop-up.
  final _export = CollageExportRunner();
  static const _stickerStore = ImportedAssetStore(ImportedAssetKind.sticker);
  static const _backgroundStore = ImportedAssetStore(
    ImportedAssetKind.backgroundImage,
  );
  static const _folderStore = StickerFolderStore();
  static const _fontStore = ImportedFontStore();

  /// Id da pasta recém-criada que ainda precisa ficar visível na fileira —
  /// ver [_createStickerFolder]. `null` quando não há rolagem pendente.
  String? _pendingFolderScrollId;

  late CollageSettings _settings = CollageSettings.forLayout(
    _defaultLayoutFor(widget.photos.length),
    widget.photos,
  );

  /// Valor próprio da linha "Tudo" da aba "Margem" — só muda quando ELA é
  /// arrastada (que também iguala `outerMarginRatio`/`innerMarginRatio` a
  /// esse valor). Sem isto, "Tudo" mostrava a média das outras duas a cada
  /// rebuild, então o próprio slider se movia sozinho ao arrastar "Externa"
  /// ou "Entre fotos" — o oposto do que uma pessoa espera de um slider que
  /// não tocou.
  late double _marginAllValue =
      (_settings.outerMarginRatio + _settings.innerMarginRatio) / 2;

  List<ImportedAsset> _importedStickers = [];
  List<ImportedAsset> _importedBackgrounds = [];

  /// Fontes próprias do usuário, já registradas no engine por
  /// [ImportedFontStore.loadAll] — entram na folha de fontes ao lado das
  /// embutidas.
  List<ImportedFont> _importedFonts = [];

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

  /// Mesmo papel de [_borderTargetsPhotos], para a aba "Fundo": `false` = o
  /// fundo da montagem inteira, `true` = o fundo de dentro de cada foto.
  bool _backgroundTargetsPhotos = false;

  /// `true` com o painel do rodapé encolhido para só a alça — recolher NÃO é
  /// fechar: a aba continua sendo a aba aberta, então sticker e texto seguem
  /// selecionáveis e moviméis na prévia enquanto os controles deles estão
  /// fora da tela.
  bool _panelCollapsed = false;

  /// `true` quando o chip "x:y" da aba "Proporção" está escolhido — é ele que
  /// mostra os campos de largura e altura. Fica ligado sozinho quando a
  /// proporção atual não bate com nenhum chip pronto (arrastar o slider, por
  /// exemplo): nesse caso a proporção é customizada de fato.
  bool _customAspectSelected = false;

  /// Pasta aberta na aba "Stickers": id de uma embutida ([BundledStickerFolder.id])
  /// ou de uma criada pelo usuário ([BundledStickerFolder.id]).
  String _stickerFolderId = BundledStickerFolder.reactions.id;

  /// Pastas criadas pelo usuário, carregadas junto com os stickers
  /// importados — ver [StickerFolderStore].
  List<StickerFolder> _customFolders = [];

  bool _saving = false;
  bool _sharing = false;

  /// Campo de escrever texto que fica no próprio painel da aba "Texto" — o
  /// mesmo campo cria uma caixa nova e edita a selecionada, sem abrir
  /// diálogo nenhum.
  final _textController = TextEditingController();
  final _textFocus = FocusNode();

  /// Progresso da exportação animada, ouvido pelo pop-up
  /// [ExportProgressDialog] — que vive numa rota própria e por isso não é
  /// reconstruído pelo `setState` desta tela.

  /// `true` entre pedir o cancelamento e a exportação de fato parar.

  /// Id da caixa sendo editada pelo campo; `null` = o campo está criando uma
  /// caixa nova.
  String? _editingTextId;

  @override
  void dispose() {
    _textController.dispose();
    _textFocus.dispose();
    _export.dispose();
    super.dispose();
  }

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
    final folders = await _folderStore.loadAll();
    final fonts = await _fontStore.loadAll();
    if (!mounted) return;
    setState(() {
      _importedStickers = stickers;
      _importedBackgrounds = backgrounds;
      _customFolders = folders;
      _importedFonts = fonts;
      _dropStickerFolderIfGone();
    });
  }

  /// Volta para "Importados" quando a pasta aberta não existe mais — só
  /// acontece se ela for apagada, mas deixa a barra sempre com alguma pasta
  /// marcada em vez de nenhuma.
  void _dropStickerFolderIfGone() {
    final exists =
        BundledStickerFolder.values.any((f) => f.id == _stickerFolderId) ||
        _customFolders.any((f) => f.id == _stickerFolderId);
    if (!exists) _stickerFolderId = BundledStickerFolder.imported.id;
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

  /// As três ações que as abas e as ações de célula devolvem para a tela.
  late final _panelActions = CollagePanelActions(
    update: _update,
    pushUndoCheckpoint: _pushUndoCheckpoint,
    message: _message,
  );

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
    // Desfazer/remover a caixa que estava sendo editada deixava o campo do
    // painel apontando para algo que não existe mais.
    final editingId = _editingTextId;
    if (editingId != null && _findText(editingId) == null) {
      _editingTextId = null;
      _textController.clear();
    }
  }

  /// Id da sobreposição cuja seleção está *visível* agora: a moldura, a alça
  /// de redimensionar e a barra de ações só aparecem enquanto a aba dona do
  /// item estiver aberta ("Stickers" para sticker, "Texto" para texto) — as
  /// mesmas abas em que `CollageOverlayView.interactive` já deixa mexer nele.
  /// Fora delas os controles não fazem nada, e a moldura em volta de um texto
  /// enquanto se ajusta o fundo da montagem só polui a prévia.
  /// [_selectedOverlayId] continua guardado ao trocar de aba, então voltando
  /// para ela a moldura reaparece no mesmo item.
  String? get _activeSelectionId {
    final id = _selectedOverlayId;
    if (id == null) return null;
    return switch (_activeTab) {
      _CollageTab.stickers => _findSticker(id) == null ? null : id,
      _CollageTab.text => _findText(id) == null ? null : id,
      _ => null,
    };
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
        title: const AppBarTitle('Montagem'),
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
            Expanded(
              child: PreviewAreaBackground(child: Center(child: _preview())),
            ),
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
        // Mesmo teto do rodapé das outras telas (ver
        // `EditorTabsFooter.maxPanelHeight`): o painel cobre a prévia, e o
        // que passar daqui continua acessível pela rolagem que ele já tem.
        constraints: const BoxConstraints(maxHeight: 200),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _panelDragHandle(),
            if (!_panelCollapsed)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: _panelContentFor(tab),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Alça no topo do painel: puxar para baixo encolhe o painel até só ela,
  /// puxar para cima traz os controles de volta, e tocar alterna os dois.
  /// Encolher deixa a prévia com quase toda a tela sem perder a aba aberta —
  /// dá para arrastar o sticker ou o texto e depois voltar aos controles de
  /// onde parou. Para fechar mesmo, é tocar de novo na aba do rodapé.
  Widget _panelDragHandle() {
    final theme = Theme.of(context);
    return GestureDetector(
      key: const ValueKey('collagePanelHandle'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _panelCollapsed = !_panelCollapsed),
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity;
        if (velocity == null || velocity == 0) return;
        setState(() => _panelCollapsed = velocity > 0);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _panelContentFor(_CollageTab tab) => switch (tab) {
    _CollageTab.layout => CollageLayoutPanel(
      layout: _settings.layout,
      onSelectKind: _selectLayoutKind,
      onApplyLayout: _applyLayout,
    ),
    _CollageTab.aspect => CollageAspectPanel(
      settings: _settings,
      actions: _panelActions,
      customSelected: _customAspectSelected,
      onCustomSelected: (v) => setState(() => _customAspectSelected = v),
    ),
    _CollageTab.margin => CollageMarginPanel(
      settings: _settings,
      actions: _panelActions,
      marginAllValue: _marginAllValue,
      onMarginAllChanged: (v) {
        _marginAllValue = v;
        _update(
          _settings.copyWith(outerMarginRatio: v, innerMarginRatio: v),
          pushUndo: false,
        );
      },
      onResetMargins: () {
        _marginAllValue = 0;
        _update(_settings.copyWith(outerMarginRatio: 0, innerMarginRatio: 0));
      },
    ),
    _CollageTab.border => CollageBorderPanel(
      settings: _settings,
      actions: _panelActions,
      targetsPhotos: _borderTargetsPhotos,
      onTargetChanged: (v) => setState(() => _borderTargetsPhotos = v),
      firstCell: _firstCell,
      previewImageBuilder: _renderPreviewImage,
    ),
    _CollageTab.background => CollageBackgroundPanel(
      targetBackground: _targetBackground,
      targetsPhotos: _backgroundTargetsPhotos,
      onTargetChanged: (v) => setState(() => _backgroundTargetsPhotos = v),
      importedBackgrounds: _importedBackgrounds,
      onApply: _applyBackground,
      onImport: _importBackgroundImage,
      onRemoveImported: _confirmRemoveBackground,
      onPushUndoCheckpoint: _pushUndoCheckpoint,
      previewImageBuilder: _renderPreviewImage,
    ),
    _CollageTab.color => CollageColorPanel(
      settings: _settings,
      actions: _panelActions,
    ),
    _CollageTab.stickers => _stickersPanelContent(),
    _CollageTab.text => _textPanelContent(),
    _CollageTab.settings => const PreviewSettingsPanel(),
  };

  Widget _footerTabs() {
    final theme = Theme.of(context);
    return Container(
      height: 60,
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
      onTap: () => setState(() {
        _activeTab = selected ? null : tab;
        // Abrir (ou trocar de) aba sempre mostra o conteúdo: recolhido é um
        // estado do painel aberto, não algo que a aba herda.
        _panelCollapsed = false;
      }),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_tabIcon(tab), size: 20, color: color),
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
    _CollageTab.color => Icons.tune_rounded,
    _CollageTab.stickers => Icons.emoji_emotions_outlined,
    _CollageTab.text => Icons.text_fields_rounded,
    _CollageTab.settings => Icons.settings_rounded,
  };

  String _tabLabel(_CollageTab tab) => switch (tab) {
    _CollageTab.layout => 'Layout',
    _CollageTab.aspect => 'Proporção',
    _CollageTab.margin => 'Margem',
    _CollageTab.border => 'Borda',
    _CollageTab.background => 'Fundo',
    _CollageTab.color => 'Cor',
    _CollageTab.stickers => 'Stickers',
    _CollageTab.text => 'Texto',
    _CollageTab.settings => 'Ajustes',
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
                              // Com "Stickers" ou "Texto" aberto no rodapé, a
                              // foto para de responder a gesto — só um dos
                              // dois grupos (fotos, ou stickers/texto) pode
                              // ser movido por vez, o mesmo motivo que
                              // CollageOverlayView.interactive já aplica ao
                              // contrário nesses dois casos.
                              interactive:
                                  _activeTab != _CollageTab.stickers &&
                                  _activeTab != _CollageTab.text,
                              onGestureStart: _pushUndoCheckpoint,
                              onChanged: (cell) => _update(
                                _settings.replacingCell(i, cell),
                                pushUndo: false,
                              ),
                              onMenu: () => openCollageCellMenu(
                                i,
                                context,
                                settings: () => _settings,
                                actions: _panelActions,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              ..._overlayWidgets(size),
              // Sempre depois (por cima) das sobreposições, sem ligar para
              // o zIndex de quem está selecionado — ver o porquê no doc de
              // `CollageOverlayView`.
              ..._selectedHandlesWidgets(size),
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
        return BackgroundImageView(path: path);
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
      selected: _activeSelectionId == sticker.id,
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
      selected: _activeSelectionId == text.id,
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
      child: textOverlayArt(text, size),
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

  // ---------------------------------------------------------------------
  // Alças de redimensionar/girar do item selecionado — numa camada própria,
  // sempre por cima de tudo na pilha principal (ver o porquê no doc de
  // `CollageOverlayView`), calculadas analiticamente em vez de medidas em
  // tempo de execução.
  // ---------------------------------------------------------------------

  /// Tamanho natural (escala 1) do conteúdo de um sticker — mesmo `refSize`
  /// quadrado que [_stickerArt] usa.
  Size _stickerNaturalSize(CollageSticker sticker, Size canvasSize) {
    final refSize = canvasSize.shortestSide * CollageSticker.referenceSizeRatio;
    return Size(refSize, refSize);
  }

  /// Geometria + como aplicar a transformação de volta, para o sticker ou
  /// texto selecionado agora — `null` fora das abas "Stickers"/"Texto" ou
  /// sem nada selecionado (mesma regra de [_activeSelectionId]).
  _SelectedOverlayGeometry? _selectedOverlayGeometry(Size canvasSize) {
    final id = _activeSelectionId;
    if (id == null) return null;

    final sticker = _findSticker(id);
    if (sticker != null) {
      return _SelectedOverlayGeometry(
        centerX: sticker.centerX,
        centerY: sticker.centerY,
        scale: sticker.scale,
        rotation: sticker.rotation,
        minScale: CollageSticker.minScale,
        maxScale: CollageSticker.maxScale,
        naturalSize: _stickerNaturalSize(sticker, canvasSize),
        apply: (cx, cy, s, r) => _update(
          _settings.replacingSticker(
            id,
            sticker.copyWith(centerX: cx, centerY: cy, scale: s, rotation: r),
          ),
          pushUndo: false,
        ),
      );
    }

    final text = _findText(id);
    if (text != null) {
      return _SelectedOverlayGeometry(
        centerX: text.centerX,
        centerY: text.centerY,
        scale: text.scale,
        rotation: text.rotation,
        minScale: CollageTextItem.minScale,
        maxScale: CollageTextItem.maxScale,
        naturalSize: textOverlayNaturalSize(text, canvasSize),
        apply: (cx, cy, s, r) => _update(
          _settings.replacingText(
            id,
            text.copyWith(centerX: cx, centerY: cy, scale: s, rotation: r),
          ),
          pushUndo: false,
        ),
      );
    }
    return null;
  }

  bool _resizeHandleCheckpointPushed = false;
  bool _rotateHandleCheckpointPushed = false;

  /// Posição (em pixels locais do canvas) que a camada acumula a partir de
  /// [event.delta] durante um arrasto da alça de girar — não há RenderBox
  /// para medir o dedo direto, então a posição vem de somar os deltas a
  /// partir de onde a alça estava no toque inicial. Reiniciada em
  /// [_onRotateHandlePointerDown].
  Offset? _rotatePointerPos;
  double? _lastRotateAngle;

  /// Mesma conta de [CollageOverlayView] (removida de lá): desfaz a rotação
  /// atual do vetor de arrasto e soma as duas componentes locais — arrastar
  /// para longe do centro (direita/baixo, sem girar) cresce; para perto,
  /// encolhe — como fração de [canvasSize].shortestSide.
  void _onResizeHandlePointerMove(
    PointerMoveEvent event,
    _SelectedOverlayGeometry geometry,
    Size canvasSize,
  ) {
    final reference = canvasSize.shortestSide;
    if (reference <= 0) return;
    final cosA = math.cos(geometry.rotation);
    final sinA = math.sin(geometry.rotation);
    final local = Offset(
      event.delta.dx * cosA + event.delta.dy * sinA,
      -event.delta.dx * sinA + event.delta.dy * cosA,
    );
    final scaleDelta = (local.dx + local.dy) / reference;
    if (scaleDelta == 0) return;
    final newScale = (geometry.scale + geometry.scale * scaleDelta).clamp(
      geometry.minScale,
      geometry.maxScale,
    );
    if (newScale == geometry.scale) return;
    if (!_resizeHandleCheckpointPushed) {
      _resizeHandleCheckpointPushed = true;
      _pushUndoCheckpoint();
    }
    geometry.apply(
      geometry.centerX,
      geometry.centerY,
      newScale,
      geometry.rotation,
    );
  }

  void _onRotateHandlePointerDown(Offset handleCenter) {
    _rotateHandleCheckpointPushed = false;
    _rotatePointerPos = handleCenter;
    _lastRotateAngle = null;
  }

  void _onRotateHandlePointerMove(
    PointerMoveEvent event,
    _SelectedOverlayGeometry geometry,
    Offset center,
  ) {
    final pos = (_rotatePointerPos ?? center) + event.delta;
    _rotatePointerPos = pos;
    final vector = pos - center;
    if (vector.distance < 1) return;
    final angle = math.atan2(vector.dy, vector.dx);
    final last = _lastRotateAngle;
    _lastRotateAngle = angle;
    if (last == null) return;
    var delta = angle - last;
    // Normaliza a virada de -pi/pi, senão passar por trás do overlay daria
    // um giro de volta inteira num quadro só.
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    if (delta == 0) return;
    if (!_rotateHandleCheckpointPushed) {
      _rotateHandleCheckpointPushed = true;
      _pushUndoCheckpoint();
    }
    geometry.apply(
      geometry.centerX,
      geometry.centerY,
      geometry.scale,
      geometry.rotation + delta,
    );
  }

  /// As duas alças do item selecionado, sempre por cima de tudo — ver o doc
  /// de `CollageOverlayView` para o porquê de não morarem mais dentro dele.
  List<Widget> _selectedHandlesWidgets(Size canvasSize) {
    final geometry = _selectedOverlayGeometry(canvasSize);
    if (geometry == null) return const [];

    final center = Offset(
      geometry.centerX * canvasSize.width,
      geometry.centerY * canvasSize.height,
    );
    final halfW = geometry.naturalSize.width * geometry.scale / 2;
    final halfH = geometry.naturalSize.height * geometry.scale / 2;
    final cosR = math.cos(geometry.rotation);
    final sinR = math.sin(geometry.rotation);
    Offset rotate(Offset local) => Offset(
      local.dx * cosR - local.dy * sinR,
      local.dx * sinR + local.dy * cosR,
    );

    final resizeCenter = center + rotate(Offset(halfW, halfH));
    final rotateCenter = center + rotate(Offset(halfW, -halfH));

    return [
      _handleCircle(
        center: resizeCenter,
        icon: Icons.open_in_full_rounded,
        onPointerDown: (_) => _resizeHandleCheckpointPushed = false,
        onPointerMove: (event) =>
            _onResizeHandlePointerMove(event, geometry, canvasSize),
      ),
      _handleCircle(
        center: rotateCenter,
        icon: Icons.rotate_right_rounded,
        onPointerDown: (_) => _onRotateHandlePointerDown(rotateCenter),
        onPointerMove: (event) =>
            _onRotateHandlePointerMove(event, geometry, center),
      ),
    ];
  }

  Widget _handleCircle({
    required Offset center,
    required IconData icon,
    required void Function(PointerDownEvent) onPointerDown,
    required void Function(PointerMoveEvent) onPointerMove,
  }) {
    final theme = Theme.of(context);
    const diameter = 24.0;
    // A área de toque é maior que o círculo visual (48dp, o mínimo
    // recomendado) para não ficar difícil de acertar a alça em telas
    // pequenas ou com dedos maiores — o círculo continua do mesmo tamanho e
    // no mesmo ponto de antes, só centralizado numa área de toque maior.
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

  Widget? _selectionToolbar() {
    final id = _activeSelectionId;
    if (id == null) return null;
    final isText = _findText(id) != null;
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
  /// receber uma foto ao toque (ver [CollageCellView]'s `+`), mas já com a
  /// borda/canto/fundo das fotos que já estão na montagem; células
  /// excedentes (quando o layout encolhe) são descartadas.
  void _applyLayout(CollageLayout layout) {
    final oldCells = _settings.cells;
    final cells = List<CollageCellSettings>.generate(
      layout.cellCount,
      (i) => i < oldCells.length
          ? oldCells[i]
          : _settings.withSharedCellStyle(const CollageCellSettings()),
    );
    _update(_settings.copyWith(layout: layout, cells: cells));
  }

  // ---------------------------------------------------------------------
  // Seção "Margem" / "Proporção" / "Borda e cantos"
  // ---------------------------------------------------------------------

  /// Espessura/arredondamento/cor atuais para o alvo escolhido no seletor
  /// "Montagem"/"Fotos" — quando o alvo é "Fotos", os 3 controles mexem em
  /// todas as células de uma vez ([CollageSettings.updatingAllCells]), então
  /// a primeira célula representa bem todas (não sobra mais nenhum jeito de
  /// uma foto divergir da outra, já que "Borda da foto" saiu do menu "...").
  CollageCellSettings? get _firstCell =>
      _settings.cells.isEmpty ? null : _settings.cells.first;

  // ---------------------------------------------------------------------
  // Seção "Fundo"
  // ---------------------------------------------------------------------

  /// Fundo do alvo escolhido no seletor "Montagem"/"Fotos": o da montagem
  /// inteira ou o de dentro das fotos. Com o alvo "Fotos" os controles mexem
  /// em todas as células de uma vez ([CollageSettings.updatingAllCells]),
  /// então a primeira célula representa bem todas — mesma lógica de
  /// [_borderPanelContent].
  CollageBackground get _targetBackground => _backgroundTargetsPhotos
      ? (_firstCell?.background ?? const CollageBackground())
      : _settings.background;

  void _applyBackground(CollageBackground background, {bool pushUndo = true}) {
    _update(
      _backgroundTargetsPhotos
          ? _settings.updatingAllCells(
              (cell) => cell.copyWith(background: background),
            )
          : _settings.copyWith(background: background),
      pushUndo: pushUndo,
    );
  }

  Future<void> _importBackgroundImage() async {
    try {
      final asset = await _backgroundStore.import();
      if (!mounted) return;
      setState(() => _importedBackgrounds = [..._importedBackgrounds, asset]);
      _applyBackground(
        _targetBackground.copyWith(
          mode: CollageBackgroundMode.image,
          imagePath: asset.filePath,
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
    // A imagem apagada pode estar em uso como fundo da montagem, das fotos ou
    // dos dois ao mesmo tempo — quem apontava para o arquivo que sumiu volta
    // para transparente, independente do alvo selecionado agora.
    var updated = _settings;
    if (updated.background.imagePath == asset.filePath) {
      updated = updated.copyWith(
        background: updated.background.copyWith(
          mode: CollageBackgroundMode.transparent,
          clearImagePath: true,
        ),
      );
    }
    if (updated.cells.any((c) => c.background.imagePath == asset.filePath)) {
      updated = updated.updatingAllCells(
        (cell) => cell.background.imagePath == asset.filePath
            ? cell.copyWith(
                background: cell.background.copyWith(
                  mode: CollageBackgroundMode.transparent,
                  clearImagePath: true,
                ),
              )
            : cell,
      );
    }
    if (!identical(updated, _settings)) _update(updated);
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
  // Seção "Ajustar cor"
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // Seção "Stickers" / "Texto"
  // ---------------------------------------------------------------------

  /// Abas embutidas que aparecem na fileira.
  ///
  /// "Novos" fica de fora enquanto está vazia: ela só existe para receber
  /// sticker solto em `assets/sticker` depois, e uma aba vazia a mais em
  /// toda instalação só empurraria o botão de criar pasta para fora da tela.
  static List<BundledStickerFolder> get _visibleBundledFolders => [
    for (final folder in BundledStickerFolder.values)
      if (folder != BundledStickerFolder.novos ||
          descobertosFor(BundledStickerFolder.novos).isNotEmpty)
        folder,
  ];

  /// Pasta embutida aberta agora, ou `null` quando a aberta é uma criada
  /// pelo usuário.
  BundledStickerFolder? get _openBundledFolder {
    for (final folder in BundledStickerFolder.values) {
      if (folder.id == _stickerFolderId) return folder;
    }
    return null;
  }

  /// Stickers importados que moram na pasta aberta: os sem pasta ficam em
  /// "Importados", o resto em cada pasta criada pelo usuário.
  List<ImportedAsset> get _stickersInOpenFolder {
    final bundled = _openBundledFolder;
    if (bundled != null && !bundled.acceptsImports) return const [];
    // "Importados" é a pasta sem id (também onde caem as entradas antigas);
    // as demais guardam o próprio id em cada sticker.
    final folderId = bundled == BundledStickerFolder.imported
        ? null
        : _stickerFolderId;
    return _importedStickers.where((a) => a.folderId == folderId).toList();
  }

  Widget _stickersPanelContent() {
    final bundledFolder = _openBundledFolder;
    // A pasta pode ter arte embutida, stickers importados, ou os dois.
    final bundledStickers = bundledFolder == null
        ? const <(String path, String label)>[]
        : bundledStickersFor(bundledFolder);
    final showsImports = bundledFolder == null || bundledFolder.acceptsImports;
    final imported = _stickersInOpenFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fileira de pastas e miniaturas de sticker bem menores que o
        // padrão do resto do app — este é o único lugar com tanta coisa
        // pequena lado a lado, então o tamanho das outras miniaturas
        // (seletor de fundo, trocar foto) fica como está.
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Fileira curta (embutidas + poucas dezenas de pastas no
            // máximo): manter mais itens construídos fora da tela custa
            // pouco e garante que uma pasta recém-criada já exista na árvore
            // (e portanto seja alcançável por `Scrollable.ensureVisible`,
            // ver o `Builder` abaixo) mesmo numa tela estreita de celular,
            // onde a área visível + cache padrão pode não chegar até ela.
            scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
            // +1 pelo botão de criar pasta, sempre no fim da linha.
            itemCount:
                _visibleBundledFolders.length + _customFolders.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              if (index < _visibleBundledFolders.length) {
                final folder = _visibleBundledFolders[index];
                return FolderTab(
                  label: folder.label,
                  selected: folder.id == _stickerFolderId,
                  onTap: () => setState(() => _stickerFolderId = folder.id),
                );
              }
              final customIndex = index - _visibleBundledFolders.length;
              if (customIndex < _customFolders.length) {
                final folder = _customFolders[customIndex];
                // A pasta recém-criada rola até ficar visível sozinha (ver
                // [_createStickerFolder]) — igual ao ícone de ajuste
                // selecionado em [ColorAdjustPanel], um `Builder` dá a este
                // item específico o próprio `BuildContext`, que
                // `Scrollable.ensureVisible` usa para centralizar exatamente
                // ele na fileira. Calcular a posição na mão (por
                // `maxScrollExtent`) dependia do layout já estar pronto no
                // frame seguinte; isto usa a posição real do item, então
                // funciona mesmo se o painel ainda estiver se ajustando
                // (ex.: o teclado fechando ao mesmo tempo).
                return Builder(
                  builder: (itemContext) {
                    if (_pendingFolderScrollId == folder.id) {
                      _pendingFolderScrollId = null;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!itemContext.mounted) return;
                        Scrollable.ensureVisible(
                          itemContext,
                          alignment: 0.5,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      });
                    }
                    return FolderTab(
                      label: folder.name,
                      selected: folder.id == _stickerFolderId,
                      onTap: () => setState(() => _stickerFolderId = folder.id),
                      onLongPress: () => _openFolderMenu(folder),
                    );
                  },
                );
              }
              return FolderTab(
                label: 'Nova pasta',
                selected: false,
                icon: Icons.create_new_folder_outlined,
                onTap: _createStickerFolder,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 58,
          // Uma fileira só: primeiro a arte embutida da pasta, depois o que
          // foi importado para ela e, no fim, o tile de importar (nas pastas
          // que aceitam importação). Antes eram dois caminhos separados, e
          // uma pasta com as duas coisas — como "GitHub" — só mostrava uma.
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount:
                bundledStickers.length +
                imported.length +
                (showsImports ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index < bundledStickers.length) {
                final sticker = bundledStickers[index];
                // `Center`: dentro de um `ListView` horizontal, o filho
                // direto é estirado para a altura inteira da fileira,
                // ignorando a altura que o `Container` pede — sem isto a
                // miniatura saía do tamanho da fileira (58), não dos 36
                // pedidos.
                return Center(
                  child: GestureDetector(
                    onTap: () => _addBundledSticker(sticker),
                    child: _bundledStickerThumb(sticker, size: 44, height: 36),
                  ),
                );
              }
              final importedIndex = index - bundledStickers.length;
              if (importedIndex < imported.length) {
                final asset = imported[importedIndex];
                return Center(
                  child: GestureDetector(
                    onTap: () => _addStickerFromAsset(asset),
                    onLongPress: () => _confirmRemoveSticker(asset),
                    child: ImportedAssetThumb(
                      asset: asset,
                      selected: false,
                      size: 44,
                      height: 36,
                    ),
                  ),
                );
              }
              return ImportAssetTile(
                // Importar de dentro de uma pasta já põe o sticker nela; em
                // "Importados" a pasta é nula.
                onTap: () => _importSticker(
                  folderId: bundledFolder == BundledStickerFolder.imported
                      ? null
                      : _stickerFolderId,
                ),
                label: 'Importar',
                size: 44,
                height: 36,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _createStickerFolder() async {
    final name = await _promptTextInput(
      initial: '',
      title: 'Nova pasta',
      maxLines: 1,
    );
    if (name == null) return; // Cancelado — nada a avisar.
    if (name.trim().isEmpty) {
      // Sem isto, um nome que não chegou a registrar (ex.: o teclado ainda
      // compondo o texto no instante do toque) fazia "Nova pasta" parecer
      // não fazer nada.
      _message('Digite um nome para a pasta.');
      return;
    }
    try {
      final folder = await _folderStore.create(name);
      if (!mounted) return;
      setState(() {
        _customFolders = [..._customFolders, folder];
        _stickerFolderId = folder.id;
        // A pasta nova nasce perto do fim da fileira (antes só de "Nova
        // pasta"), fora da parte já visível se houver muitas pastas — o
        // item dela mesma, ao entrar na árvore, pede pra rolar até si (ver
        // o `Builder` em `_stickersPanelContent`).
        _pendingFolderScrollId = folder.id;
      });
    } catch (e) {
      // Uma pasta que falha ao salvar não pode desaparecer em silêncio —
      // sem isto, tocar "Nova pasta" simplesmente não fazia nada visível.
      if (!mounted) return;
      _message('Não deu para criar a pasta: $e');
    }
  }

  /// Menu de segurar uma pasta criada — as embutidas não passam
  /// `onLongPress`, então não chegam aqui.
  void _openFolderMenu(StickerFolder folder) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Renomear'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _renameStickerFolder(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Apagar'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmRemoveStickerFolder(folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameStickerFolder(StickerFolder folder) async {
    final name = await _promptTextInput(
      initial: folder.name,
      title: 'Renomear pasta',
      maxLines: 1,
    );
    if (name == null || name.trim().isEmpty) return;
    await _folderStore.rename(folder.id, name);
    if (!mounted) return;
    setState(() {
      _customFolders = [
        for (final f in _customFolders)
          f.id == folder.id ? StickerFolder(id: f.id, name: name.trim()) : f,
      ];
    });
  }

  /// Apagar a pasta não apaga o que o usuário importou para ela: os stickers
  /// voltam para "Importados" (`moveFolderToRoot`), e o diálogo diz isso
  /// antes de confirmar.
  Future<void> _confirmRemoveStickerFolder(StickerFolder folder) async {
    final inFolder = _importedStickers
        .where((a) => a.folderId == folder.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar pasta?'),
        content: Text(
          inFolder == 0
              ? '"${folder.name}" vai ser apagada.'
              : '"${folder.name}" vai ser apagada. '
                    '${inFolder == 1 ? 'O sticker que está' : 'Os $inFolder stickers que estão'} '
                    'nela ${inFolder == 1 ? 'volta' : 'voltam'} para "Importados".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _stickerStore.moveFolderToRoot(folder.id);
    await _folderStore.remove(folder.id);
    if (!mounted) return;
    setState(() {
      _customFolders = _customFolders.where((f) => f.id != folder.id).toList();
      _importedStickers = [
        for (final asset in _importedStickers)
          asset.folderId == folder.id
              ? ImportedAsset(
                  id: asset.id,
                  label: asset.label,
                  filePath: asset.filePath,
                  isVector: asset.isVector,
                  nativeAspectRatio: asset.nativeAspectRatio,
                )
              : asset,
      ];
      _dropStickerFolderIfGone();
    });
  }

  Widget _bundledStickerThumb(
    (String path, String label) sticker, {
    double size = 62,
    double height = 46,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
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

  Future<void> _importSticker({String? folderId}) async {
    try {
      final asset = await _stickerStore.import(folderId: folderId);
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
    final selected = _selectedOverlayId == null
        ? null
        : _findText(_selectedOverlayId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textComposer(),
        // Os controles de estilo só fazem sentido com um texto selecionado —
        // eles mexem naquele texto, não em todos.
        if (selected != null) ...[
          const SizedBox(height: 8),
          PanelColorRow(
            label: 'Cor do texto',
            color: selected.color,
            onTap: () => _pickTextColor(selected.id),
          ),
          PanelSwitchRow(
            label: 'Fundo do texto',
            value: selected.hasBackground,
            onChanged: (on) => _toggleTextBackground(selected.id, on),
          ),
          if (selected.hasBackground) ...[
            const SizedBox(height: 4),
            _textBackgroundGroup(selected),
          ],
        ],
      ],
    );
  }

  /// Cor/opacidade/arredondamento do fundo do texto, agrupados numa caixa com
  /// destaque à esquerda — deixa claro que os três são sub-opções de "Fundo
  /// do texto" logo acima, então os rótulos aqui dentro não repetem "do
  /// fundo" (a folha de cor, mais longe desse contexto, continua dizendo
  /// "Cor do fundo do texto").
  Widget _textBackgroundGroup(CollageTextItem selected) {
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
          PanelColorRow(
            label: 'Cor',
            color: selected.backgroundColor!,
            onTap: () => _pickTextBackgroundColor(selected.id),
          ),
          const SizedBox(height: 4),
          PanelSliderRow(
            onChangeStart: _pushUndoCheckpoint,
            label: 'Opacidade',
            value: selected.backgroundColor!.a,
            min: 0,
            max: 1,
            valueLabel: '${(selected.backgroundColor!.a * 100).round()}%',
            onChanged: (v) => _update(
              _settings.replacingText(
                selected.id,
                selected.copyWith(
                  backgroundColor: selected.backgroundColor!.withValues(
                    alpha: v,
                  ),
                ),
              ),
              pushUndo: false,
            ),
          ),
          const SizedBox(height: 4),
          PanelSliderRow(
            onChangeStart: _pushUndoCheckpoint,
            label: 'Arredondamento',
            value: selected.backgroundCornerRatio,
            min: 0,
            max: CollageTextItem.maxBackgroundCornerRatio,
            valueLabel:
                '${(selected.backgroundCornerRatio / CollageTextItem.maxBackgroundCornerRatio * 100).round()}%',
            onChanged: (v) => _update(
              _settings.replacingText(
                selected.id,
                selected.copyWith(backgroundCornerRatio: v),
              ),
              pushUndo: false,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleTextBackground(String id, bool on) {
    final item = _findText(id);
    if (item == null) return;
    _update(
      _settings.replacingText(
        id,
        on
            ? item.copyWith(
                backgroundColor: item.backgroundColor ?? defaultBackgroundColor,
              )
            : item.copyWith(clearBackgroundColor: true),
      ),
    );
  }

  void _pickTextColor(String id) => _pickOverlayTextColor(
    id: id,
    title: 'Cor do texto',
    current: (item) => item.color,
    apply: (item, color) => item.copyWith(color: color),
  );

  void _pickTextBackgroundColor(String id) => _pickOverlayTextColor(
    id: id,
    title: 'Cor do fundo do texto',
    current: (item) => item.backgroundColor ?? defaultBackgroundColor,
    apply: (item, color) => item.copyWith(backgroundColor: color),
  );

  /// Mesma folha de cor do resto da montagem (com conta-gotas na prévia),
  /// servindo tanto à cor do texto quanto à do fundo dele — [current]/[apply]
  /// são o que muda entre as duas, no mesmo espírito de [_pickBorderColor].
  void _pickOverlayTextColor({
    required String id,
    required String title,
    required Color Function(CollageTextItem item) current,
    required CollageTextItem Function(CollageTextItem item, Color color) apply,
  }) {
    final item = _findText(id);
    if (item == null) return;
    var checkpointPushed = false;
    showCollageColorPickerSheet(
      context: context,
      title: title,
      initialColor: current(item),
      onColorSelected: (color) {
        final latest = _findText(id);
        if (latest == null) return;
        if (!checkpointPushed) {
          checkpointPushed = true;
          _pushUndoCheckpoint();
        }
        _update(
          _settings.replacingText(id, apply(latest, color)),
          pushUndo: false,
        );
      },
      previewImageBuilder: _renderPreviewImage,
    );
  }

  /// Campo de escrever texto do painel: o botão da ponta cria a caixa (ou
  /// confirma a edição, quando o lápis carregou uma aqui). Escrever direto no
  /// painel evita a janela que existia só para digitar uma frase.
  Widget _textComposer() {
    final theme = Theme.of(context);
    final editing = _editingTextId != null;
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
                onPressed: _cancelTextEdit,
                child: const Text('Cancelar'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _textController,
          builder: (context, value, _) {
            final canSubmit = value.text.trim().isNotEmpty;
            return TextField(
              controller: _textController,
              focusNode: _textFocus,
              minLines: 1,
              // Até 3 linhas, o mesmo que o diálogo antigo aceitava — com
              // `TextInputType.multiline` o Enter quebra linha e quem
              // confirma é o botão da ponta.
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submitPanelText(),
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
                    onPressed: canSubmit ? _submitPanelText : null,
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

  /// Cria a caixa nova (ou salva a que o lápis trouxe para o campo). O foco
  /// volta para o campo em vez de sair: dá para escrever várias caixas em
  /// sequência sem reabrir o teclado a cada uma.
  void _submitPanelText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final editingId = _editingTextId;
    if (editingId != null) {
      final item = _findText(editingId);
      if (item != null) {
        _update(_settings.replacingText(editingId, item.copyWith(text: text)));
      }
      setState(() => _editingTextId = null);
    } else {
      final item = CollageTextItem(
        id: 't_${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        centerX: 0.5,
        centerY: 0.5,
        zIndex: _settings.nextZIndex,
      );
      _update(_settings.addingText(item));
      setState(() => _selectedOverlayId = item.id);
    }
    _textController.clear();
    _textFocus.requestFocus();
  }

  void _cancelTextEdit() {
    setState(() => _editingTextId = null);
    _textController.clear();
  }

  /// O lápis da barra de ações traz o texto da caixa selecionada para o campo
  /// do painel — que já está na tela, já que a barra só aparece com a aba
  /// "Texto" aberta.
  void _editSelectedText(String id) {
    final item = _findText(id);
    if (item == null) return;
    setState(() {
      _editingTextId = id;
      _textController.text = item.text;
      _textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: item.text.length,
      );
    });
    _textFocus.requestFocus();
  }

  Future<String?> _promptTextInput({
    required String initial,
    String title = 'Texto',
    int maxLines = 3,
  }) => showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        TextInputDialog(initial: initial, title: title, maxLines: maxLines),
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
                    CollageFontThumb(
                      family: font.$1,
                      label: font.$2,
                      selected: item.fontFamily == font.$1,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _applyTextFont(id, font.$1);
                      },
                    ),
                  // As importadas ficam na mesma grade das embutidas —
                  // segurar remove.
                  for (final font in _importedFonts)
                    CollageFontThumb(
                      family: font.family,
                      label: font.label,
                      selected: item.fontFamily == font.family,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _applyTextFont(id, font.family);
                      },
                      onLongPress: () {
                        Navigator.of(sheetContext).pop();
                        _confirmRemoveFont(font);
                      },
                    ),
                  CollageFontThumb(
                    family: null,
                    label: 'Importar',
                    selected: false,
                    icon: Icons.font_download_outlined,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _importFont(id);
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

  void _applyTextFont(String id, String? family) {
    final item = _findText(id);
    if (item == null) return;
    _pushUndoCheckpoint();
    _update(
      _settings.replacingText(
        id,
        item.copyWith(fontFamily: family, clearFontFamily: family == null),
      ),
      pushUndo: false,
    );
  }

  /// Importar uma fonte já a aplica no texto que abriu a folha — mesmo
  /// caminho de "importar e usar" dos stickers.
  Future<void> _importFont(String textId) async {
    try {
      final font = await _fontStore.import();
      if (!mounted) return;
      setState(() => _importedFonts = [..._importedFonts, font]);
      _applyTextFont(textId, font.family);
    } on ImportedFontException catch (e) {
      _message(e.message);
    }
  }

  /// Remover a fonte devolve os textos que a usavam para a fonte padrão — a
  /// família deixa de existir na próxima abertura do app, e um texto
  /// apontando para ela ficaria com uma fonte que não é a escolhida nem a
  /// mostrada agora.
  Future<void> _confirmRemoveFont(ImportedFont font) async {
    final inUse = _settings.texts
        .where((t) => t.fontFamily == font.family)
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover fonte?'),
        content: Text(
          inUse.isEmpty
              ? '"${font.label}" vai sair da lista de fontes.'
              : '"${font.label}" vai sair da lista de fontes, e '
                    '${inUse.length == 1 ? 'o texto que a usa volta' : 'os ${inUse.length} textos que a usam voltam'} '
                    'para a fonte padrão.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _fontStore.remove(font.id);
    if (!mounted) return;
    setState(() {
      _importedFonts = _importedFonts.where((f) => f.id != font.id).toList();
    });
    var updated = _settings;
    for (final text in inUse) {
      updated = updated.replacingText(
        text.id,
        text.copyWith(clearFontFamily: true),
      );
    }
    if (!identical(updated, _settings)) _update(updated);
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

  // ---------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------

  /// Formato, regra de duração e tamanho escolhidos na última exportação —
  /// a folha de opções reabre já marcada no que a pessoa usou da última vez.
  CollageExportFormat _exportFormat = CollageExportFormat.gif;
  CollageDurationRule _durationRule = CollageDurationRule.longest;
  CollageExportSize _exportSize = CollageExportSize.standard;

  /// Pergunta o formato (quando há foto animada na montagem) e o tamanho da
  /// exportação. Devolve `null` quando a pessoa fecha a folha sem escolher.
  ///
  /// [_exportFormat]/[_durationRule]/[_exportSize] só guardam a última
  /// escolha para a folha já abrir marcada nela; a seleção feita durante
  /// esta chamada vive em variáveis locais (`selectedFormat`/`selectedRule`/
  /// `selectedSize`) para não vazar para outra folha que porventura esteja
  /// aberta ao mesmo tempo.
  Future<CollageExportFormat?> _askExportFormat() async {
    final info = await _export.inspectAnimationCached(_settings);
    if (!mounted) return null;

    var selectedFormat = info.hasAnimation
        ? _exportFormat
        : CollageExportFormat.png;
    var selectedRule = _durationRule;
    var selectedSize = _exportSize;

    final result = await showModalBottomSheet<CollageExportFormat>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, sheetSetState) {
          final theme = Theme.of(sheetContext);
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Exportar', style: theme.textTheme.titleMedium),
                    if (info.hasAnimation) ...[
                      const SizedBox(height: 4),
                      Text(
                        info.animatedCount == 1
                            ? 'Uma das fotos é animada — a montagem pode '
                                  'sair animada também.'
                            : '${info.animatedCount} fotos são animadas — '
                                  'a montagem pode sair animada também.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      RadioGroup<CollageExportFormat>(
                        groupValue: selectedFormat,
                        onChanged: (value) {
                          if (value == null) return;
                          sheetSetState(() => selectedFormat = value);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final format in CollageExportFormat.values)
                              RadioListTile<CollageExportFormat>(
                                contentPadding: EdgeInsets.zero,
                                value: format,
                                title: Text(format.label),
                                subtitle: Text(format.subtitle),
                              ),
                          ],
                        ),
                      ),
                      if (selectedFormat.isAnimated &&
                          info.hasDifferentDurations) ...[
                        const Divider(height: 24),
                        Text(
                          'Duração',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        RadioGroup<CollageDurationRule>(
                          groupValue: selectedRule,
                          onChanged: (value) {
                            if (value == null) return;
                            sheetSetState(() => selectedRule = value);
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final rule in CollageDurationRule.values)
                                RadioListTile<CollageDurationRule>(
                                  contentPadding: EdgeInsets.zero,
                                  value: rule,
                                  title: Text(
                                    '${rule.label} '
                                    '(${_formatSeconds(info.durationFor(rule))})',
                                  ),
                                  subtitle: Text(rule.subtitle),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const Divider(height: 24),
                    ] else
                      const SizedBox(height: 12),
                    Text(
                      'Tamanho',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final size in CollageExportSize.values)
                          ChoiceChip(
                            label: Text(size.label),
                            selected: selectedSize == size,
                            onSelected: (_) =>
                                sheetSetState(() => selectedSize = size),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(selectedFormat),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: const Text('Continuar'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _exportFormat = selectedFormat;
        _durationRule = selectedRule;
        _exportSize = selectedSize;
      });
    }
    return result;
  }

  String _formatSeconds(Duration duration) =>
      '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';

  /// Abre o pop-up de progresso e roda a exportação. Devolve o arquivo, ou
  /// `null` quando o usuário cancelou — o pop-up sai da tela em qualquer um
  /// dos casos, inclusive em erro, para nunca sobrar um "exportando" preso.
  Future<File?> _exportWithProgress(CollageExportFormat format) async {
    // O PNG sai de uma composição só, rápida demais para valer um pop-up que
    // só piscaria na tela.
    if (!format.isAnimated) return _buildExportFile(format);

    _export.begin();
    final (width, height) = CollageExportRunner.pixelSize(
      _settings,
      _exportSize,
      format,
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExportProgressDialog(
          progress: _export.progress,
          formatLabel: format.label,
          width: width,
          height: height,
          onCancel: _export.cancel,
        ),
      ),
    );
    try {
      return await _buildExportFile(format);
    } on CollageRenderCancelled {
      return null;
    } on FfmpegException {
      // Cancelar durante a codificação chega aqui como falha do FFmpeg —
      // não é erro para mostrar ao usuário.
      if (_export.cancelled) return null;
      rethrow;
    } finally {
      navigator.pop();
    }
  }

  void _reportExportProgress(double value) {
    // O notifier morre junto com a tela; sem esta guarda, um quadro que
    // termina depois de sair da montagem escreveria num objeto descartado.
    if (!mounted) return;
    _export.progress.value = ExportProgress(
      value: value.clamp(0.0, 1.0),
      cancelling: _export.progress.value.cancelling,
    );
  }

  Future<File> _buildExportFile(CollageExportFormat format) => _export.build(
    settings: _settings,
    format: format,
    size: _exportSize,
    rule: _durationRule,
    reportProgress: _reportExportProgress,
  );

  Future<void> _save() async {
    final format = await _askExportFormat();
    if (format == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final file = await _exportWithProgress(format);
      if (file == null) {
        if (mounted) _message('Exportação cancelada.');
        return;
      }
      await _output.saveToGallery(file);
      if (!mounted) return;
      _message('Montagem salva na galeria.');
    } on OutputException catch (e) {
      if (!mounted) return;
      _message(e.message);
    } on FfmpegException catch (e) {
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
    final format = await _askExportFormat();
    if (format == null || !mounted) return;
    setState(() => _sharing = true);
    try {
      final file = await _exportWithProgress(format);
      if (file == null) {
        if (mounted) _message('Exportação cancelada.');
        return;
      }
      await _output.share(
        file,
        mimeType: format.mimeType,
        text: 'Montagem de fotos feita com o app Video to GIF',
      );
    } on FfmpegException catch (e) {
      if (!mounted) return;
      _message(e.message);
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
