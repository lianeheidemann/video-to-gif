import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/aspect_preset.dart';
import '../../core/models/color_adjustments.dart';
import '../../core/models/frame_settings.dart';
import '../../core/models/image_frame.dart';
import '../../core/models/photo_info.dart';
import '../../core/services/imported_frame_store.dart';
import '../../core/services/output_service.dart';
import 'services/photo_frame_compositor.dart';
import '../../core/ui/app_bar_title.dart';
import '../../core/ui/checkerboard_background.dart';
import '../../core/ui/color_adjust_controls.dart';
import '../../core/ui/crop/crop_controller.dart';
import '../../core/ui/frame/content_fit_picker.dart';
import '../../core/ui/frame/frame_color_row.dart';
import '../../core/ui/frame/frame_sliders.dart';
import '../../core/ui/frame/frame_style_picker.dart';
import '../../core/ui/frame/frame_thumb_shell.dart';
import '../../core/ui/frame/image_frame_picker.dart';
import '../../core/ui/crop/crop_overlay.dart';
import '../../core/ui/crop/crop_size_fields.dart';
import '../../core/ui/crop/cropped_view.dart';
import '../../core/ui/editor_tabs_footer.dart';
import '../../core/ui/labeled_section.dart';
import '../../core/ui/preview_settings_panel.dart';
import '../../core/ui/text_overlay_editor.dart';

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

  /// Preset travado na aba "Recorte" — guardado à parte de `_frame.crop`
  /// porque "Personalizado" e um preset podem cair no mesmo retângulo (ex.:
  /// ao digitar largura/altura que batem com 1:1), e o chip marcado tem que
  /// continuar sendo o que foi tocado. Mesma ideia de `SvgEditPage._aspect`.
  AspectPreset _aspect = AspectPreset.presets.first;

  /// Regras de recorte compartilhadas com as telas de vídeo e SVG.
  late final _crop = CropController(
    sourceWidth: widget.photo.width,
    sourceHeight: widget.photo.height,
  );

  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _widthFocus = FocusNode();
  final _heightFocus = FocusNode();

  final _textOverlay = TextOverlayController();

  /// Aba aberta no rodapé (índice em [_sections]) — `null` fecha o painel e
  /// deixa a prévia com o máximo de espaço.
  int? _activeSection = 0;

  /// Histórico de desfazer/refazer da moldura, no mesmo formato da tela de
  /// montagem: pilhas do próprio [FrameSettings], com os arrastes contínuos
  /// (sliders) empilhando um checkpoint só no início do gesto.
  final List<FrameSettings> _undoStack = [];
  final List<FrameSettings> _redoStack = [];

  bool _saving = false;
  bool _sharing = false;

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
      _frame.crop?.aspectRatio ?? widget.photo.aspectRatio;

  /// A foto da prévia, já com o ajuste de cor por cima — o mesmo filtro que
  /// `photo_frame_compositor` aplica na exportação, para a tela mostrar o
  /// que vai sair. A moldura e o fundo ficam de fora, como lá.
  Widget _photoPreview(BoxFit fit) {
    final photo = Image.file(File(widget.photo.path), fit: fit);
    if (!_frame.adjustments.hasAdjustments) return photo;
    return ColorFiltered(colorFilter: _frame.adjustments.filter, child: photo);
  }

  /// A foto já recortada pela janela da aba "Recorte" (`_frame.crop`) — o
  /// que efetivamente vai para o arquivo salvo, mesma lógica de
  /// `photo_frame_compositor.dart`. `BoxFit.fill` porque [CroppedView] já
  /// desenha o filho no tamanho nativo da foto; não há reamostragem aqui.
  Widget _croppedPhotoPreview() => CroppedView(
    sourceWidth: widget.photo.width,
    sourceHeight: widget.photo.height,
    crop: _frame.crop,
    child: _photoPreview(BoxFit.fill),
  );

  void _updateFrame(FrameSettings frame, {bool pushUndo = true}) {
    if (pushUndo) {
      _undoStack.add(_frame);
      _redoStack.clear();
    }
    setState(() => _frame = frame);
  }

  /// Empilha o estado atual antes de um gesto contínuo (slider), para o
  /// arrasto inteiro virar UM passo de desfazer em vez de um por quadro.
  void _pushUndoCheckpoint() {
    _undoStack.add(_frame);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    setState(() {
      _redoStack.add(_frame);
      _frame = previous;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    setState(() {
      _undoStack.add(_frame);
      _frame = next;
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
      final bytes = await composeFramedPhoto(
        photo: widget.photo,
        frame: _frame,
      );
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
      final bytes = await composeFramedPhoto(
        photo: widget.photo,
        frame: _frame,
      );
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
    final busy = _saving || _sharing;
    final sections = _sections;
    final active = _activeSection == null
        ? null
        : (_activeSection! < sections.length ? _activeSection : null);
    // As alças de recorte só aparecem na própria aba "Recorte" — nas outras,
    // a prévia já mostra o resultado recortado, igual ao vídeo e ao SVG.
    final showCropHandles =
        active != null && sections[active].title == 'Recorte';
    final textTabActive = active != null && sections[active].title == 'Texto';
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
  }) => showCropHandles
      ? _rawCropPreviewWithHandles()
      : _framedPreview(textTabActive);

  /// Foto inteira (sem recorte aplicado) com o véu + alças por cima — mesma
  /// ideia da aba "Ajustar" do recorte de vídeo/"Recorte" do editor de SVG.
  /// As coordenadas do recorte são sempre relativas a este tamanho original.
  Widget _rawCropPreviewWithHandles() {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: widget.photo.aspectRatio,
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
              bounds: Size(
                widget.photo.width.toDouble(),
                widget.photo.height.toDouble(),
              ),
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
                  child: ImageFrameArtwork(asset: asset, fit: BoxFit.fill),
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

  // ---------------------------------------------------------------------
  // Seção "Recorte"
  // ---------------------------------------------------------------------

  String get _cropLabel => _aspect.ratio == null
      ? '${widget.photo.width}×${widget.photo.height}'
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
            CropSizeSummary(crop: crop),
            const SizedBox(height: 12),
            CropSizeInputs(
              crop: crop,
              widthController: _widthController,
              heightController: _heightController,
              widthFocus: _widthFocus,
              heightFocus: _heightFocus,
              onSubmitWidth: _applyCropWidth,
              onSubmitHeight: _applyCropHeight,
            ),
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
        _frame = _frame.copyWith(
          crop: _frame.crop ?? _crop.defaultCustomCrop(),
        );
        return;
      }

      if (preset.ratio == null) {
        _frame = _frame.copyWith(clearCrop: true);
        return;
      }

      _frame = _frame.copyWith(crop: _crop.forRatio(preset.ratio!));
    });
  }

  /// Proporção travada pelo preset atual, ou `null` em "Personalizado".
  double? get _lockedRatio =>
      _aspect == _customAspectPreset ? null : _aspect.ratio;

  void _applyCropWidth(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > widget.photo.width) {
      _message('Largura máxima é ${widget.photo.width} (tamanho original).');
    } else if (parsed < 1) {
      _message('A largura mínima é 1.');
    }
    final crop = _frame.crop;
    if (crop == null) return;
    _updateFrame(
      _frame.copyWith(
        crop: _crop.withWidth(parsed, crop: crop, ratio: _lockedRatio),
      ),
    );
  }

  void _applyCropHeight(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > widget.photo.height) {
      _message('Altura máxima é ${widget.photo.height} (tamanho original).');
    } else if (parsed < 1) {
      _message('A altura mínima é 1.');
    }
    final crop = _frame.crop;
    if (crop == null) return;
    _updateFrame(
      _frame.copyWith(
        crop: _crop.withHeight(parsed, crop: crop, ratio: _lockedRatio),
      ),
    );
  }

  void _resetCurrentCrop() {
    if (_aspect == _customAspectPreset) {
      _updateFrame(_frame.copyWith(crop: _crop.defaultCustomCrop()));
      return;
    }
    if (_aspect.ratio == null) {
      _updateFrame(_frame.copyWith(clearCrop: true));
      return;
    }
    _updateFrame(_frame.copyWith(crop: _crop.forRatio(_aspect.ratio!)));
  }

  /// Converte o arraste de uma alça (em pixels da prévia exibida) para pixels
  /// da foto e recalcula o recorte, livre ou travado à proporção selecionada.
  /// A sobra fracionária de cada frame de gesto fica guardada no
  /// [CropController] — sem isso, fotos de baixa resolução exibidas bem
  /// maiores que o tamanho nativo fariam o arrasto parecer travado e depois
  /// "pular".
  void _resizeCropFromHandle(
    CropHandle handle,
    Offset displayDelta,
    Size previewSize,
  ) {
    final crop = _frame.crop;
    if (crop == null || previewSize.width <= 0 || previewSize.height <= 0) {
      return;
    }

    final next = _crop.resizeBy(
      crop: crop,
      handle: handle,
      sourceDelta: _toSourceDelta(displayDelta, previewSize),
      ratio: _lockedRatio,
    );
    if (next == null) return;
    _updateFrame(_frame.copyWith(crop: next));
  }

  /// Mesma conversão de [_resizeCropFromHandle], para o botão de mover a
  /// janela inteira.
  void _moveCropFromHandle(Offset displayDelta, Size previewSize) {
    final crop = _frame.crop;
    if (crop == null || previewSize.width <= 0 || previewSize.height <= 0) {
      return;
    }

    final next = _crop.moveBy(
      crop: crop,
      sourceDelta: _toSourceDelta(displayDelta, previewSize),
    );
    if (next == null) return;
    _updateFrame(_frame.copyWith(crop: next));
  }

  /// Converte um arraste em pixels da prévia exibida para pixels da foto.
  Offset _toSourceDelta(Offset displayDelta, Size previewSize) => Offset(
    displayDelta.dx * widget.photo.width / previewSize.width,
    displayDelta.dy * widget.photo.height / previewSize.height,
  );

  // ---------------------------------------------------------------------
  // Seção "Moldura" (procedural)
  // ---------------------------------------------------------------------

  Widget _frameStyleSection() {
    final theme = Theme.of(context);
    final style = _frame.style;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FrameStylePicker(
          active: _frame.style,
          onSelected: (style) => _updateFrame(frameWithStyle(_frame, style)),
        ),
        if (style != FrameStyle.none) ...[
          const SizedBox(height: 18),
          SectionCard(
            children: [
              FrameColorRow(
                label: 'Cor da moldura',
                color: _frame.color,
                onTap: _pickFrameColor,
              ),
              Divider(
                height: 13,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              FrameThicknessRow(
                frame: _frame,
                onChangeStart: _pushUndoCheckpoint,
                onChanged: (next) => _updateFrame(next, pushUndo: false),
              ),
              Divider(
                height: 13,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              CornerRadiusRow(
                frame: _frame,
                onChangeStart: _pushUndoCheckpoint,
                onChanged: (next) => _updateFrame(next, pushUndo: false),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Moldura de imagem"
  // ---------------------------------------------------------------------

  Widget _imageFrameSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ImageFramePicker(
          selected: _frame.imageFrame,
          imported: _importedImageFrames,
          onSelected: _selectImageFrame,
          onClear: () => _updateFrame(_frame.copyWith(clearImageFrame: true)),
          onImport: _importFrameImage,
          onRemoveImported: _confirmRemoveImportedFrame,
        ),
        // A resolução só existe para moldura de imagem — sem uma escolhida,
        // não há canvas próprio para dimensionar.
        if (_frame.hasFixedAspect) ...[
          const SizedBox(height: 18),
          SectionCard(children: [_frameResolutionSelector()]),
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
          ContentFitTile(
            mode: mode,
            selected: mode == selected,
            onSelected: (m) => _updateFrame(_frame.copyWith(contentFit: m)),
            zoomRow: ContentZoomRow(
              frame: _frame,
              onChangeStart: _pushUndoCheckpoint,
              onChanged: (next) => _updateFrame(next, pushUndo: false),
            ),
          ),
          if (mode != _selectableContentFitModes.last)
            const SizedBox(height: 8),
        ],
      ],
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
    if (!await confirmRemoveImportedFrame(context, asset)) return;

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

  /// Folha de cor da Montagem (swatches + conta-gotas na prévia atual + roda
  /// HSV completa) para os dois seletores de cor desta tela.
  void _pickColor({
    required String title,
    required Color selectedColor,
    required ValueChanged<Color> onSelected,
  }) {
    showFrameColorPicker(
      context: context,
      title: title,
      selectedColor: selectedColor,
      onSelected: onSelected,
      onFirstChange: _pushUndoCheckpoint,
      previewImageBuilder: _renderPreviewImage,
    );
  }

  /// Rasteriza a prévia atual (já dentro da moldura) para o conta-gotas da
  /// folha de cor poder amostrar um pixel dela.
  Future<ui.Image> _renderPreviewImage() =>
      renderPreviewImage(context, _colorPreviewKey);

  // ---------------------------------------------------------------------
  // Sliders da moldura procedural
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // "Ajuste do conteúdo" / "Resolução da moldura"
  // ---------------------------------------------------------------------

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

  // ---------------------------------------------------------------------
  // "Fundo transparente"
  // ---------------------------------------------------------------------

  /// Ajuste de cor da foto: o mesmo painel da montagem e da edição de GIF,
  /// aqui gravando em [FrameSettings.adjustments] — assim o desfazer/refazer
  /// da tela já cobre o ajuste, como cobre os outros controles.
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
          FrameColorRow(
            key: const ValueKey('backgroundColorRow'),
            label: 'Cor do fundo',
            color: _frame.backgroundColor,
            onTap: _pickBackgroundColor,
          ),
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
}
