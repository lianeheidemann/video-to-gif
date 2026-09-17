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
import '../models/photo_info.dart';
import '../services/imported_frame_store.dart';
import '../services/output_service.dart';
import '../services/photo_frame_compositor.dart';
import 'widgets/app_bar_title.dart';
import 'widgets/checkerboard_background.dart';
import 'widgets/color_adjust_controls.dart';
import 'widgets/color_picker_sheet.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/cropped_view.dart';
import 'widgets/editor_tabs_footer.dart';
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
        borderRadius: BorderRadius.circular(22),
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
        crop: CropRect.centeredIn(
          widget.photo.width,
          widget.photo.height,
          preset.ratio!,
        ),
      );
    });
  }

  /// Recorte inicial do preset "Personalizado": 80% da foto, centralizado.
  CropRect _defaultCustomCrop() {
    final width = (widget.photo.width * 0.8).round().clamp(
      1,
      widget.photo.width,
    );
    final height = (widget.photo.height * 0.8).round().clamp(
      1,
      widget.photo.height,
    );
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
    if (parsed > widget.photo.width) {
      _message('Largura máxima é ${widget.photo.width} (tamanho original).');
    } else if (parsed < 1) {
      _message('A largura mínima é 1.');
    }
    _setCropWidth(parsed);
  }

  void _applyCropHeight(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > widget.photo.height) {
      _message('Altura máxima é ${widget.photo.height} (tamanho original).');
    } else if (parsed < 1) {
      _message('A altura mínima é 1.');
    }
    _setCropHeight(parsed);
  }

  void _setCropWidth(int width) {
    final crop = _frame.crop;
    if (crop == null) return;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    var w = width.clamp(1, widget.photo.width);
    int h;
    if (ratio != null) {
      h = (w / ratio).round().clamp(1, widget.photo.height);
      w = (h * ratio).round().clamp(1, widget.photo.width);
    } else {
      h = crop.height;
    }

    _updateFrame(_frame.copyWith(crop: _cropAroundCenter(w, h, around: crop)));
  }

  void _setCropHeight(int height) {
    final crop = _frame.crop;
    if (crop == null) return;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    var h = height.clamp(1, widget.photo.height);
    int w;
    if (ratio != null) {
      w = (h * ratio).round().clamp(1, widget.photo.width);
      h = (w / ratio).round().clamp(1, widget.photo.height);
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
        crop: CropRect.centeredIn(
          widget.photo.width,
          widget.photo.height,
          _aspect.ratio!,
        ),
      ),
    );
  }

  CropRect _cropAroundCenter(int width, int height, {CropRect? around}) {
    final safeWidth = width.clamp(1, widget.photo.width);
    final safeHeight = height.clamp(1, widget.photo.height);

    final centerX = around == null
        ? widget.photo.width / 2
        : around.x + around.width / 2;
    final centerY = around == null
        ? widget.photo.height / 2
        : around.y + around.height / 2;

    final maxX = widget.photo.width - safeWidth;
    final maxY = widget.photo.height - safeHeight;
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
        displayDelta.dx * widget.photo.width / previewSize.width;
    final dy =
        _resizeDragRemainder.dy +
        displayDelta.dy * widget.photo.height / previewSize.height;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    final next = ratio == null
        ? resizeFreeCrop(
            crop,
            handle,
            dx,
            dy,
            boundsWidth: widget.photo.width,
            boundsHeight: widget.photo.height,
          )
        : resizeLockedCrop(
            crop,
            handle,
            dx,
            dy,
            ratio,
            boundsWidth: widget.photo.width,
            boundsHeight: widget.photo.height,
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
        displayDelta.dx * widget.photo.width / previewSize.width +
        _moveDragRemainder.dx;
    final dy =
        displayDelta.dy * widget.photo.height / previewSize.height +
        _moveDragRemainder.dy;

    final maxX = (widget.photo.width - crop.width).clamp(0, widget.photo.width);
    final maxY = (widget.photo.height - crop.height).clamp(
      0,
      widget.photo.height,
    );
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
    final assets = [...ImageFrameLibrary.bundled, ..._importedImageFrames];
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
