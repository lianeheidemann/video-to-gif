import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/aspect_preset.dart';
import '../../core/models/color_adjustments.dart';
import '../../core/models/crop_rect.dart';
import 'models/svg_edit_settings.dart';
import 'models/svg_info.dart';
import '../../core/services/output_service.dart';
import 'services/svg_xml_editor.dart';
import '../../core/ui/app_bar_title.dart';
import '../../core/ui/checkerboard_background.dart';
import '../../core/ui/color_adjust_controls.dart';
import '../../core/ui/crop/crop_controller.dart';
import '../../core/ui/frame/frame_color_row.dart';
import '../../core/ui/crop/crop_overlay.dart';
import '../../core/ui/crop/crop_size_fields.dart';
import '../../core/ui/crop/cropped_view.dart';
import '../../core/ui/editor_tabs_footer.dart';
import '../../core/ui/labeled_section.dart';
import '../../core/ui/preview_settings_panel.dart';

/// Sentinela do preset "Personalizado" na fileira de proporções — mesma
/// ideia de `_customAspectPreset` em `editor_page.dart`: não é uma proporção
/// de verdade (`ratio: -1`), só um valor que não bate com nenhum preset de
/// [AspectPreset.presets], usado pra saber quando mostrar os campos de
/// largura/altura em vez de travar a uma proporção fixa.
const _customAspectPreset = AspectPreset('Personalizado', -1);

/// Tela de recorte/edição de um SVG — mantém o arquivo como vetor o tempo
/// todo: a prévia é só composição de widgets (nunca mexe no XML), e o XML só
/// é reescrito de verdade na hora de salvar/compartilhar
/// (`svg_xml_editor.dart`). Separada de `PhotoFramePage` de propósito: as
/// duas telas não compartilham nada da exportação (uma sempre sai PNG
/// rasterizado, a outra sempre sai SVG de verdade).
class SvgEditPage extends StatefulWidget {
  const SvgEditPage({super.key, required this.svg});

  final SvgInfo svg;

  @override
  State<SvgEditPage> createState() => _SvgEditPageState();
}

class _SvgEditPageState extends State<SvgEditPage> {
  static const _output = OutputService();

  /// Ancorada no `RepaintBoundary` em volta da prévia — [_renderPreviewImage]
  /// usa isso para rasterizar exatamente o que está na tela para o
  /// conta-gotas do seletor de cor, mesma técnica de `PhotoFramePage`.
  final _colorPreviewKey = GlobalKey();

  SvgEditSettings _settings = const SvgEditSettings();

  /// Regras de recorte compartilhadas com as telas de vídeo e foto. O SVG
  /// usa uma janela mínima menor que o padrão: 32 quebraria um ícone de
  /// 24x24, bem comum no formato.
  late final _crop = CropController(
    sourceWidth: _sourceWidth,
    sourceHeight: _sourceHeight,
    minHandleSize: _minCropSize,
  );

  /// Preset de proporção travado na aba "Recorte" — guardado à parte de
  /// `_settings.crop` porque "Personalizado" e um preset podem cair no
  /// mesmo retângulo (ex.: ao digitar largura/altura que batem com 1:1), e
  /// o chip marcado tem que continuar sendo o que foi tocado.
  AspectPreset _aspect = AspectPreset.presets.first;

  final List<SvgEditSettings> _undoStack = [];
  final List<SvgEditSettings> _redoStack = [];

  int? _activeSection = 0;
  bool _saving = false;
  bool _sharing = false;

  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _widthFocus = FocusNode();
  final _heightFocus = FocusNode();

  int get _sourceWidth => widget.svg.width.round();
  int get _sourceHeight => widget.svg.height.round();

  /// Tamanho de [_sourceWidth]/[_sourceHeight] depois de girar — 90°/270°
  /// trocam largura por altura. É o que a aba "Recorte" mostra e mede: a
  /// prévia ali reflete girar/espelhar (ver [_rawPreviewWithHandles]), então
  /// a janela de recorte é medida no espaço já girado, não no original.
  int get _displayWidth =>
      _settings.rotationQuarterTurns.isOdd ? _sourceHeight : _sourceWidth;
  int get _displayHeight =>
      _settings.rotationQuarterTurns.isOdd ? _sourceWidth : _sourceHeight;

  /// Janela mínima arrastável pela alça — 32 (o padrão do recorte de vídeo/
  /// foto, que nunca é menor que isso) quebraria um ícone de 24x24, bem
  /// comum em SVG. Escala com o próprio tamanho do SVG.
  double get _minCropSize =>
      (math.min(_sourceWidth, _sourceHeight) / 8).clamp(1, 32);

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _widthFocus.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  void _update(SvgEditSettings settings, {bool pushUndo = true}) {
    if (pushUndo) {
      _undoStack.add(_settings);
      _redoStack.clear();
    }
    setState(() => _settings = settings);
  }

  /// Empilha o estado atual antes de um gesto contínuo (slider/roda de cor),
  /// para o arrasto inteiro virar UM passo de desfazer.
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
  // Abas
  // ---------------------------------------------------------------------

  List<EditorSection> get _sections => [
    EditorSection(
      icon: Icons.crop_rounded,
      title: 'Recorte',
      value: _cropLabel,
      builder: (_) => _cropSection(),
    ),
    EditorSection(
      icon: Icons.rotate_90_degrees_ccw_rounded,
      title: 'Girar/Espelhar',
      label: 'Girar',
      value: _rotateFlipLabel,
      builder: (_) => _rotateFlipSection(),
    ),
    EditorSection(
      icon: Icons.wallpaper_rounded,
      title: 'Fundo',
      value: _settings.transparentBackground ? 'Transparente' : 'Cor',
      builder: (_) => _backgroundSection(),
    ),
    EditorSection(
      icon: Icons.filter_b_and_w_rounded,
      title: 'Filtro',
      value: _settings.filterType.label,
      builder: (_) => _filterSection(),
    ),
    EditorSection(
      icon: Icons.tune_rounded,
      title: 'Ajustar cor',
      label: 'Cor',
      value: _settings.adjustments.hasAdjustments ? 'Ajustada' : 'Original',
      builder: (_) => _colorAdjustSection(),
    ),
    EditorSection(
      icon: Icons.opacity_rounded,
      title: 'Opacidade',
      value: '${(_settings.opacity * 100).round()}%',
      builder: (_) => _opacitySection(),
    ),
    // Última aba da barra nas três telas de edição (vídeo, foto e montagem)
    // — configurações gerais, não deste SVG em si.
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
    // a prévia já mostra o resultado recortado, igual ao vídeo em
    // `EditorPage`.
    final showCropHandles =
        active != null && sections[active].title == 'Recorte';

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Editar SVG'),
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
            tooltip: _saving ? 'Salvando…' : 'Salvar',
            onPressed: busy ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt_rounded),
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
                      child: _preview(showCropHandles: showCropHandles),
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

  Widget _preview({required bool showCropHandles}) =>
      showCropHandles ? _rawPreviewWithHandles() : _croppedDecoratedPreview();

  /// SVG inteiro (sem recorte aplicado) com o véu + alças por cima, igual à
  /// aba "Ajustar" do recorte de vídeo — mas, ao contrário de antes, já
  /// mostrado girado/espelhado (ver [_displayWidth]/[_displayHeight] e o
  /// `Transform`/`RotatedBox` abaixo), pra não parecer que "Girar" foi
  /// desfeito ao abrir esta aba. A janela de recorte em si continua guardada
  /// em espaço original (ver [SvgEditSettings.crop]) — [_toDisplayCrop]
  /// converte só pra desenhar aqui, e [_resizeCropFromHandle]/
  /// [_moveCropFromHandle] convertem o arrasto de volta.
  Widget _rawPreviewWithHandles() {
    final theme = Theme.of(context);
    Widget picture = SvgPicture.file(File(widget.svg.path), fit: BoxFit.fill);
    if (_settings.rotationQuarterTurns != 0) {
      picture = RotatedBox(
        quarterTurns: _settings.rotationQuarterTurns,
        child: picture,
      );
    }
    if (_settings.flipHorizontal || _settings.flipVertical) {
      picture = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          _settings.flipHorizontal ? -1.0 : 1.0,
          _settings.flipVertical ? -1.0 : 1.0,
          1.0,
        ),
        child: picture,
      );
    }

    final crop = _settings.crop;
    return AspectRatio(
      aspectRatio: _displayWidth / _displayHeight,
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
            picture,
            CropOverlay(
              bounds: Size(_displayWidth.toDouble(), _displayHeight.toDouble()),
              crop: crop == null ? null : _toDisplayCrop(crop),
              onResize: _resizeCropFromHandle,
              onMove: _moveCropFromHandle,
              freeform: _aspect == _customAspectPreset,
            ),
          ],
        ),
      ),
    );
  }

  /// O resultado já recortado/girado/espelhado/com filtro e opacidade — o
  /// que efetivamente vai para o arquivo salvo, mesma ordem de composição
  /// de `svg_xml_editor.dart`'s `renderEditedSvg`.
  Widget _croppedDecoratedPreview() {
    final theme = Theme.of(context);
    Widget content = CroppedView(
      sourceWidth: _sourceWidth,
      sourceHeight: _sourceHeight,
      crop: _settings.crop,
      child: SvgPicture.file(File(widget.svg.path), fit: BoxFit.fill),
    );

    if (_settings.rotationQuarterTurns != 0) {
      content = RotatedBox(
        quarterTurns: _settings.rotationQuarterTurns,
        child: content,
      );
    }
    if (_settings.flipHorizontal || _settings.flipVertical) {
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          _settings.flipHorizontal ? -1.0 : 1.0,
          _settings.flipVertical ? -1.0 : 1.0,
          1.0,
        ),
        child: content,
      );
    }
    // Ajuste fino primeiro, preset por cima — mesma ordem de
    // `svg_xml_editor.dart`'s `applyFilterSvg`, para a prévia nunca divergir
    // do arquivo exportado.
    if (_settings.adjustments.hasAdjustments) {
      content = ColorFiltered(
        colorFilter: _settings.adjustments.filter,
        child: content,
      );
    }
    final filter = _settings.previewColorFilter;
    if (filter != null) {
      content = ColorFiltered(colorFilter: filter, child: content);
    }
    if (_settings.opacity < 1) {
      content = Opacity(opacity: _settings.opacity, child: content);
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _settings.transparentBackground
          ? content
          : ColoredBox(color: _settings.backgroundColor, child: content),
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Recorte"
  // ---------------------------------------------------------------------

  String get _cropLabel =>
      _aspect.ratio == null ? '$_sourceWidth×$_sourceHeight' : _aspect.label;

  Widget _cropSection() {
    final crop = _settings.crop;
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
        _settings = _settings.copyWith(
          crop: _settings.crop ?? _crop.defaultCustomCrop(),
        );
        return;
      }

      if (preset.ratio == null) {
        _settings = _settings.copyWith(clearCrop: true);
        return;
      }

      _settings = _settings.copyWith(crop: _crop.forRatio(preset.ratio!));
    });
  }

  /// Proporção travada pelo preset atual, ou `null` em "Personalizado".
  double? get _lockedRatio =>
      _aspect == _customAspectPreset ? null : _aspect.ratio;

  void _applyCropWidth(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > _sourceWidth) {
      _message('Largura máxima é $_sourceWidth (tamanho original do SVG).');
    } else if (parsed < 1) {
      _message('A largura mínima é 1.');
    }
    final crop = _settings.crop;
    if (crop == null) return;
    _update(
      _settings.copyWith(
        crop: _crop.withWidth(parsed, crop: crop, ratio: _lockedRatio),
      ),
    );
  }

  void _applyCropHeight(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > _sourceHeight) {
      _message('Altura máxima é $_sourceHeight (tamanho original do SVG).');
    } else if (parsed < 1) {
      _message('A altura mínima é 1.');
    }
    final crop = _settings.crop;
    if (crop == null) return;
    _update(
      _settings.copyWith(
        crop: _crop.withHeight(parsed, crop: crop, ratio: _lockedRatio),
      ),
    );
  }

  void _resetCurrentCrop() {
    if (_aspect == _customAspectPreset) {
      _update(_settings.copyWith(crop: _crop.defaultCustomCrop()));
      return;
    }
    if (_aspect.ratio == null) {
      _update(_settings.copyWith(clearCrop: true));
      return;
    }
    _update(_settings.copyWith(crop: _crop.forRatio(_aspect.ratio!)));
  }

  /// Converte um [CropRect] do espaço original do SVG pro espaço de exibição
  /// atual (já girado/espelhado) — só pra desenhar a janela por cima da
  /// prévia transformada em [_rawPreviewWithHandles]; [SvgEditSettings.crop]
  /// continua sempre guardado no espaço original.
  CropRect _toDisplayCrop(CropRect crop) {
    var x = crop.x;
    var y = crop.y;
    var w = crop.width;
    var h = crop.height;
    var boundsW = _sourceWidth;
    var boundsH = _sourceHeight;

    for (var i = 0; i < _settings.rotationQuarterTurns; i++) {
      final newX = boundsH - (y + h);
      final newY = x;
      x = newX;
      y = newY;
      final newW = h;
      final newH = w;
      w = newW;
      h = newH;
      final newBoundsW = boundsH;
      final newBoundsH = boundsW;
      boundsW = newBoundsW;
      boundsH = newBoundsH;
    }
    if (_settings.flipHorizontal) x = boundsW - (x + w);
    if (_settings.flipVertical) y = boundsH - (y + h);

    return CropRect(x: x, y: y, width: w, height: h);
  }

  CropHandle _mirrorHandleHorizontally(CropHandle handle) => switch (handle) {
    CropHandle.topLeft => CropHandle.topRight,
    CropHandle.topRight => CropHandle.topLeft,
    CropHandle.bottomLeft => CropHandle.bottomRight,
    CropHandle.bottomRight => CropHandle.bottomLeft,
    CropHandle.left => CropHandle.right,
    CropHandle.right => CropHandle.left,
    CropHandle.top => CropHandle.top,
    CropHandle.bottom => CropHandle.bottom,
  };

  CropHandle _mirrorHandleVertically(CropHandle handle) => switch (handle) {
    CropHandle.topLeft => CropHandle.bottomLeft,
    CropHandle.bottomLeft => CropHandle.topLeft,
    CropHandle.topRight => CropHandle.bottomRight,
    CropHandle.bottomRight => CropHandle.topRight,
    CropHandle.top => CropHandle.bottom,
    CropHandle.bottom => CropHandle.top,
    CropHandle.left => CropHandle.left,
    CropHandle.right => CropHandle.right,
  };

  /// Um passo pra trás no ciclo horário de cantos/lados — desfaz um quarto
  /// de volta de rotação na identidade do handle (ex.: o que a pessoa vê
  /// como canto superior-direito, com a arte girada 90°, é o canto
  /// superior-esquerdo no espaço original).
  CropHandle _undoQuarterTurn(CropHandle handle) => switch (handle) {
    CropHandle.topLeft => CropHandle.bottomLeft,
    CropHandle.topRight => CropHandle.topLeft,
    CropHandle.bottomRight => CropHandle.topRight,
    CropHandle.bottomLeft => CropHandle.bottomRight,
    CropHandle.top => CropHandle.left,
    CropHandle.right => CropHandle.top,
    CropHandle.bottom => CropHandle.right,
    CropHandle.left => CropHandle.bottom,
  };

  /// Converte o handle e o delta arrastados na prévia — que mostra a arte já
  /// girada/espelhada — para o handle e o delta equivalentes no espaço
  /// original, onde [SvgEditSettings.crop] é definido. Sem isso, arrastar um
  /// canto com rotação/espelhamento ativos mexeria no lado errado do
  /// recorte. Desfaz na ordem inversa de como a prévia compõe a transformação
  /// (girar primeiro, espelhar depois — ver [_rawPreviewWithHandles]):
  /// primeiro desfaz o espelhamento, depois a rotação.
  (CropHandle, Offset) _toSourceHandleAndDelta(
    CropHandle handle,
    Offset delta,
  ) {
    var h = handle;
    var dx = delta.dx;
    var dy = delta.dy;

    if (_settings.flipHorizontal) {
      h = _mirrorHandleHorizontally(h);
      dx = -dx;
    }
    if (_settings.flipVertical) {
      h = _mirrorHandleVertically(h);
      dy = -dy;
    }
    for (var i = 0; i < _settings.rotationQuarterTurns; i++) {
      h = _undoQuarterTurn(h);
      final nextDx = dy;
      final nextDy = -dx;
      dx = nextDx;
      dy = nextDy;
    }

    return (h, Offset(dx, dy));
  }

  /// Converte o arraste de uma alça (em pixels da prévia exibida) para
  /// unidades do SVG e recalcula o recorte, livre ou travado à proporção
  /// selecionada.
  ///
  /// O recorte é medido no espaço original do SVG, mas a alça é arrastada
  /// sobre a prévia já girada/espelhada — daí o [_toSourceHandleAndDelta]
  /// antes de entregar o delta ao [CropController], que cuida da sobra
  /// fracionária de um frame de gesto pro próximo. Sem acumular essa sobra,
  /// num SVG pequeno exibido bem maior que o tamanho nativo a maioria dos
  /// frames arredondaria pra zero e, de vez em quando, um frame com delta
  /// maior daria um salto de vários pixels — o "pulando de um lado pro
  /// outro" que motivou o acúmulo.
  void _resizeCropFromHandle(
    CropHandle displayHandle,
    Offset rawDisplayDelta,
    Size previewSize,
  ) {
    final crop = _settings.crop;
    if (crop == null || previewSize.width <= 0 || previewSize.height <= 0) {
      return;
    }

    final scaledDelta = Offset(
      rawDisplayDelta.dx * _displayWidth / previewSize.width,
      rawDisplayDelta.dy * _displayHeight / previewSize.height,
    );
    final (handle, sourceDelta) = _toSourceHandleAndDelta(
      displayHandle,
      scaledDelta,
    );

    // `_aspect.ratio` não é invertido para 90°/270° — um preset travado
    // (não "Personalizado") combinado com rotação ímpar pode desenhar a
    // janela um pouco fora da proporção que aparece na tela. O caso
    // relatado (arraste "pulando"/reset visual) usa sempre "Personalizado"
    // (sem proporção travada), então não esbarra nisso.
    final next = _crop.resizeBy(
      crop: crop,
      handle: handle,
      sourceDelta: sourceDelta,
      ratio: _lockedRatio,
    );
    if (next == null) return;
    _update(_settings.copyWith(crop: next));
  }

  /// Mesma conversão de espaço de [_resizeCropFromHandle], para o botão de
  /// mover a janela inteira. Mover não tem "handle" (é sempre a janela
  /// inteira), então só o delta precisa ser desfeito, sem
  /// [_toSourceHandleAndDelta] remapear identidade de canto/lado.
  void _moveCropFromHandle(Offset rawDisplayDelta, Size previewSize) {
    final crop = _settings.crop;
    if (crop == null || previewSize.width <= 0 || previewSize.height <= 0) {
      return;
    }

    var dx = rawDisplayDelta.dx * _displayWidth / previewSize.width;
    var dy = rawDisplayDelta.dy * _displayHeight / previewSize.height;
    if (_settings.flipHorizontal) dx = -dx;
    if (_settings.flipVertical) dy = -dy;
    for (var i = 0; i < _settings.rotationQuarterTurns; i++) {
      final nextDx = dy;
      final nextDy = -dx;
      dx = nextDx;
      dy = nextDy;
    }

    final next = _crop.moveBy(crop: crop, sourceDelta: Offset(dx, dy));
    if (next == null) return;
    _update(_settings.copyWith(crop: next));
  }

  String get _rotateFlipLabel {
    final parts = <String>[
      if (_settings.rotationQuarterTurns != 0)
        '${_settings.rotationQuarterTurns * 90}°',
      if (_settings.flipHorizontal) 'Espelho H',
      if (_settings.flipVertical) 'Espelho V',
    ];
    return parts.isEmpty ? 'Nenhum' : parts.join(' · ');
  }

  Widget _rotateFlipSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _update(
                  _settings.copyWith(
                    rotationQuarterTurns:
                        (_settings.rotationQuarterTurns + 3) % 4,
                  ),
                ),
                icon: const Icon(Icons.rotate_left_rounded),
                label: const Text('Girar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _update(
                  _settings.copyWith(
                    rotationQuarterTurns:
                        (_settings.rotationQuarterTurns + 1) % 4,
                  ),
                ),
                icon: const Icon(Icons.rotate_right_rounded),
                label: const Text('Girar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _flipToggleButton(
                label: 'Espelhar horizontal',
                icon: Icons.swap_horiz_rounded,
                selected: _settings.flipHorizontal,
                onTap: () => _update(
                  _settings.copyWith(flipHorizontal: !_settings.flipHorizontal),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _flipToggleButton(
                label: 'Espelhar vertical',
                icon: Icons.swap_vert_rounded,
                selected: _settings.flipVertical,
                onTap: () => _update(
                  _settings.copyWith(flipVertical: !_settings.flipVertical),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _flipToggleButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return selected
        ? FilledButton.tonalIcon(
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label),
          );
  }

  // ---------------------------------------------------------------------
  // Seção "Fundo"
  // ---------------------------------------------------------------------

  Widget _backgroundSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Fundo transparente',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Switch(
              value: _settings.transparentBackground,
              onChanged: (v) =>
                  _update(_settings.copyWith(transparentBackground: v)),
            ),
          ],
        ),
        if (!_settings.transparentBackground) ...[
          Divider(
            height: 13,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          FrameColorRow(
            label: 'Cor do fundo',
            color: _settings.backgroundColor,
            onTap: _pickBackgroundColor,
          ),
        ],
      ],
    );
  }

  void _pickBackgroundColor() => _pickColor(
    title: 'Cor do fundo',
    selectedColor: _settings.backgroundColor,
    onSelected: (color) =>
        _update(_settings.copyWith(backgroundColor: color), pushUndo: false),
  );

  /// Mesma folha de cor das outras duas telas de edição (swatches + conta-
  /// gotas na prévia atual + roda HSV completa).
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

  /// Rasteriza a prévia atual para o conta-gotas da folha de cor poder
  /// amostrar um pixel dela.
  Future<ui.Image> _renderPreviewImage() =>
      renderPreviewImage(context, _colorPreviewKey);

  // ---------------------------------------------------------------------
  // Seção "Filtro"
  // ---------------------------------------------------------------------

  Widget _filterSection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in SvgFilterType.values)
          ChoiceChip(
            label: Text(type.label),
            selected: _settings.filterType == type,
            onSelected: (_) => _update(_settings.copyWith(filterType: type)),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Cor"
  // ---------------------------------------------------------------------

  /// Mesmo painel de `EditorPage`/`PhotoFramePage`/`CollagePage` — brilho,
  /// exposição, contraste, realces, sombras, saturação, matiz e temperatura,
  /// compostos por cima do preset de [SvgFilterType] (ver
  /// [SvgEditSettings.adjustments]), não em vez dele.
  Widget _colorAdjustSection() {
    final adjustments = _settings.adjustments;
    return ColorAdjustPanel(
      hasAdjustments: adjustments.hasAdjustments,
      valueOf: (adjustment) => adjustment.valueIn(adjustments),
      onChangeStart: _pushUndoCheckpoint,
      onChanged: (adjustment, value) => _update(
        _settings.copyWith(adjustments: adjustment.applyIn(adjustments, value)),
        pushUndo: false,
      ),
      onReset: () {
        _pushUndoCheckpoint();
        _update(
          _settings.copyWith(adjustments: ColorAdjustments.neutral),
          pushUndo: false,
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Seção "Opacidade"
  // ---------------------------------------------------------------------

  Widget _opacitySection() {
    final theme = Theme.of(context);
    final percent = (_settings.opacity * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Opacidade', style: theme.textTheme.bodyMedium),
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
          min: 0,
          max: 1,
          divisions: 100,
          value: _settings.opacity,
          label: '$percent%',
          onChangeStart: (_) => _pushUndoCheckpoint(),
          onChanged: (v) =>
              _update(_settings.copyWith(opacity: v), pushUndo: false),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Salvar / compartilhar
  // ---------------------------------------------------------------------

  Future<String> _buildEditedSvg() async {
    final source = await File(widget.svg.path).readAsString();
    return renderEditedSvg(source, widget.svg, _settings);
  }

  String _suggestedFileName() {
    final base = widget.svg.path.split(Platform.pathSeparator).last;
    final withoutExt = base.toLowerCase().endsWith('.svg')
        ? base.substring(0, base.length - 4)
        : base;
    return '${withoutExt}_editado.svg';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final xml = await _buildEditedSvg();
      final uri = await FilePicker.saveFile(
        fileName: _suggestedFileName(),
        bytes: Uint8List.fromList(utf8.encode(xml)),
        mimeType: 'image/svg+xml',
        dialogTitle: 'Salvar SVG editado',
        type: FileType.custom,
        allowedExtensions: ['svg'],
      );
      if (!mounted) return;
      if (uri != null) _message('SVG salvo.');
    } on SvgEditException catch (e) {
      if (!mounted) return;
      _message(e.message);
    } catch (_) {
      if (!mounted) return;
      _message('Não foi possível salvar o SVG.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final xml = await _buildEditedSvg();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/svg_editado_${DateTime.now().millisecondsSinceEpoch}.svg',
      );
      await file.writeAsString(xml);
      await _output.share(
        file,
        mimeType: 'image/svg+xml',
        text: 'SVG editado com o app Video to GIF',
      );
    } on SvgEditException catch (e) {
      if (!mounted) return;
      _message(e.message);
    } catch (_) {
      if (!mounted) return;
      _message('Não foi possível gerar o SVG.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
