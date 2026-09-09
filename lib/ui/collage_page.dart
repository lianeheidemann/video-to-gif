import 'dart:async';
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
import '../models/collage_export.dart';
import '../models/collage_layout.dart';
import '../models/collage_settings.dart';
import '../models/collage_sticker.dart';
import '../models/collage_text.dart';
import '../models/crop_rect.dart';
import '../models/default_colors.dart';
import '../models/photo_info.dart';
import '../services/collage_animation.dart';
import '../services/collage_compositor.dart';
import '../services/ffmpeg_service.dart';
import '../services/imported_asset_store.dart';
import '../services/imported_font_store.dart';
import '../services/output_service.dart';
import '../services/sticker_folder_store.dart';
import 'photo_crop_page.dart';
import 'widgets/collage_cell_view.dart';
import 'widgets/collage_overlay_view.dart';
import 'widgets/collage_painter.dart';
import 'widgets/color_adjust_controls.dart';
import 'widgets/color_picker_sheet.dart';
import 'widgets/export_progress_dialog.dart';
import 'widgets/folder_tab.dart';
import 'widgets/target_sub_panel.dart';

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
}

/// Pastas da seção "Stickers": as temáticas com os stickers embutidos do
/// app, mais "Importados" para os que o usuário trouxe do aparelho.
///
/// "Black" ainda não tem sticker embutido — a arte vem depois —, então por
/// enquanto ela vale como pasta de importados: o botão "Importar" aparece
/// dentro e o que entrar ali fica marcado com o id dela. "GitHub" tem arte
/// embutida e também aceita importados.
enum _StickerFolder { reactions, symbols, effects, github, black, imported }

extension on _StickerFolder {
  /// `true` nas pastas que recebem stickers importados — "Importados" e as
  /// que ainda estão sem arte embutida.
  bool get acceptsImports =>
      this == _StickerFolder.imported ||
      this == _StickerFolder.github ||
      this == _StickerFolder.black;

  /// Id da pasta embutida na barra — o próprio nome do enum. As pastas
  /// criadas pelo usuário usam ids com prefixo `f_` (ver
  /// `StickerFolderStore.create`), então os dois conjuntos convivem na mesma
  /// barra sem risco de colisão.
  String get id => name;

  String get label => switch (this) {
    _StickerFolder.reactions => 'Reações',
    _StickerFolder.symbols => 'Símbolos',
    _StickerFolder.effects => 'Efeitos',
    _StickerFolder.github => 'GitHub',
    _StickerFolder.black => 'Black',
    _StickerFolder.imported => 'Importados',
  };
}

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
  final _ffmpeg = FfmpegService();
  static const _stickerStore = ImportedAssetStore(ImportedAssetKind.sticker);
  static const _backgroundStore = ImportedAssetStore(
    ImportedAssetKind.backgroundImage,
  );
  static const _folderStore = StickerFolderStore();
  static const _fontStore = ImportedFontStore();

  /// Stickers prontos, embutidos no app (`assets/sticker/`), agrupados por
  /// pasta temática na seção "Stickers" — ver [_StickerFolder].
  static const _stickerFolderReactions = <(String path, String label)>[
    ('assets/sticker/thumbs_up.svg', 'Joinha'),
    ('assets/sticker/smiley.svg', 'Sorriso'),
  ];
  static const _stickerFolderSymbols = <(String path, String label)>[
    ('assets/sticker/heart.svg', 'Coração'),
    ('assets/sticker/star.svg', 'Estrela'),
  ];
  static const _stickerFolderEffects = <(String path, String label)>[
    ('assets/sticker/sparkle.svg', 'Brilho'),
  ];

  /// Pasta "GitHub": arte enviada pela Liane, guardada em
  /// `assets/sticker/github/`. Os nomes de arquivo começam com um número
  /// que define a ordem em que aparecem na fileira.
  static const _stickerFolderGithub = <(String path, String label)>[
    ('assets/sticker/github/01-robot-android.svg', 'Robô Android'),
    (
      'assets/sticker/github/10-wordmark-github-bold.svg',
      'Marca GitHub negrito',
    ),
    (
      'assets/sticker/github/11-wordmark-github-compact.svg',
      'Marca GitHub compacto',
    ),
    ('assets/sticker/github/20-octocat-colorido.svg', 'Octocat colorido'),
    ('assets/sticker/github/21-octopus-com-bigodes.svg', 'Polvo com bigodes'),
    ('assets/sticker/github/22-octopus-silhueta.svg', 'Polvo silhueta'),
    (
      'assets/sticker/github/23-octopus-silhueta-pernas.svg',
      'Polvo silhueta pernas',
    ),
    (
      'assets/sticker/github/24-octopus-contorno-grosso.svg',
      'Polvo contorno grosso',
    ),
    (
      'assets/sticker/github/25-octopus-contorno-duotone.svg',
      'Polvo contorno duotone',
    ),
    (
      'assets/sticker/github/26-octopus-contorno-fino.svg',
      'Polvo contorno fino',
    ),
    ('assets/sticker/github/30-gato-contorno-fino.svg', 'Gato contorno fino'),
    ('assets/sticker/github/31-gato-contorno-medio.svg', 'Gato contorno médio'),
    (
      'assets/sticker/github/32-gato-contorno-grosso.svg',
      'Gato contorno grosso',
    ),
    (
      'assets/sticker/github/33-gato-silhueta-azul-marinho.svg',
      'Gato silhueta azul marinho',
    ),
    (
      'assets/sticker/github/40-gato-circulo-contorno.svg',
      'Gato círculo contorno',
    ),
    (
      'assets/sticker/github/41-gato-circulo-preto-grande.svg',
      'Gato círculo preto grande',
    ),
    (
      'assets/sticker/github/42-gato-circulo-preto-medio.svg',
      'Gato círculo preto médio',
    ),
    (
      'assets/sticker/github/43-gato-circulo-preto-classico.svg',
      'Gato círculo preto clássico',
    ),
    (
      'assets/sticker/github/44-gato-circulo-preto-pequeno.svg',
      'Gato círculo preto pequeno',
    ),
    (
      'assets/sticker/github/45-gato-circulo-preto-cauda.svg',
      'Gato círculo preto cauda',
    ),
    (
      'assets/sticker/github/46-gato-circulo-preto-logo.svg',
      'Gato círculo preto logo',
    ),
    (
      'assets/sticker/github/47-gato-circulo-preto-sticker.svg',
      'Gato círculo preto sticker',
    ),
    ('assets/sticker/github/48-gato-circulo-azul.svg', 'Gato círculo azul'),
    (
      'assets/sticker/github/49-gato-circulo-azul-cinza.svg',
      'Gato círculo azul cinza',
    ),
    (
      'assets/sticker/github/50-gato-circulo-azul-petroleo.svg',
      'Gato círculo azul petróleo',
    ),
    (
      'assets/sticker/github/51-gato-circulo-azul-degrade.svg',
      'Gato círculo azul degradê',
    ),
    (
      'assets/sticker/github/60-gato-oval-contorno-fino.svg',
      'Gato oval contorno fino',
    ),
    (
      'assets/sticker/github/61-gato-oval-contorno-preenchido.svg',
      'Gato oval contorno preenchido',
    ),
    (
      'assets/sticker/github/62-gato-oval-contorno-grosso.svg',
      'Gato oval contorno grosso',
    ),
    (
      'assets/sticker/github/63-octopus-oval-contorno.svg',
      'Polvo oval contorno',
    ),
    ('assets/sticker/github/64-gato-oval-ciano.svg', 'Gato oval ciano'),
    (
      'assets/sticker/github/65-gato-oval-preto-pequeno.svg',
      'Gato oval preto pequeno',
    ),
    (
      'assets/sticker/github/70-gato-quadrado-arredondado-01.svg',
      'Gato quadrado arredondado',
    ),
    (
      'assets/sticker/github/71-gato-quadrado-arredondado-02.svg',
      'Gato quadrado arredondado 2',
    ),
    (
      'assets/sticker/github/72-gato-quadrado-arredondado-03.svg',
      'Gato quadrado arredondado 3',
    ),
    ('assets/sticker/github/73-gato-quadrado-reto.svg', 'Gato quadrado reto'),
    ('assets/sticker/github/74-gato-quadrado-duplo.svg', 'Gato quadrado duplo'),
    ('assets/sticker/github/80-gato-badge-cinza.svg', 'Gato selo cinza'),
  ];

  /// Stickers embutidos da pasta [folder] — vazio para
  /// [_StickerFolder.imported], que mostra os importados pelo usuário em vez
  /// disso (ver [_stickersPanelContent]).
  static List<(String path, String label)> _bundledStickersFor(
    _StickerFolder folder,
  ) => switch (folder) {
    _StickerFolder.reactions => _stickerFolderReactions,
    _StickerFolder.symbols => _stickerFolderSymbols,
    _StickerFolder.effects => _stickerFolderEffects,
    _StickerFolder.github => _stickerFolderGithub,
    // Sem arte embutida ainda: se comporta como pasta de importados até os
    // arquivos chegarem.
    _StickerFolder.black => const [],
    _StickerFolder.imported => const [],
  };

  late CollageSettings _settings = CollageSettings.forLayout(
    _defaultLayoutFor(widget.photos.length),
    widget.photos,
  );

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

  /// Pasta aberta na aba "Stickers": id de uma embutida ([_StickerFolder.id])
  /// ou de uma criada pelo usuário ([StickerFolder.id]).
  String _stickerFolderId = _StickerFolder.reactions.id;

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
  final _exportProgress = ValueNotifier(const ExportProgress());

  /// `true` entre pedir o cancelamento e a exportação de fato parar.
  bool _exportCancelled = false;

  /// Id da caixa sendo editada pelo campo; `null` = o campo está criando uma
  /// caixa nova.
  String? _editingTextId;

  @override
  void dispose() {
    _textController.dispose();
    _textFocus.dispose();
    _exportProgress.dispose();
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
        _StickerFolder.values.any((f) => f.id == _stickerFolderId) ||
        _customFolders.any((f) => f.id == _stickerFolderId);
    if (!exists) _stickerFolderId = _StickerFolder.imported.id;
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
        padding: const EdgeInsets.symmetric(vertical: 8),
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
    _CollageTab.layout => _layoutPanelContent(),
    _CollageTab.aspect => _aspectPanelContent(),
    _CollageTab.margin => _marginPanelContent(),
    _CollageTab.border => _borderPanelContent(),
    _CollageTab.background => _backgroundPanelContent(),
    _CollageTab.color => _colorPanelContent(),
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
      onTap: () => setState(() {
        _activeTab = selected ? null : tab;
        // Abrir (ou trocar de) aba sempre mostra o conteúdo: recolhido é um
        // estado do painel aberto, não algo que a aba herda.
        _panelCollapsed = false;
      }),
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
    _CollageTab.color => Icons.tune_rounded,
    _CollageTab.stickers => Icons.emoji_emotions_outlined,
    _CollageTab.text => Icons.text_fields_rounded,
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

    // O mesmo respiro e o mesmo arredondamento que `_TextOverlay.paint`
    // desenha na exportação — o raio sai do menor lado da caixa já com o
    // respiro, então a prévia e o PNG batem em qualquer tamanho de fonte.
    final (padH, padV) = CollageTextItem.backgroundPaddingFor(fontSize);
    return _TextBackgroundBox(
      color: background,
      cornerRatio: item.backgroundCornerRatio,
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      child: text,
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

  Widget _marginPanelContent() {
    final outer = _settings.outerMarginRatio;
    final inner = _settings.innerMarginRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Margem'),
        // As três de uma vez, uma embaixo da outra: antes eram chips que
        // trocavam qual delas o único slider controlava, então ver a margem
        // externa e a de entre fotos ao mesmo tempo era impossível.
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _marginRow(
                    icon: Icons.border_all_rounded,
                    label: 'Tudo',
                    // "Tudo" não tem valor próprio: mostra a média das duas e,
                    // ao arrastar, iguala as duas ao valor escolhido.
                    value: (outer + inner) / 2,
                    onChanged: (v) => _update(
                      _settings.copyWith(
                        outerMarginRatio: v,
                        innerMarginRatio: v,
                      ),
                      pushUndo: false,
                    ),
                  ),
                  _marginRow(
                    icon: Icons.border_outer_rounded,
                    label: 'Externa',
                    value: outer,
                    onChanged: (v) => _update(
                      _settings.copyWith(outerMarginRatio: v),
                      pushUndo: false,
                    ),
                  ),
                  _marginRow(
                    icon: Icons.border_inner_rounded,
                    label: 'Entre fotos',
                    value: inner,
                    onChanged: (v) => _update(
                      _settings.copyWith(innerMarginRatio: v),
                      pushUndo: false,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Zerar margens',
              onPressed: outer == 0 && inner == 0
                  ? null
                  : () => _update(
                      _settings.copyWith(
                        outerMarginRatio: 0,
                        innerMarginRatio: 0,
                      ),
                    ),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ],
    );
  }

  /// Uma linha da aba "Margem": ícone, slider e o valor em porcentagem. O
  /// nome fica no tooltip do ícone — escrito por extenso, as três linhas não
  /// caberiam sem espremer o slider.
  Widget _marginRow({
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    final clamped = value.clamp(
      CollageSettings.minMarginRatio,
      CollageSettings.maxMarginRatio,
    );
    final percent = (clamped / CollageSettings.maxMarginRatio * 100).round();
    return Row(
      children: [
        Tooltip(
          message: label,
          child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: Slider(
            min: CollageSettings.minMarginRatio,
            max: CollageSettings.maxMarginRatio,
            value: clamped,
            label: '$percent%',
            onChangeStart: (_) => _pushUndoCheckpoint(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$percent%',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  /// "x:y" é o chip da proporção livre: ou o usuário o escolheu, ou a
  /// proporção atual não corresponde a nenhum chip pronto.
  bool get _aspectIsCustom =>
      _customAspectSelected || _customAspectLabel() != null;

  Widget _aspectPanelContent() {
    final custom = _aspectIsCustom;
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
                // Com "x:y" escolhido, nenhum chip pronto fica marcado —
                // senão dois apareceriam marcados ao mesmo tempo quando os
                // campos formassem justo a proporção de um deles.
                selected:
                    !custom &&
                    (_settings.aspectRatio - preset.$2).abs() < 0.001,
                onSelected: (_) {
                  setState(() => _customAspectSelected = false);
                  _update(_settings.copyWith(aspectRatio: preset.$2));
                },
              ),
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              labelStyle: Theme.of(context).textTheme.bodySmall,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              label: const Text('x:y'),
              selected: custom,
              onSelected: (_) => setState(() => _customAspectSelected = true),
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
        // Largura e altura só entram na tela com "x:y" escolhido — antes
        // ficavam sempre lá, ocupando espaço mesmo para quem só queria um
        // dos formatos prontos.
        if (custom) ...[
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
        // Espessura, arredondamento e cor valem para o alvo escolhido em
        // cima (a montagem inteira ou todas as fotos), então ficam dentro da
        // caixa dele — ver [TargetSubPanel].
        TargetSubPanel(
          options: const ['Montagem', 'Fotos'],
          selectedIndex: targetsPhotos ? 1 : 0,
          onSelected: (index) =>
              setState(() => _borderTargetsPhotos = index == 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
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
          ),
        ),
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

  /// Linha de liga/desliga no estilo dos painéis do rodapé. Um
  /// `SwitchListTile` aqui dispara o aviso do Material de "fundo/ink
  /// invisível" (o painel já tem cor de fundo própria) — e o visual ficaria
  /// diferente das outras linhas.
  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
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

  Widget _backgroundPanelContent() {
    final background = _targetBackground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Fundo'),
        // O fundo da montagem (a área fora/entre as fotos) e o fundo de
        // dentro de cada foto (o que aparece na sobra do modo "encaixar") são
        // escolhas independentes — mesmo seletor de alvo da aba "Borda e
        // cantos". Transparente/Cor/Imagem valem para o alvo escolhido, por
        // isso ficam dentro da caixa dele (ver [TargetSubPanel]).
        TargetSubPanel(
          options: const ['Montagem', 'Fotos'],
          selectedIndex: _backgroundTargetsPhotos ? 1 : 0,
          onSelected: (index) =>
              setState(() => _backgroundTargetsPhotos = index == 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `ChoiceChip`s em vez de `SegmentedButton`: os 3 rótulos
              // ("Transparente" principalmente) não cabem lado a lado com
              // ícone dentro da largura do painel do rodapé sem quebrar linha
              // dentro do próprio botão — chip quebra para a linha de baixo
              // inteiro, nunca no meio de uma palavra.
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
                    (
                      CollageBackgroundMode.color,
                      'Cor',
                      Icons.palette_outlined,
                    ),
                    (
                      CollageBackgroundMode.image,
                      'Imagem',
                      Icons.image_outlined,
                    ),
                  ])
                    ChoiceChip(
                      avatar: Icon(entry.$3, size: 18),
                      label: Text(entry.$2),
                      selected: background.mode == entry.$1,
                      onSelected: (_) =>
                          _applyBackground(background.copyWith(mode: entry.$1)),
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
          ),
        ),
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
          final selected = _targetBackground.imagePath == asset.filePath;
          return GestureDetector(
            onTap: () => _applyBackground(
              _targetBackground.copyWith(
                mode: CollageBackgroundMode.image,
                imagePath: asset.filePath,
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
      initialColor: _targetBackground.color,
      onColorSelected: (color) {
        if (!checkpointPushed) {
          checkpointPushed = true;
          _pushUndoCheckpoint();
        }
        _applyBackground(
          _targetBackground.copyWith(
            mode: CollageBackgroundMode.color,
            color: color,
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

  /// Ajuste de cor de todas as fotos de uma vez. Mexe só no que é foto —
  /// `CollageCellSettings` guarda os valores e o filtro de cor sai deles no
  /// desenho da imagem da célula (ver `collage_painter.dart`), então fundo,
  /// borda, stickers e texto ficam de fora por construção.
  ///
  /// Os valores mostrados vêm da célula de referência
  /// ([CollageSettings.cellStyleTemplate]), a mesma lógica das abas "Borda e
  /// cantos" e "Fundo" quando o alvo é "Fotos": os controles aplicam em lote,
  /// então uma célula representa todas.
  Widget _colorPanelContent() {
    final reference = _settings.cellStyleTemplate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Ajustar cor'),
        ColorAdjustPanel(
          hasAdjustments: _settings.cells.any((c) => c.hasColorAdjustments),
          valueOf: (adjustment) => adjustment.valueOf(reference),
          onChangeStart: _pushUndoCheckpoint,
          onChanged: (adjustment, value) => _update(
            _settings.updatingAllCells((c) => adjustment.apply(c, value)),
            pushUndo: false,
          ),
          onReset: () {
            _pushUndoCheckpoint();
            _update(
              _settings.updatingAllCells((c) => c.withoutColorAdjustments()),
              pushUndo: false,
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Stickers" / "Texto"
  // ---------------------------------------------------------------------

  /// Pasta embutida aberta agora, ou `null` quando a aberta é uma criada
  /// pelo usuário.
  _StickerFolder? get _openBundledFolder {
    for (final folder in _StickerFolder.values) {
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
    final folderId = bundled == _StickerFolder.imported
        ? null
        : _stickerFolderId;
    return _importedStickers.where((a) => a.folderId == folderId).toList();
  }

  Widget _stickersPanelContent() {
    final bundledFolder = _openBundledFolder;
    // A pasta pode ter arte embutida, stickers importados, ou os dois.
    final bundledStickers = bundledFolder == null
        ? const <(String path, String label)>[]
        : _bundledStickersFor(bundledFolder);
    final showsImports = bundledFolder == null || bundledFolder.acceptsImports;
    final imported = _stickersInOpenFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('Stickers'),
        // Fileira de pastas e miniaturas de sticker bem menores que o
        // padrão do resto do app — este é o único lugar com tanta coisa
        // pequena lado a lado, então o tamanho das outras miniaturas
        // (seletor de fundo, trocar foto) fica como está.
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // +1 pelo botão de criar pasta, sempre no fim da linha.
            itemCount: _StickerFolder.values.length + _customFolders.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              if (index < _StickerFolder.values.length) {
                final folder = _StickerFolder.values[index];
                return FolderTab(
                  label: folder.label,
                  selected: folder.id == _stickerFolderId,
                  onTap: () => setState(() => _stickerFolderId = folder.id),
                );
              }
              final customIndex = index - _StickerFolder.values.length;
              if (customIndex < _customFolders.length) {
                final folder = _customFolders[customIndex];
                return FolderTab(
                  label: folder.name,
                  selected: folder.id == _stickerFolderId,
                  onTap: () => setState(() => _stickerFolderId = folder.id),
                  onLongPress: () => _openFolderMenu(folder),
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
                    child: _assetThumb(
                      asset,
                      selected: false,
                      size: 44,
                      height: 36,
                    ),
                  ),
                );
              }
              return _importTile(
                // Importar de dentro de uma pasta já põe o sticker nela; em
                // "Importados" a pasta é nula.
                onTap: () => _importSticker(
                  folderId: bundledFolder == _StickerFolder.imported
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
    if (name == null || name.trim().isEmpty) return;
    final folder = await _folderStore.create(name);
    if (!mounted) return;
    setState(() {
      _customFolders = [..._customFolders, folder];
      _stickerFolderId = folder.id;
    });
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
        _panelHeader('Texto'),
        _textComposer(),
        // Os controles de estilo só fazem sentido com um texto selecionado —
        // eles mexem naquele texto, não em todos.
        if (selected != null) ...[
          const SizedBox(height: 8),
          _colorRow(
            'Cor do texto',
            selected.color,
            () => _pickTextColor(selected.id),
          ),
          _switchRow(
            'Fundo do texto',
            selected.hasBackground,
            (on) => _toggleTextBackground(selected.id, on),
          ),
          if (selected.hasBackground) ...[
            _colorRow(
              'Cor do fundo do texto',
              selected.backgroundColor!,
              () => _pickTextBackgroundColor(selected.id),
            ),
            const SizedBox(height: 4),
            _sliderRow(
              label: 'Opacidade do fundo',
              value: selected.backgroundColor!.a,
              min: 0,
              max: 1,
              display: '${(selected.backgroundColor!.a * 100).round()}%',
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
            _sliderRow(
              label: 'Arredondamento do fundo',
              value: selected.backgroundCornerRatio,
              min: 0,
              max: CollageTextItem.maxBackgroundCornerRatio,
              display:
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
        ],
      ],
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
        _TextInputDialog(initial: initial, title: title, maxLines: maxLines),
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
                        _applyTextFont(id, font.$1);
                      },
                    ),
                  // As importadas ficam na mesma grade das embutidas —
                  // segurar remove.
                  for (final font in _importedFonts)
                    _FontThumb(
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
                  _FontThumb(
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

  Widget _importTile({
    required VoidCallback onTap,
    required String label,
    double size = 62,
    double height = 46,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          children: [
            Container(
              width: size,
              height: height,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: theme.colorScheme.primary,
                size: 18,
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

  Widget _assetThumb(
    ImportedAsset asset, {
    required bool selected,
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
      // O estilo compartilhado entra por cima: uma foto escolhida depois
      // (numa célula que nasceu vazia, antes de a borda/fundo terem sido
      // ajustados) tem que aparecer igual às outras, não com os padrões.
      final replaced = _settings.withSharedCellStyle(
        cell
            .copyWith(
              photoPath: path,
              photoWidth: width,
              photoHeight: height,
              clearManualCrop: true,
            )
            .resetFraming(),
      );
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

  /// Folha de ajuste de cor: uma fileira de bolinhas (uma por ajuste, como
  /// nos editores de foto), o nome do ajuste escolhido em cima e a régua de
  /// intensidade embaixo, com o zero no centro. Cada mexida na régua é
  /// aplicada na hora à célula, então a prévia atrás da folha mostra o
  /// resultado enquanto o dedo ainda está na tela.
  void _openCellColorAdjust(int index) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // Sem véu: a régua muda a prévia da montagem em tempo real (ver
      // comentário acima), e uma barreira escura por trás escondia
      // exatamente o resultado que essa mexida deveria mostrar.
      barrierColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            if (index >= _settings.cells.length) return const SizedBox.shrink();
            final cell = _settings.cells[index];
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ColorAdjustPanel(
                  title: 'Ajustar cor',
                  hasAdjustments: cell.hasColorAdjustments,
                  valueOf: (adjustment) => adjustment.valueOf(cell),
                  onChangeStart: _pushUndoCheckpoint,
                  onChanged: (adjustment, value) {
                    _update(
                      _settings.replacingCell(
                        index,
                        adjustment.apply(cell, value),
                      ),
                      pushUndo: false,
                    );
                    sheetSetState(() {});
                  },
                  onReset: () {
                    _pushUndoCheckpoint();
                    _update(
                      _settings.replacingCell(
                        index,
                        cell.withoutColorAdjustments(),
                      ),
                      pushUndo: false,
                    );
                    sheetSetState(() {});
                  },
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
      outerMarginRatio: _settings.outerMarginRatio,
      innerMarginRatio: _settings.innerMarginRatio,
    );
    if (index >= rects.length) return 1.0;
    final rect = rects[index];
    if (rect.width <= 0 || rect.height <= 0) return 1.0;
    return rect.width / rect.height;
  }

  /// Abre o recorte de uma foto específica. O recorte é livre por padrão (a
  /// proporção da célula é só mais uma opção da fileira), então o resultado
  /// quase nunca tem a mesma proporção da célula: por isso a foto recortada
  /// entra em "encaixar" e com o enquadramento zerado — aparece inteira,
  /// centralizada e na horizontal, em vez de ser esticada/cortada pelo
  /// "preencher" para caber na célula.
  Future<void> _openCropTool(int index) async {
    final cell = _settings.cells[index];
    if (!cell.hasPhoto) return;
    final crop = await Navigator.of(context).push<CropRect>(
      MaterialPageRoute(
        builder: (_) => PhotoCropPage(
          photoPath: cell.photoPath!,
          photoWidth: cell.photoWidth,
          photoHeight: cell.photoHeight,
          cellAspectRatio: _cellAspectRatioFor(index),
          initialCrop: cell.manualCrop,
        ),
      ),
    );
    if (crop == null || !mounted) return;
    _pushUndoCheckpoint();
    _update(
      _settings.replacingCell(
        index,
        cell
            .copyWith(manualCrop: crop, fitMode: CollageCellFitMode.contain)
            .resetFraming(),
      ),
      pushUndo: false,
    );
  }

  // ---------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------

  /// Largura da exportação: grande o bastante para cada foto caber na sua
  /// célula sem encolher.
  ///
  /// Antes valia o maior lado entre as fotos, o que ignorava o layout: numa
  /// montagem com quatro fotos lado a lado, cada célula fica com ~1/4 da
  /// largura, então exportar na largura de UMA foto reduzia todas a um
  /// quarto do tamanho — era isso que saía visivelmente borrado. Agora a
  /// conta é ao contrário: mede que fração da montagem cada célula ocupa e
  /// pede a largura que devolve a resolução original de cada foto.
  int _exportWidth() {
    // A fração não depende do tamanho medido, então qualquer largura de
    // referência serve para descobrir as proporções do layout.
    const probe = 1000.0;
    final probeSize = Size(probe, probe / _settings.aspectRatio);
    final geometry = CollageGeometry.of(probeSize, _settings);
    var needed = 480.0;
    for (var i = 0; i < _settings.cells.length; i++) {
      if (i >= geometry.cellRects.length) continue;
      final cell = _settings.cells[i];
      if (!cell.hasPhoto) continue;
      final rect = geometry.cellRects[i];
      if (rect.width > 0) {
        needed = math.max(needed, cell.photoWidth * probe / rect.width);
      }
      if (rect.height > 0) {
        // Pela altura: a montagem precisa de tantas alturas quanto a célula
        // é menor que a foto, e a largura sai da proporção da montagem.
        final byHeight = cell.photoHeight * probeSize.height / rect.height;
        needed = math.max(needed, byHeight * _settings.aspectRatio);
      }
    }
    return needed.round().clamp(480, 2200);
  }

  Future<File> _writeTempFile(Uint8List bytes, String extension) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/montagem_${DateTime.now().millisecondsSinceEpoch}'
        '.$extension';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Formato e regra de duração escolhidos na última exportação — a folha de
  /// opções reabre já marcada no que a pessoa usou da última vez.
  CollageExportFormat _exportFormat = CollageExportFormat.gif;
  CollageDurationRule _durationRule = CollageDurationRule.longest;

  /// Pergunta o formato quando há foto animada na montagem; sem nenhuma, o
  /// PNG é a única saída possível e a folha não aparece. Devolve `null`
  /// quando a pessoa fecha a folha sem escolher.
  ///
  /// [_exportFormat]/[_durationRule] só guardam a última escolha para a
  /// folha já abrir marcada nela; a seleção feita durante esta chamada vive
  /// em variáveis locais (`selectedFormat`/`selectedRule`) para não vazar
  /// para outra folha que porventura esteja aberta ao mesmo tempo.
  Future<CollageExportFormat?> _askExportFormat() async {
    final info = await inspectCollageAnimation(_settings);
    if (!mounted) return null;
    if (!info.hasAnimation) return CollageExportFormat.png;

    var selectedFormat = _exportFormat;
    var selectedRule = _durationRule;

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
                    const SizedBox(height: 4),
                    Text(
                      info.animatedCount == 1
                          ? 'Uma das fotos é animada — a montagem pode sair '
                                'animada também.'
                          : '${info.animatedCount} fotos são animadas — a '
                                'montagem pode sair animada também.',
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
      });
    }
    return result;
  }

  String _formatSeconds(Duration duration) =>
      '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';

  /// Gera o arquivo final no formato escolhido: PNG direto do compositor, ou
  /// a sequência de quadros da montagem animada codificada pelo FFmpeg.
  Future<File> _buildExportFile(CollageExportFormat format) async {
    if (!format.isAnimated) {
      final bytes = await composeCollage(
        settings: _settings,
        outputWidth: _exportWidth(),
      );
      return _writeTempFile(bytes, format.extension);
    }

    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final workDir = await Directory(
      '${temp.path}/montagem_quadros_$stamp',
    ).create(recursive: true);
    try {
      final sequence = await renderCollageFrames(
        settings: _settings,
        // A animação multiplica o custo por quadro; um limite mais baixo que
        // o do PNG mantém a exportação viável no celular.
        outputWidth: _animatedExportWidth(),
        rule: _durationRule,
        workDir: workDir,
        // Desenhar os quadros é a parte longa: fica com 85% da barra, e a
        // codificação com os 15% finais.
        onProgress: (value) => _reportExportProgress(value * 0.85),
        isCancelled: () => _exportCancelled,
      );
      return await _ffmpeg.encodeCollageSequence(
        framePattern: sequence.pattern,
        fps: sequence.fps,
        outputPath: '${temp.path}/montagem_$stamp.${format.extension}',
        webp: format == CollageExportFormat.webp,
        frameCount: sequence.frameCount,
        onProgress: (value) => _reportExportProgress(0.85 + value * 0.15),
      );
    } finally {
      if (await workDir.exists()) await workDir.delete(recursive: true);
    }
  }

  /// Largura da exportação animada — o PNG usa [_exportWidth] inteiro.
  ///
  /// O teto existe porque a animação paga o custo de desenhar e codificar
  /// cada quadro; 1440 ainda cabe no celular e já é o bastante para quatro
  /// fotos de 360px lado a lado saírem sem redução.
  int _animatedExportWidth() => math.min(_exportWidth(), 1440);

  /// Tamanho final em pixels, do mesmo jeito que o compositor calcula: a
  /// altura sai da proporção da montagem.
  (int width, int height) _exportPixelSize(CollageExportFormat format) {
    final width = format.isAnimated ? _animatedExportWidth() : _exportWidth();
    final height = (width / _settings.aspectRatio).round().clamp(2, 1 << 20);
    return (width, height);
  }

  void _reportExportProgress(double value) {
    // O notifier morre junto com a tela; sem esta guarda, um quadro que
    // termina depois de sair da montagem escreveria num objeto descartado.
    if (!mounted) return;
    _exportProgress.value = ExportProgress(
      value: value.clamp(0.0, 1.0),
      cancelling: _exportProgress.value.cancelling,
    );
  }

  /// Abre o pop-up de progresso e roda a exportação. Devolve o arquivo, ou
  /// `null` quando o usuário cancelou — o pop-up sai da tela em qualquer um
  /// dos casos, inclusive em erro, para nunca sobrar um "exportando" preso.
  Future<File?> _exportWithProgress(CollageExportFormat format) async {
    // O PNG sai de uma composição só, rápida demais para valer um pop-up que
    // só piscaria na tela.
    if (!format.isAnimated) return _buildExportFile(format);

    _exportCancelled = false;
    _exportProgress.value = const ExportProgress();
    final (width, height) = _exportPixelSize(format);
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExportProgressDialog(
          progress: _exportProgress,
          formatLabel: format.label,
          width: width,
          height: height,
          onCancel: _cancelExport,
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
      if (_exportCancelled) return null;
      rethrow;
    } finally {
      navigator.pop();
    }
  }

  void _cancelExport() {
    _exportCancelled = true;
    _exportProgress.value = ExportProgress(
      value: _exportProgress.value.value,
      cancelling: true,
    );
    unawaited(_ffmpeg.cancel());
  }

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
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.initial,
    this.title = 'Texto',
    this.maxLines = 3,
  });

  final String initial;

  /// Título do diálogo — o mesmo campo serve para escrever um texto da
  /// montagem e para nomear/renomear uma pasta de stickers.
  final String title;
  final int maxLines;

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
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
      ),
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
              hintText: 'X',
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
              hintText: 'Y',
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
    this.onLongPress,
    this.icon,
  });

  final String? family;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Segurar remove — só as fontes importadas passam algo aqui.
  final VoidCallback? onLongPress;

  /// No lugar do "Aa": usado pelo tile de importar, que não tem fonte para
  /// mostrar ainda.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
}

/// Caixa colorida atrás de um texto da montagem, com o arredondamento em
/// razão do menor lado (a mesma unidade proporcional que
/// [CollageTextItem.backgroundCornerRatio] tem na exportação). Precisa de um
/// `LayoutBuilder` porque o raio depende do tamanho final da caixa, que só é
/// conhecido depois de medir o texto.
class _TextBackgroundBox extends StatelessWidget {
  const _TextBackgroundBox({
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
      painter: _TextBackgroundPainter(color: color, cornerRatio: cornerRatio),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _TextBackgroundPainter extends CustomPainter {
  const _TextBackgroundPainter({
    required this.color,
    required this.cornerRatio,
  });

  final Color color;
  final double cornerRatio;

  @override
  void paint(Canvas canvas, Size size) {
    paintCollageTextBackground(canvas, Offset.zero & size, color, cornerRatio);
  }

  @override
  bool shouldRepaint(covariant _TextBackgroundPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.cornerRatio != cornerRatio;
}
