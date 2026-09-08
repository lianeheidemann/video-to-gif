import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

import '../models/frame_settings.dart';
import '../models/image_frame.dart';
import '../models/photo_info.dart';
import '../services/imported_frame_store.dart';
import '../services/output_service.dart';
import '../services/photo_frame_compositor.dart';
import 'widgets/frame_painter.dart';
import 'widgets/labeled_section.dart';

/// Mesmos três modos apresentados ao usuário em `EditorPage` — `fit` só
/// existe como resultado interno do ajuste automático.
const _selectableContentFitModes = [
  ContentFitMode.auto,
  ContentFitMode.fill,
  ContentFitMode.expand,
];

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

  FrameSettings _frame = const FrameSettings();
  List<ImageFrameAsset> _importedImageFrames = [];
  bool _contentFitExpanded = false;

  bool _saving = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadImportedFrames();
  }

  Future<void> _loadImportedFrames() async {
    final frames = await _importedFrameStore.loadAll();
    if (!mounted) return;
    setState(() => _importedImageFrames = frames);
  }

  double get _photoAspectRatio => widget.photo.aspectRatio;

  void _updateFrame(FrameSettings frame) => setState(() => _frame = frame);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moldura em foto')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _framedPreview(),
            const SizedBox(height: 20),
            _frameStyleSection(),
            _imageFrameSection(),
            _backgroundSection(),
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

  Widget _framedPreview() {
    final frame = _frame;
    if (frame.imageFrame != null) return _imageFramedPreview(frame.imageFrame!);

    return AspectRatio(
      aspectRatio: _photoAspectRatio,
      child: frame.style == FrameStyle.none
          ? _plainPreview()
          : _proceduralFramedPreview(),
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
      child: Image.file(File(widget.photo.path), fit: BoxFit.cover),
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
            child: Image.file(File(widget.photo.path), fit: BoxFit.cover),
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
    Widget photo(BoxFit boxFit) =>
        Image.file(File(widget.photo.path), fit: boxFit);

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
  // Seção "Moldura" (procedural)
  // ---------------------------------------------------------------------

  Widget _frameStyleSection() {
    final theme = Theme.of(context);
    final style = _frame.style;

    return LabeledSection(
      icon: Icons.smartphone_rounded,
      title: 'Moldura',
      value: style.label,
      hint: 'Escolha uma opção',
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _frameStyleThumbnails(),
          if (style != FrameStyle.none) ...[
            const SizedBox(height: 18),
            _sectionCard(
              children: [
                _frameColorRow(),
                Divider(
                  height: 17,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
                _frameThicknessRow(),
                Divider(
                  height: 17,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
                _cornerRadiusRow(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _frameStyleThumbnails() {
    final active = _frame.style;
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: FrameStyle.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
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
      padding: const EdgeInsets.all(11),
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
        size: 22,
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
    final hasFixedAspect = _frame.hasFixedAspect;
    return LabeledSection(
      icon: Icons.image_outlined,
      title: 'Moldura de imagem',
      value: _frame.imageFrame?.label ?? FrameStyle.none.label,
      hint: 'Escolha uma opção',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _imageFrameThumbnails(),
          if (hasFixedAspect) ...[
            const SizedBox(height: 18),
            _sectionCard(children: [_contentFitSubsection()]),
            const SizedBox(height: 18),
            _sectionCard(children: [_frameResolutionSelector()]),
          ],
        ],
      ),
    );
  }

  Widget _imageFrameThumbnails() {
    final selected = _frame.imageFrame;
    final assets = [...ImageFrameLibrary.bundled, ..._importedImageFrames];
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: assets.length + 2,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
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
      padding: const EdgeInsets.all(11),
      onTap: () => _updateFrame(_frame.copyWith(clearImageFrame: true)),
      child: Icon(
        Icons.crop_free_rounded,
        size: 22,
        color: theme.colorScheme.primary.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _imageFrameThumb(ImageFrameAsset asset, {required bool selected}) {
    return _frameThumbShell(
      key: ValueKey('imageFrameThumb_${asset.id}'),
      label: asset.label,
      selected: selected,
      padding: const EdgeInsets.all(6),
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
        width: 62,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
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

  static const _colorSwatches = <Color>[
    Color(0xFFC9A8FF),
    Colors.white,
    Colors.black,
    Color(0xFFE57373),
    Color(0xFF58C78C),
    Color(0xFFB8B36A),
    Color(0xFF64B5F6),
    Color(0xFFE6A15D),
  ];

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

  void _pickFrameColor() => _pickColor(
    title: 'Cor da moldura',
    selectedColor: _frame.color,
    onSelected: (color) => _updateFrame(_frame.copyWith(color: color)),
  );

  void _pickBackgroundColor() => _pickColor(
    title: 'Cor do fundo',
    selectedColor: _frame.backgroundColor,
    onSelected: (color) =>
        _updateFrame(_frame.copyWith(backgroundColor: color)),
  );

  void _pickColor({
    required String title,
    required Color selectedColor,
    required ValueChanged<Color> onSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final color in _colorSwatches)
                      _colorSwatchButton(
                        color,
                        selected: color == selectedColor,
                        onTap: () {
                          onSelected(color);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _colorSwatchButton(
    Color color, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 3 : 1.5,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 18,
                color: _contrastingIconColor(color),
              )
            : null,
      ),
    );
  }

  Color _contrastingIconColor(Color background) =>
      background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

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
          onChanged: (v) =>
              _updateFrame(frame.copyWith(thicknessAtReference: v)),
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
          onChanged: (v) => _updateFrame(frame.copyWith(cornerRatio: v)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // "Ajuste do conteúdo" / "Resolução da moldura"
  // ---------------------------------------------------------------------

  Widget _contentFitSubsection() {
    final selected = _frame.contentFit;
    return _collapsibleSubsection(
      label: 'Ajuste do conteúdo',
      expanded: _contentFitExpanded,
      onToggle: () =>
          setState(() => _contentFitExpanded = !_contentFitExpanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final mode in _selectableContentFitModes) ...[
            _contentFitTile(mode, selected: mode == selected),
            if (mode != _selectableContentFitModes.last)
              const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

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
          onChanged: (v) => _updateFrame(frame.copyWith(contentZoom: v)),
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _contentFitIcon(mode),
            size: 20,
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

  Widget _backgroundSection() {
    final frame = _frame;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _sectionCard(
        children: [
          SwitchListTile(
            key: const ValueKey('transparentBackgroundSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Fundo transparente'),
            value: frame.transparentBackground,
            onChanged: (v) =>
                _updateFrame(frame.copyWith(transparentBackground: v)),
          ),
          if (!frame.transparentBackground) ...[
            const Divider(height: 1),
            _backgroundColorRow(),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------

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
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
        ),
      ],
    );
  }

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
        width: 62,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 62,
                  height: 62,
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
                      width: 18,
                      height: 18,
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
                        size: 12,
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

  Widget _collapsibleSubsection({
    required String label,
    String? subtitle,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodySmall),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[const SizedBox(height: 8), child],
      ],
    );
  }
}
