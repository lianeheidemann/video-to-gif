import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

import '../models/aspect_preset.dart';
import '../models/color_adjustments.dart';
import '../models/crop_rect.dart';
import '../models/frame_settings.dart';
import '../models/image_frame.dart';
import '../models/eraser_mask.dart';
import '../models/photo_info.dart';
import '../services/bundled_frame_store.dart';
import '../services/imported_frame_store.dart';
import '../services/magic_eraser.dart';
import '../services/output_service.dart';
import '../services/photo_frame_compositor.dart';
import 'widgets/app_bar_title.dart';
import 'widgets/checkerboard_background.dart';
import 'widgets/color_adjust_controls.dart';
import 'widgets/color_picker_sheet.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/cropped_view.dart';
import 'widgets/editor_tabs_footer.dart';
import 'widgets/eraser_mask_overlay.dart';
import 'widgets/export_progress_dialog.dart';
import 'widgets/frame_painter.dart';
import 'widgets/labeled_section.dart';
import 'widgets/preview_settings_panel.dart';
import 'widgets/text_overlay_editor.dart';

/// Mesmos três modos apresentados ao usuário em `EditorPage` — `fit` só
/// existe como resultado interno do ajuste automático.
const _selectableContentFitModes = [
  ContentFitMode.auto,
  ContentFitMode.fill,
  ContentFitMode.expand,
];

/// Mesma ideia de `_customAspectPreset` em `editor_page.dart`/
/// `svg_edit_page.dart`: não é uma proporção de verdade (o -1 nunca é usado
/// como razão), só marca "livre" — cada alça mexe só no seu lado/canto, sem
/// travar largura/altura entre si.
const _customAspectPreset = AspectPreset('Personalizado', -1);

/// Um passo de desfazer: a moldura mais qual arquivo de foto estava em uso.
/// Os dois andam juntos porque a borracha mágica troca o arquivo, e voltar
/// só a moldura deixaria o desfazer pela metade.
typedef _EditStep = ({FrameSettings frame, PhotoInfo photo});

/// Tela dedicada a aplicar uma moldura (procedural ou de imagem) a uma foto
/// estática. Reaproveita o mesmo modelo ([FrameSettings], [ImageFrameAsset])
/// e a mesma biblioteca de molduras ([ImportedFrameStore]) da aba "Frame" de
/// `EditorPage`, mas sem as abas "Ajustar"/"Frame" nem a linha do tempo — a
/// tela inteira é sobre moldura, e a composição final é feita com
/// `dart:ui`/[Canvas] puro (ver `photo_frame_compositor.dart`), sem FFmpeg.
class PhotoFramePage extends StatefulWidget {
  const PhotoFramePage({super.key, required this.photo});

  final PhotoInfo photo;

  @override
  State<PhotoFramePage> createState() => _PhotoFramePageState();
}

class _PhotoFramePageState extends State<PhotoFramePage> {
  static const _output = OutputService();
  final _importedFrameStore = ImportedFrameStore();

  /// Ancorada no `RepaintBoundary` em volta da prévia — [_renderPreviewImage]
  /// usa isso para rasterizar exatamente o que está na tela para o
  /// conta-gotas do seletor de cor.
  final _colorPreviewKey = GlobalKey();

  FrameSettings _frame = const FrameSettings();
  List<ImageFrameAsset> _importedImageFrames = [];

  /// A foto em edição. Começa sendo a que chegou pela rota e é **trocada** a
  /// cada apagada da borracha mágica, por um PNG temporário já corrigido. As
  /// dimensões nunca mudam, então `_frame.crop` (que está em pixels da foto)
  /// continua valendo.
  late PhotoInfo _photo = widget.photo;

  /// Os PNGs que a borracha gerou nesta sessão de edição. Ficam vivos
  /// enquanto a tela existe porque a pilha de desfazer aponta para eles;
  /// somem todos juntos no [dispose].
  final List<String> _erasedFiles = [];

  /// Estado da aba "Borracha": a seleção atual e como ela é desenhada.
  EraserMask _eraserMask = EraserMask.empty;
  EraserTool _eraserTool = EraserTool.brush;
  EraserQuality _eraserQuality = EraserQuality.normal;

  /// Tamanho do pincel como porcentagem do menor lado da foto — ver
  /// [brushRadiusFor]. Em pixels fixos, o mesmo valor seria um respingo numa
  /// foto grande e um borrão numa pequena.
  double _brushPercent = 4;

  /// Sobe a cada apagada para que "Tentar de novo" mude de verdade o
  /// resultado em vez de repetir o mesmo sorteio.
  int _eraseSeed = 0;

  /// A última seleção que foi apagada, para o "Tentar de novo" poder repetir
  /// a mesma região com outra semente.
  EraserMask? _lastErased;

  /// O arquivo que a última apagada produziu. "Tentar de novo" só vale
  /// enquanto ele ainda é a foto em uso: se a pessoa mexeu em outra coisa
  /// depois, desfazer para tentar de novo derrubaria essa outra mudança.
  String? _lastErasedPath;

  bool get _canRetryErase =>
      _lastErased != null && _lastErasedPath == _photo.path;

  final _eraserCanvasKey = GlobalKey<EraserCanvasState>();

  /// Preset travado na aba "Recorte" — guardado à parte de `_frame.crop`
  /// porque "Personalizado" e um preset podem cair no mesmo retângulo (ex.:
  /// ao digitar largura/altura que batem com 1:1), e o chip marcado tem que
  /// continuar sendo o que foi tocado. Mesma ideia de `SvgEditPage._aspect`.
  AspectPreset _aspect = AspectPreset.presets.first;

  /// Sobra fracionária do arrasto de recorte, de um frame de gesto pro
  /// próximo — mesmo motivo de `SvgEditPage._resizeDragRemainder`/
  /// `_moveDragRemainder`: sem acumular, arrastos pequenos em fotos de baixa
  /// resolução ficam parados a maior parte do tempo e depois "pulam".
  Offset _resizeDragRemainder = Offset.zero;
  Offset _moveDragRemainder = Offset.zero;

  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _widthFocus = FocusNode();
  final _heightFocus = FocusNode();

  final _textOverlay = TextOverlayController();

  /// Aba aberta no rodapé (índice em [_sections]) — `null` fecha o painel e
  /// deixa a prévia com o máximo de espaço.
  int? _activeSection = 0;

  /// Histórico de desfazer/refazer, no mesmo formato da tela de montagem:
  /// pilhas do estado inteiro, com os arrastes contínuos (sliders)
  /// empilhando um checkpoint só no início do gesto.
  ///
  /// Guarda também qual foto estava em uso: antes da borracha bastava a
  /// moldura, mas apagar algo troca o arquivo, e desfazer tem que voltar os
  /// dois juntos.
  final List<_EditStep> _undoStack = [];
  final List<_EditStep> _redoStack = [];

  bool _saving = false;
  bool _sharing = false;
  bool _erasing = false;

  @override
  void initState() {
    super.initState();
    _loadImportedFrames();
    _textOverlay.loadFonts();
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _widthFocus.dispose();
    _heightFocus.dispose();
    _textOverlay.dispose();
    // Os PNGs da borracha só existem para esta edição: quem quis guardar já
    // salvou ou compartilhou.
    for (final path in _erasedFiles) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
    super.dispose();
  }

  Future<void> _loadImportedFrames() async {
    final frames = await _importedFrameStore.loadAll();
    if (!mounted) return;
    setState(() => _importedImageFrames = frames);
  }

  /// Proporção efetiva da foto depois do recorte da aba "Recorte" — a
  /// própria proporção nativa quando nenhuma janela foi escolhida
  /// ("Original").
  double get _photoAspectRatio =>
      _frame.crop?.aspectRatio ?? _photo.aspectRatio;

  /// A foto da prévia, já com o ajuste de cor por cima — o mesmo filtro que
  /// `photo_frame_compositor` aplica na exportação, para a tela mostrar o
  /// que vai sair. A moldura e o fundo ficam de fora, como lá.
  Widget _photoPreview(BoxFit fit) {
    final photo = Image.file(File(_photo.path), fit: fit);
    if (!_frame.adjustments.hasAdjustments) return photo;
    return ColorFiltered(colorFilter: _frame.adjustments.filter, child: photo);
  }

  /// A foto já recortada pela janela da aba "Recorte" (`_frame.crop`) — o
  /// que efetivamente vai para o arquivo salvo, mesma lógica de
  /// `photo_frame_compositor.dart`. `BoxFit.fill` porque [CroppedView] já
  /// desenha o filho no tamanho nativo da foto; não há reamostragem aqui.
  Widget _croppedPhotoPreview() => CroppedView(
    sourceWidth: _photo.width,
    sourceHeight: _photo.height,
    crop: _frame.crop,
    child: _photoPreview(BoxFit.fill),
  );

  _EditStep get _currentStep => (frame: _frame, photo: _photo);

  void _updateFrame(FrameSettings frame, {bool pushUndo = true}) {
    if (pushUndo) {
      _undoStack.add(_currentStep);
      _redoStack.clear();
    }
    setState(() => _frame = frame);
  }

  /// Empilha o estado atual antes de um gesto contínuo (slider), para o
  /// arrasto inteiro virar UM passo de desfazer em vez de um por quadro.
  void _pushUndoCheckpoint() {
    _undoStack.add(_currentStep);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    setState(() {
      _redoStack.add(_currentStep);
      _frame = previous.frame;
      _photo = previous.photo;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    setState(() {
      _undoStack.add(_currentStep);
      _frame = next.frame;
      _photo = next.photo;
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<File> _writeTempPng(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/moldura_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes = await composeFramedPhoto(photo: _photo, frame: _frame);
      final file = await _writeTempPng(bytes);
      await _output.saveToGallery(file);
      if (!mounted) return;
      _message('Foto salva na galeria.');
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
      final bytes = await composeFramedPhoto(photo: _photo, frame: _frame);
      final file = await _writeTempPng(bytes);
      await _output.share(
        file,
        mimeType: 'image/png',
        text: 'Foto com moldura feita com o app Video to GIF',
      );
    } catch (_) {
      if (!mounted) return;
      _message('Não foi possível gerar a imagem.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// O estilo procedural que a aba "Moldura" deve mostrar. Com uma moldura
  /// de imagem ativa é sempre "Sem moldura": as duas famílias são mutuamente
  /// exclusivas, como na aba "Frame" do editor de vídeo.
  FrameStyle get _activeFrameStyle =>
      _frame.imageFrame == null ? _frame.style : FrameStyle.none;

  /// As seções da tela, na ordem em que aparecem na barra de baixo — as
  /// mesmas de antes, só que como abas em vez de cards empilhados numa lista
  /// rolável (mesmo rodapé da tela de montagem).
  List<EditorSection> get _sections => [
    EditorSection(
      icon: Icons.crop_rounded,
      title: 'Recorte',
      value: _cropLabel,
      builder: (_) => _cropSection(),
    ),
    EditorSection(
      icon: Icons.auto_fix_high_rounded,
      title: 'Borracha mágica',
      label: 'Borracha',
      value: _eraserMask.isEmpty ? 'Nenhuma seleção' : 'Seleção pronta',
      builder: (_) => _eraserSection(),
    ),
    EditorSection(
      icon: Icons.smartphone_rounded,
      title: 'Moldura',
      value: _activeFrameStyle.label,
      builder: (_) => _frameStyleSection(),
    ),
    EditorSection(
      icon: Icons.image_outlined,
      title: 'Moldura de imagem',
      label: 'Imagem',
      value: _frame.imageFrame?.label ?? FrameStyle.none.label,
      builder: (_) => _imageFrameSection(),
    ),
    if (_frame.hasFixedAspect)
      EditorSection(
        icon: Icons.fit_screen_rounded,
        title: 'Ajuste da foto',
        label: 'Ajuste',
        value: _frame.contentFit.label,
        builder: (_) => _contentFitSection(),
      ),
    EditorSection(
      icon: Icons.tune_rounded,
      title: 'Ajustar cor',
      label: 'Cor',
      value: _frame.adjustments.hasAdjustments ? 'Ajustada' : 'Original',
      builder: (_) => _colorAdjustSection(),
    ),
    EditorSection(
      icon: Icons.text_fields_rounded,
      title: 'Texto',
      value: _frame.texts.isEmpty ? 'Nenhum' : '${_frame.texts.length}',
      builder: (_) => _textSection(),
    ),
    EditorSection(
      icon: Icons.wallpaper_rounded,
      title: 'Fundo',
      value: _frame.transparentBackground ? 'Transparente' : 'Cor',
      builder: (_) => _backgroundSection(),
    ),
    // Última aba da barra nas três telas de edição (vídeo, foto e
    // montagem) — configurações gerais, não deste recorte/moldura em si.
    EditorSection(
      icon: Icons.settings_rounded,
      title: 'Configurações',
      label: 'Ajustes',
      builder: (_) => const PreviewSettingsPanel(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _sharing || _erasing;
    final sections = _sections;
    final active = _activeSection == null
        ? null
        : (_activeSection! < sections.length ? _activeSection : null);
    // As alças de recorte só aparecem na própria aba "Recorte" — nas outras,
    // a prévia já mostra o resultado recortado, igual ao vídeo e ao SVG.
    final showCropHandles =
        active != null && sections[active].title == 'Recorte';
    final textTabActive = active != null && sections[active].title == 'Texto';
    // A borracha trabalha sobre a foto inteira, sem recorte nem moldura: o
    // que se apaga é conteúdo da foto, não do enquadramento.
    final eraserTabActive =
        active != null && sections[active].title == 'Borracha mágica';
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Editar imagem'),
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
              child: PreviewAreaBackground(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: RepaintBoundary(
                      key: _colorPreviewKey,
                      child: _preview(
                        showCropHandles: showCropHandles,
                        textTabActive: textTabActive,
                        eraserTabActive: eraserTabActive,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            EditorTabsFooter(
              sections: sections,
              activeIndex: active,
              onSelected: (index) => setState(() => _activeSection = index),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Prévia
  // ---------------------------------------------------------------------

  Widget _preview({
    required bool showCropHandles,
    required bool textTabActive,
    required bool eraserTabActive,
  }) {
    if (eraserTabActive) return _eraserPreview();
    return showCropHandles
        ? _rawCropPreviewWithHandles()
        : _framedPreview(textTabActive);
  }

  /// Prévia da borracha: a foto crua (sem recorte nem moldura) com o véu da
  /// seleção por cima. Crua de propósito — apagar mexe no conteúdo da foto,
  /// então o que vale é a coordenada dela, não a do enquadramento.
  Widget _eraserPreview() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: EraserCanvas(
        key: _eraserCanvasKey,
        photoWidth: _photo.width,
        photoHeight: _photo.height,
        mask: _eraserMask,
        tool: _eraserTool,
        brushRadius: brushRadiusFor(_brushPercent, _photo.width, _photo.height),
        enabled: !_erasing,
        onMaskChanged: (mask) => setState(() => _eraserMask = mask),
        onZoomChanged: (_) => setState(() {}),
        child: _photoPreview(BoxFit.fill),
      ),
    );
  }

  /// Foto inteira (sem recorte aplicado) com o véu + alças por cima — mesma
  /// ideia da aba "Ajustar" do recorte de vídeo/"Recorte" do editor de SVG.
  /// As coordenadas do recorte são sempre relativas a este tamanho original.
  Widget _rawCropPreviewWithHandles() {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: _photo.aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _photoPreview(BoxFit.fill),
            CropOverlay(
              bounds: Size(_photo.width.toDouble(), _photo.height.toDouble()),
              crop: _frame.crop,
              onResize: _resizeCropFromHandle,
              onMove: _moveCropFromHandle,
              freeform: _aspect == _customAspectPreset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _framedPreview(bool textTabActive) {
    final frame = _frame;
    final double aspect;
    final Widget content;
    if (frame.imageFrame != null) {
      aspect = frame.imageFrame!.nativeAspectRatio;
      content = _imageFramedPreview(frame.imageFrame!);
    } else {
      aspect = _photoAspectRatio;
      content = frame.style == FrameStyle.none
          ? _plainPreview()
          : _proceduralFramedPreview();
    }

    return AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            content,
            TextOverlayStack(
              controller: _textOverlay,
              texts: _frame.texts,
              onChanged: (texts) =>
                  _updateFrame(_frame.copyWith(texts: texts), pushUndo: false),
              canvasSize: constraints.biggest,
              interactive: textTabActive,
              onGestureStart: _pushUndoCheckpoint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _plainPreview() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _croppedPhotoPreview(),
    );
  }

  Widget _proceduralFramedPreview() {
    final frame = _frame;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thickness = frame.thicknessFor(width);
        final outerRadius = frame.cornerRadiusFor(width);
        final innerRadius = (outerRadius - thickness).clamp(0.0, outerRadius);

        final bordered = Container(
          color: frame.color,
          padding: EdgeInsets.all(thickness),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(innerRadius),
            child: _croppedPhotoPreview(),
          ),
        );

        final rounded = ClipRRect(
          borderRadius: BorderRadius.circular(outerRadius),
          child: bordered,
        );
        if (frame.transparentBackground) return rounded;
        return ColoredBox(color: frame.backgroundColor, child: rounded);
      },
    );
  }

  Widget _imageFramedPreview(ImageFrameAsset asset) {
    final preview = AspectRatio(
      aspectRatio: asset.nativeAspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final rect = Rect.fromLTWH(
            size.width * asset.contentRect.left,
            size.height * asset.contentRect.top,
            size.width * asset.contentRect.width,
            size.height * asset.contentRect.height,
          );
          final fit = resolveContentFit(
            _frame.contentFit,
            _photoAspectRatio,
            rect.width / rect.height,
          );

          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: _imageFrameContentPreview(fit),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: _imageFrameArtwork(asset, fit: BoxFit.fill),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (_frame.transparentBackground) return preview;
    return ColoredBox(color: _frame.backgroundColor, child: preview);
  }

  Widget _imageFrameContentPreview(ContentFitMode fit) {
    // Tamanho de referência qualquer, na proporção certa (a real do recorte
    // não importa aqui — `FittedBox` só olha para a proporção do filho) —
    // mesma técnica de `EditorPage._imageFrameContentPreview`.
    Widget photo(BoxFit boxFit) => FittedBox(
      fit: boxFit,
      child: SizedBox(
        width: 1000,
        height: 1000 / _photoAspectRatio,
        child: _croppedPhotoPreview(),
      ),
    );

    if (fit != ContentFitMode.expand) {
      return ColoredBox(
        color: Colors.black,
        child: ClipRect(
          child: photo(
            fit == ContentFitMode.fill ? BoxFit.cover : BoxFit.contain,
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: Transform.scale(
          scale: _frame.effectiveContentZoom,
          child: photo(BoxFit.contain),
        ),
      ),
    );
  }

  Widget _imageFrameArtwork(ImageFrameAsset asset, {required BoxFit fit}) {
    return switch (asset.source) {
      ImageFrameSource.bundledSvg => SvgPicture.asset(
        asset.svgAssetPath!,
        fit: fit,
      ),
      ImageFrameSource.importedSvg => SvgPicture.file(
        File(asset.imageFilePath!),
        fit: fit,
      ),
      ImageFrameSource.importedImage => Image.file(
        File(asset.imageFilePath!),
        fit: fit,
      ),
    };
  }

  // ---------------------------------------------------------------------
  // Seção "Recorte"
  // ---------------------------------------------------------------------

  String get _cropLabel => _aspect.ratio == null
      ? '${_photo.width}×${_photo.height}'
      : _aspect.label;

  Widget _cropSection() {
    final crop = _frame.crop;
    final visiblePresets = <AspectPreset>[
      ...AspectPreset.presets,
      _customAspectPreset,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OptionChips<AspectPreset>(
          options: visiblePresets,
          selected: visiblePresets.contains(_aspect)
              ? _aspect
              : visiblePresets.first,
          labelBuilder: (preset) => preset.label,
          onSelected: _selectAspectPreset,
        ),
        if (crop != null) ...[
          const SizedBox(height: 18),
          if (_aspect == _customAspectPreset) ...[
            _cropSizeSummary(crop),
            const SizedBox(height: 12),
            _cropSizeInputs(crop),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _resetCurrentCrop,
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: const Text('Centralizar e redefinir'),
            ),
          ),
        ],
      ],
    );
  }

  /// Aplica o preset de proporção escolhido: cria um recorte customizado,
  /// remove o recorte ("Original") ou centraliza um recorte na proporção
  /// fixa selecionada.
  void _selectAspectPreset(AspectPreset preset) {
    setState(() {
      _aspect = preset;

      if (preset == _customAspectPreset) {
        _frame = _frame.copyWith(crop: _frame.crop ?? _defaultCustomCrop());
        return;
      }

      if (preset.ratio == null) {
        _frame = _frame.copyWith(clearCrop: true);
        return;
      }

      _frame = _frame.copyWith(
        crop: CropRect.centeredIn(_photo.width, _photo.height, preset.ratio!),
      );
    });
  }

  /// Recorte inicial do preset "Personalizado": 80% da foto, centralizado.
  CropRect _defaultCustomCrop() {
    final width = (_photo.width * 0.8).round().clamp(1, _photo.width);
    final height = (_photo.height * 0.8).round().clamp(1, _photo.height);
    return _cropAroundCenter(width, height);
  }

  Widget _cropSizeSummary(CropRect crop) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.aspect_ratio_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Janela de recorte',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${crop.width}×${crop.height}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Campos numéricos de largura/altura do recorte, sincronizados com o
  /// estado atual enquanto não estão em foco — mesmo padrão de
  /// `EditorPage._cropSizeInputs`/`SvgEditPage._cropSizeInputs`.
  Widget _cropSizeInputs(CropRect crop) {
    if (!_widthFocus.hasFocus) _syncSizeField(_widthController, crop.width);
    if (!_heightFocus.hasFocus) {
      _syncSizeField(_heightController, crop.height);
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _widthController,
            focusNode: _widthFocus,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Largura',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: _applyCropWidth,
            onTapOutside: (_) => _applyCropWidth(_widthController.text),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _heightController,
            focusNode: _heightFocus,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Altura',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: _applyCropHeight,
            onTapOutside: (_) => _applyCropHeight(_heightController.text),
          ),
        ),
      ],
    );
  }

  void _syncSizeField(TextEditingController controller, int value) {
    final text = value.toString();
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _applyCropWidth(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > _photo.width) {
      _message('Largura máxima é ${_photo.width} (tamanho original).');
    } else if (parsed < 1) {
      _message('A largura mínima é 1.');
    }
    _setCropWidth(parsed);
  }

  void _applyCropHeight(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > _photo.height) {
      _message('Altura máxima é ${_photo.height} (tamanho original).');
    } else if (parsed < 1) {
      _message('A altura mínima é 1.');
    }
    _setCropHeight(parsed);
  }

  void _setCropWidth(int width) {
    final crop = _frame.crop;
    if (crop == null) return;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    var w = width.clamp(1, _photo.width);
    int h;
    if (ratio != null) {
      h = (w / ratio).round().clamp(1, _photo.height);
      w = (h * ratio).round().clamp(1, _photo.width);
    } else {
      h = crop.height;
    }

    _updateFrame(_frame.copyWith(crop: _cropAroundCenter(w, h, around: crop)));
  }

  void _setCropHeight(int height) {
    final crop = _frame.crop;
    if (crop == null) return;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    var h = height.clamp(1, _photo.height);
    int w;
    if (ratio != null) {
      w = (h * ratio).round().clamp(1, _photo.width);
      h = (w / ratio).round().clamp(1, _photo.height);
    } else {
      w = crop.width;
    }

    _updateFrame(_frame.copyWith(crop: _cropAroundCenter(w, h, around: crop)));
  }

  void _resetCurrentCrop() {
    if (_aspect == _customAspectPreset) {
      _updateFrame(_frame.copyWith(crop: _defaultCustomCrop()));
      return;
    }
    if (_aspect.ratio == null) {
      _updateFrame(_frame.copyWith(clearCrop: true));
      return;
    }
    _updateFrame(
      _frame.copyWith(
        crop: CropRect.centeredIn(_photo.width, _photo.height, _aspect.ratio!),
      ),
    );
  }

  CropRect _cropAroundCenter(int width, int height, {CropRect? around}) {
    final safeWidth = width.clamp(1, _photo.width);
    final safeHeight = height.clamp(1, _photo.height);

    final centerX = around == null
        ? _photo.width / 2
        : around.x + around.width / 2;
    final centerY = around == null
        ? _photo.height / 2
        : around.y + around.height / 2;

    final maxX = _photo.width - safeWidth;
    final maxY = _photo.height - safeHeight;
    final x = (centerX - safeWidth / 2).round().clamp(0, maxX);
    final y = (centerY - safeHeight / 2).round().clamp(0, maxY);

    return CropRect(x: x, y: y, width: safeWidth, height: safeHeight);
  }

  /// Converte o arraste de uma alça (em pixels da prévia exibida) para
  /// pixels da foto e recalcula o recorte, livre ou travado à proporção
  /// selecionada. Acumula a sobra fracionária de um frame de gesto pro
  /// próximo (ver [_resizeDragRemainder]) — sem isso, fotos de baixa
  /// resolução exibidas bem maiores que o tamanho nativo fariam o arrasto
  /// parecer travado e depois "pular".
  void _resizeCropFromHandle(
    CropHandle handle,
    Offset displayDelta,
    Size previewSize,
  ) {
    final crop = _frame.crop;
    if (crop == null || previewSize.width <= 0 || previewSize.height <= 0) {
      return;
    }

    final dx =
        _resizeDragRemainder.dx +
        displayDelta.dx * _photo.width / previewSize.width;
    final dy =
        _resizeDragRemainder.dy +
        displayDelta.dy * _photo.height / previewSize.height;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    final next = ratio == null
        ? resizeFreeCrop(
            crop,
            handle,
            dx,
            dy,
            boundsWidth: _photo.width,
            boundsHeight: _photo.height,
          )
        : resizeLockedCrop(
            crop,
            handle,
            dx,
            dy,
            ratio,
            boundsWidth: _photo.width,
            boundsHeight: _photo.height,
          );

    if (next.width == crop.width &&
        next.height == crop.height &&
        next.x == crop.x &&
        next.y == crop.y) {
      _resizeDragRemainder = Offset(dx, dy);
      return;
    }

    _resizeDragRemainder = Offset.zero;
    _updateFrame(_frame.copyWith(crop: next));
  }

  /// Mesma lógica de sobra fracionária de [_resizeCropFromHandle], para o
  /// botão de mover a janela inteira.
  void _moveCropFromHandle(Offset displayDelta, Size previewSize) {
    final crop = _frame.crop;
    if (crop == null || previewSize.width <= 0 || previewSize.height <= 0) {
      return;
    }

    final dx =
        displayDelta.dx * _photo.width / previewSize.width +
        _moveDragRemainder.dx;
    final dy =
        displayDelta.dy * _photo.height / previewSize.height +
        _moveDragRemainder.dy;

    final maxX = (_photo.width - crop.width).clamp(0, _photo.width);
    final maxY = (_photo.height - crop.height).clamp(0, _photo.height);
    final rawX = (crop.x + dx).clamp(0.0, maxX.toDouble());
    final rawY = (crop.y + dy).clamp(0.0, maxY.toDouble());
    final x = rawX.round();
    final y = rawY.round();

    _moveDragRemainder = Offset(rawX - x, rawY - y);

    if (x == crop.x && y == crop.y) return;

    _updateFrame(
      _frame.copyWith(
        crop: crop.copyWith(x: x, y: y),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Moldura" (procedural)
  // ---------------------------------------------------------------------

  Widget _frameStyleSection() {
    final theme = Theme.of(context);
    final style = _frame.style;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _frameStyleThumbnails(),
        if (style != FrameStyle.none) ...[
          const SizedBox(height: 18),
          _sectionCard(
            children: [
              _frameColorRow(),
              Divider(
                height: 13,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              _frameThicknessRow(),
              Divider(
                height: 13,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              _cornerRadiusRow(),
            ],
          ),
        ],
      ],
    );
  }

  Widget _frameStyleThumbnails() {
    final active = _frame.style;
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: FrameStyle.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final style = FrameStyle.values[index];
          return _frameStyleThumb(style, selected: style == active);
        },
      ),
    );
  }

  Widget _frameStyleThumb(FrameStyle style, {required bool selected}) {
    return _frameThumbShell(
      key: ValueKey('frameStyleThumb_${style.name}'),
      label: style.label,
      selected: selected,
      padding: const EdgeInsets.all(8),
      onTap: () => _selectFrameStyle(style),
      child: _frameStyleGlyph(
        style,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _frameStyleGlyph(FrameStyle style, {required Color color}) {
    if (style == FrameStyle.none) {
      return Icon(
        Icons.crop_free_rounded,
        size: 16,
        color: color.withValues(alpha: 0.6),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final outerRadius = style.defaultCornerRatio * size.shortestSide;
        final inset = size.shortestSide * 0.22;
        final innerRadius = (outerRadius - inset).clamp(0.0, outerRadius);
        return Stack(
          children: [
            CustomPaint(
              size: size,
              painter: FramePainter(
                FrameSettings(
                  style: style,
                  color: color,
                  thicknessAtReference: style.defaultThickness,
                  cornerRatio: style.defaultCornerRatio,
                  transparentBackground: true,
                ),
              ),
            ),
            Positioned(
              left: inset,
              top: inset,
              right: inset,
              bottom: inset,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(innerRadius),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _selectFrameStyle(FrameStyle style) {
    _updateFrame(
      _frame.copyWith(
        style: style,
        cornerRatio: style.defaultCornerRatio,
        thicknessAtReference: style.defaultThickness,
        clearImageFrame: true,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Moldura de imagem"
  // ---------------------------------------------------------------------

  Widget _imageFrameSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _imageFrameThumbnails(),
        // A resolução só existe para moldura de imagem — sem uma escolhida,
        // não há canvas próprio para dimensionar.
        if (_frame.hasFixedAspect) ...[
          const SizedBox(height: 18),
          _sectionCard(children: [_frameResolutionSelector()]),
        ],
      ],
    );
  }

  /// "Ajuste da foto" virou aba própria (só aparece com moldura de imagem
  /// ativa), então aqui não cabe mais o cabeçalho recolhível que ela tinha
  /// como sub-seção.
  Widget _contentFitSection() {
    final selected = _frame.contentFit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final mode in _selectableContentFitModes) ...[
          _contentFitTile(mode, selected: mode == selected),
          if (mode != _selectableContentFitModes.last)
            const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _imageFrameThumbnails() {
    final selected = _frame.imageFrame;
    final assets = [...bundledImageFrames, ..._importedImageFrames];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: assets.length + 2,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) return _noImageFrameThumb(selected: selected == null);
          if (index == assets.length + 1) return _importFrameThumb();
          final asset = assets[index - 1];
          return _imageFrameThumb(asset, selected: asset.id == selected?.id);
        },
      ),
    );
  }

  Widget _noImageFrameThumb({required bool selected}) {
    final theme = Theme.of(context);
    return _frameThumbShell(
      key: const ValueKey('imageFrameThumb_none'),
      label: FrameStyle.none.label,
      selected: selected,
      padding: const EdgeInsets.all(8),
      onTap: () => _updateFrame(_frame.copyWith(clearImageFrame: true)),
      child: Icon(
        Icons.crop_free_rounded,
        size: 16,
        color: theme.colorScheme.primary.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _imageFrameThumb(ImageFrameAsset asset, {required bool selected}) {
    return _frameThumbShell(
      key: ValueKey('imageFrameThumb_${asset.id}'),
      label: asset.label,
      selected: selected,
      padding: const EdgeInsets.all(4),
      onTap: () => _selectImageFrame(asset),
      onLongPress: asset.source == ImageFrameSource.bundledSvg
          ? null
          : () => _confirmRemoveImportedFrame(asset),
      child: _imageFrameArtwork(asset, fit: BoxFit.contain),
    );
  }

  Widget _importFrameThumb() {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _importFrameImage,
      child: SizedBox(
        width: 46,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
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
            const SizedBox(height: 6),
            Text(
              'Importar',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  void _selectImageFrame(ImageFrameAsset asset) {
    _updateFrame(_frame.copyWith(style: FrameStyle.none, imageFrame: asset));
  }

  Future<void> _importFrameImage() async {
    try {
      final asset = await _importedFrameStore.importFrame();
      if (!mounted) return;
      setState(() => _importedImageFrames = [..._importedImageFrames, asset]);
      _selectImageFrame(asset);
    } on ImportedFrameException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _confirmRemoveImportedFrame(ImageFrameAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover moldura?'),
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

    await _importedFrameStore.remove(asset.id);
    if (!mounted) return;
    setState(() {
      _importedImageFrames = _importedImageFrames
          .where((a) => a.id != asset.id)
          .toList();
      if (_frame.imageFrame?.id == asset.id) {
        _updateFrame(_frame.copyWith(clearImageFrame: true));
      }
    });
  }

  // ---------------------------------------------------------------------
  // Cor (compartilhada entre moldura e fundo)
  // ---------------------------------------------------------------------

  Widget _frameColorRow() => _colorPickerRow(
    label: 'Cor da moldura',
    color: _frame.color,
    onTap: _pickFrameColor,
  );

  Widget _backgroundColorRow() => _colorPickerRow(
    key: const ValueKey('backgroundColorRow'),
    label: 'Cor do fundo',
    color: _frame.backgroundColor,
    onTap: _pickBackgroundColor,
  );

  Widget _colorPickerRow({
    Key? key,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      key: key,
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

  void _pickFrameColor() => _pickColor(
    title: 'Cor da moldura',
    selectedColor: _frame.color,
    onSelected: (color) =>
        _updateFrame(_frame.copyWith(color: color), pushUndo: false),
  );

  void _pickBackgroundColor() => _pickColor(
    title: 'Cor do fundo',
    selectedColor: _frame.backgroundColor,
    onSelected: (color) =>
        _updateFrame(_frame.copyWith(backgroundColor: color), pushUndo: false),
  );

  /// Mesma folha de cor da Montagem (swatches + conta-gotas na prévia atual
  /// + roda HSV completa) para os dois seletores de cor desta tela — antes
  /// esta tela tinha sua própria folha, só com swatches fixos.
  ///
  /// O checkpoint de desfazer entra na primeira cor escolhida, não na
  /// abertura do painel nem em cada mexida da roda HSV/conta-gotas — mesmo
  /// cuidado que `CollagePage._pickBorderColor` já tinha: sem isso, arrastar
  /// pela roda de cor empilharia um passo de desfazer por quadro.
  void _pickColor({
    required String title,
    required Color selectedColor,
    required ValueChanged<Color> onSelected,
  }) {
    var checkpointPushed = false;
    showCollageColorPickerSheet(
      context: context,
      title: title,
      initialColor: selectedColor,
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

  /// Rasteriza a prévia atual (já dentro da moldura) para o conta-gotas da
  /// folha de cor poder amostrar um pixel dela — mesma técnica de
  /// `CollagePage._renderPreviewImage`, mas capturando o que já está
  /// desenhado na tela em vez de recompor do zero.
  Future<ui.Image> _renderPreviewImage() async {
    final renderObject = _colorPreviewKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('Prévia indisponível para o conta-gotas.');
    }
    return renderObject.toImage(
      pixelRatio: MediaQuery.of(context).devicePixelRatio,
    );
  }

  // ---------------------------------------------------------------------
  // Sliders da moldura procedural
  // ---------------------------------------------------------------------

  Widget _frameThicknessRow() {
    final theme = Theme.of(context);
    final frame = _frame;
    final thickness = frame.thicknessAtReference.clamp(0, 24).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Espessura da borda',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              '${thickness.round()}px',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          min: 0,
          max: 24,
          divisions: 24,
          value: thickness,
          label: '${thickness.round()}px',
          onChangeStart: (_) => _pushUndoCheckpoint(),
          onChanged: (v) => _updateFrame(
            frame.copyWith(thicknessAtReference: v),
            pushUndo: false,
          ),
        ),
      ],
    );
  }

  Widget _cornerRadiusRow() {
    final theme = Theme.of(context);
    final frame = _frame;
    const max = FrameSettings.maxCornerRatio;
    final ratio = frame.cornerRatio.clamp(0.0, max).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Arredondamento dos cantos',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              '${(ratio / max * 100).round()}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          min: 0,
          max: max,
          divisions: 25,
          value: ratio,
          label: '${(ratio / max * 100).round()}%',
          onChangeStart: (_) => _pushUndoCheckpoint(),
          onChanged: (v) =>
              _updateFrame(frame.copyWith(cornerRatio: v), pushUndo: false),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // "Ajuste do conteúdo" / "Resolução da moldura"
  // ---------------------------------------------------------------------

  Widget _contentZoomRow() {
    final theme = Theme.of(context);
    final frame = _frame;
    final zoom = frame.contentZoom
        .clamp(FrameSettings.minContentZoom, FrameSettings.maxContentZoom)
        .toDouble();
    final percent = (zoom * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Zoom do conteúdo',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              '$percent%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          key: const ValueKey('frameContentZoomSlider'),
          min: FrameSettings.minContentZoom,
          max: FrameSettings.maxContentZoom,
          divisions: 58,
          value: zoom,
          label: '$percent%',
          onChangeStart: (_) => _pushUndoCheckpoint(),
          onChanged: (v) =>
              _updateFrame(frame.copyWith(contentZoom: v), pushUndo: false),
        ),
      ],
    );
  }

  Widget _frameResolutionSelector() {
    final theme = Theme.of(context);
    final selected = _frame.frameResolutionMode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resolução da moldura', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          SegmentedButton<ImageFrameResolutionMode>(
            key: const ValueKey('frameResolutionSegmentedButton'),
            segments: const [
              ButtonSegment(
                value: ImageFrameResolutionMode.matchAjustar,
                label: Text(
                  'Da foto',
                  key: ValueKey('frameResolutionSegment_matchAjustar'),
                ),
              ),
              ButtonSegment(
                value: ImageFrameResolutionMode.nativeMax,
                label: Text(
                  'Máxima',
                  key: ValueKey('frameResolutionSegment_nativeMax'),
                ),
              ),
            ],
            selected: {selected},
            showSelectedIcon: true,
            expandedInsets: EdgeInsets.zero,
            onSelectionChanged: (selection) => _updateFrame(
              _frame.copyWith(frameResolutionMode: selection.single),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentFitTile(ContentFitMode mode, {required bool selected}) {
    final theme = Theme.of(context);
    final showZoom = selected && mode == ContentFitMode.expand;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            key: ValueKey('contentFitTile_${mode.name}'),
            onTap: () => _updateFrame(_frame.copyWith(contentFit: mode)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: _contentFitTileHeader(mode, selected: selected),
            ),
          ),
          if (showZoom)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _contentZoomRow(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _contentFitTileHeader(ContentFitMode mode, {required bool selected}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _contentFitIcon(mode),
            size: 16,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            mode.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (selected)
          Icon(
            Icons.check_circle_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
      ],
    );
  }

  IconData _contentFitIcon(ContentFitMode mode) => switch (mode) {
    ContentFitMode.auto => Icons.auto_fix_high_rounded,
    ContentFitMode.fill => Icons.crop_free_rounded,
    ContentFitMode.fit => Icons.fit_screen_rounded,
    ContentFitMode.expand => Icons.open_in_full_rounded,
  };

  // ---------------------------------------------------------------------
  // "Fundo transparente"
  // ---------------------------------------------------------------------

  /// Ajuste de cor da foto: o mesmo painel da montagem e da edição de GIF,
  /// aqui gravando em [FrameSettings.adjustments] — assim o desfazer/refazer
  /// da tela já cobre o ajuste, como cobre os outros controles.
  // ---------------------------------------------------------------------
  // Aba "Borracha mágica"
  // ---------------------------------------------------------------------

  /// O painel da borracha. A ordem segue o uso: escolher a ferramenta,
  /// ajustar o pincel, apagar — e só depois os botões de arrependimento.
  Widget _eraserSection() {
    final theme = Theme.of(context);
    final canvas = _eraserCanvasKey.currentState;
    final radius = brushRadiusFor(_brushPercent, _photo.width, _photo.height);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pinte o que quer tirar da foto. Um dedo pinta, dois dão zoom.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tool in EraserTool.values)
              ChoiceChip(
                label: Text(tool.label),
                selected: _eraserTool == tool,
                onSelected: _erasing
                    ? null
                    : (_) => setState(() => _eraserTool = tool),
              ),
          ],
        ),
        // O slider só faz sentido para as ferramentas que têm espessura; o
        // laço e o retângulo desenham área fechada.
        if (!_eraserTool.isArea) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tamanho do pincel',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '${radius.round() * 2}px',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            min: 0.5,
            max: 20,
            divisions: 39,
            value: _brushPercent,
            label: '${radius.round() * 2}px',
            onChanged: _erasing
                ? null
                : (v) => setState(() => _brushPercent = v),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text('Qualidade', style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final quality in EraserQuality.values)
                  ChoiceChip(
                    label: Text(quality.label),
                    selected: _eraserQuality == quality,
                    onSelected: _erasing
                        ? null
                        : (_) => setState(() => _eraserQuality = quality),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Mais qualidade demora mais. Áreas pequenas saem em resolução '
          'cheia em qualquer opção.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (_eraserMask.isEmpty || _erasing) ? null : _erase,
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('Apagar'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: (_eraserMask.isEmpty || _erasing)
                  ? null
                  : () => setState(() => _eraserMask = EraserMask.empty),
              child: const Text('Limpar'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            if (_eraserMask.strokes.isNotEmpty && !_erasing)
              TextButton.icon(
                onPressed: () =>
                    setState(() => _eraserMask = _eraserMask.removeLast()),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Desfazer traço'),
              ),
            // Só aparece depois de uma apagada: outra semente dá outro
            // resultado para a mesma seleção, que é a saída quando o
            // primeiro preenchimento não convence.
            if (_canRetryErase && !_erasing)
              TextButton.icon(
                onPressed: _retryErase,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar de novo'),
              ),
            if (canvas?.isZoomed ?? false)
              TextButton.icon(
                onPressed: canvas!.resetZoom,
                icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
                label: const Text('Enquadrar'),
              ),
          ],
        ),
      ],
    );
  }

  /// Apaga a seleção atual. Cada apagada é um passo de desfazer inteiro: a
  /// foto anterior continua no disco, então voltar é imediato.
  Future<void> _erase() => _runErase(_eraserMask, _eraseSeed + 1);

  /// Repete a última apagada com outra semente. Desfaz a anterior primeiro,
  /// senão a segunda tentativa preencheria por cima de um preenchimento — o
  /// que empilha borrão em vez de dar uma alternativa.
  Future<void> _retryErase() {
    final mask = _lastErased;
    if (mask == null || !_canRetryErase) return Future.value();
    // Desfazer primeiro: sem isso a segunda tentativa preencheria por cima do
    // primeiro preenchimento, empilhando borrão em vez de oferecer uma
    // alternativa. `_canRetryErase` garante que o topo da pilha é mesmo a
    // apagada, e não alguma outra mudança feita depois.
    _undo();
    return _runErase(mask, _eraseSeed + 1);
  }

  Future<void> _runErase(EraserMask mask, int seed) async {
    final progress = ValueNotifier(const ExportProgress());
    final before = _currentStep;
    setState(() => _erasing = true);

    final task = startMagicErase(
      photo: _photo,
      mask: mask,
      quality: _eraserQuality,
      seed: seed,
      onProgress: (value) =>
          progress.value = ExportProgress(value: value.clamp(0.0, 1.0)),
    );

    // O pop-up continua ouvindo `progress` durante a animação de saída, então
    // o notifier só pode ser descartado depois que a rota some de verdade —
    // daí guardar este future em vez de descartar no `finally`.
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportProgressDialog(
        progress: progress,
        formatLabel: 'PNG',
        title: 'Apagando da foto',
        width: _photo.width,
        height: _photo.height,
        onCancel: () {
          progress.value = ExportProgress(
            value: progress.value.value,
            cancelling: true,
          );
          task.cancel();
        },
      ),
    );

    try {
      final bytes = await task.done;
      final file = await _writeTempPng(bytes);
      final erased = PhotoInfo(
        path: file.path,
        // A recomposição desenha num canvas do tamanho da foto, então as
        // dimensões são as mesmas por construção — e é disso que o recorte
        // e a moldura dependem para continuar válidos.
        width: _photo.width,
        height: _photo.height,
      );
      _erasedFiles.add(file.path);
      if (!mounted) return;
      setState(() {
        _undoStack.add(before);
        _redoStack.clear();
        _photo = erased;
        _eraserMask = EraserMask.empty;
        _lastErased = mask;
        _lastErasedPath = erased.path;
        _eraseSeed = seed;
      });
    } on MagicEraserCancelled {
      // Cancelar não é erro: a pessoa pediu para parar.
    } on MagicEraserException catch (e) {
      if (mounted) _message(e.message);
    } catch (_) {
      if (mounted) _message('Não foi possível apagar essa área.');
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _erasing = false);
      }
      unawaited(dialog.whenComplete(progress.dispose));
    }
  }

  Widget _colorAdjustSection() {
    final adjustments = _frame.adjustments;
    return ColorAdjustPanel(
      hasAdjustments: adjustments.hasAdjustments,
      valueOf: (adjustment) => adjustment.valueIn(adjustments),
      onChangeStart: _pushUndoCheckpoint,
      onChanged: (adjustment, value) => _updateFrame(
        _frame.copyWith(adjustments: adjustment.applyIn(adjustments, value)),
        pushUndo: false,
      ),
      onReset: () {
        _pushUndoCheckpoint();
        _updateFrame(
          _frame.copyWith(adjustments: ColorAdjustments.neutral),
          pushUndo: false,
        );
      },
    );
  }

  Widget _textSection() {
    _textOverlay.dropSelectionIfGone(_frame.texts);
    return TextOverlayPanel(
      controller: _textOverlay,
      texts: _frame.texts,
      onChanged: (texts) => _updateFrame(_frame.copyWith(texts: texts)),
      previewImageBuilder: _renderPreviewImage,
      onGestureStart: _pushUndoCheckpoint,
    );
  }

  Widget _backgroundSection() {
    final frame = _frame;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const ValueKey('transparentBackgroundSwitch'),
          children: [
            Expanded(
              child: Text(
                'Fundo transparente',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Switch(
              value: frame.transparentBackground,
              onChanged: (v) =>
                  _updateFrame(frame.copyWith(transparentBackground: v)),
            ),
          ],
        ),
        if (!frame.transparentBackground) ...[
          Divider(
            height: 13,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          _backgroundColorRow(),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // Utilitários visuais compartilhados
  // ---------------------------------------------------------------------

  Widget _frameThumbShell({
    required Key key,
    required String label,
    required bool selected,
    required EdgeInsets padding,
    required VoidCallback onTap,
    required Widget child,
    VoidCallback? onLongPress,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 46,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  padding: padding,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: child,
                ),
                if (selected)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
