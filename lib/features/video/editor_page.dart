import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/color_adjustments.dart';
import '../../core/models/conversion_settings.dart';
import '../../core/models/frame_settings.dart';
import '../../core/models/image_frame.dart';
import '../../core/models/size_estimate.dart';
import '../../core/models/video_info.dart';
import '../../core/ffmpeg/ffmpeg_service.dart';
import '../../core/services/imported_frame_store.dart';
import '../../core/services/size_estimator.dart';
import 'converting_page.dart';
import '../../core/ui/app_bar_title.dart';
import '../../core/ui/checkerboard_background.dart';
import '../../core/ui/color_adjust_controls.dart';
import '../../core/ui/crop/crop_controller.dart';
import '../../core/ui/frame/content_fit_picker.dart';
import '../../core/ui/frame/frame_color_row.dart';
import '../../core/ui/panel_rows.dart';
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
import 'widgets/size_panel.dart';
import '../../core/ui/text_overlay_editor.dart';
import 'widgets/webp_convert_panel.dart';

const _customAspectPreset = AspectPreset('Personalizados', -1);

/// Opções apresentadas ao usuário. `fit` continua como resultado interno do
/// ajuste automático quando é preciso preservar o vídeo inteiro, mas não é
/// exibido como uma escolha duplicada na interface.
const _selectableContentFitModes = [
  ContentFitMode.auto,
  ContentFitMode.fill,
  ContentFitMode.expand,
];

/// Tela principal de edição: prévia do vídeo, corte de duração, recorte de
/// área, velocidade, resolução, FPS/cores e o painel de estimativa de
/// tamanho que leva à conversão.
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.video,
    required this.initialSettings,
  });

  final VideoInfo video;
  final ConversionSettings initialSettings;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _ffmpeg = FfmpegService();
  final _importedFrameStore = ImportedFrameStore();
  final _sectionsScrollController = ScrollController();
  final _frameStyleAnchorKey = GlobalKey();
  final _imageFrameAnchorKey = GlobalKey();
  final _previewAreaKey = GlobalKey();

  /// Ancorada no `RepaintBoundary` em volta da prévia —
  /// [_renderPreviewImage] usa isso para rasterizar exatamente o que está
  /// na tela para o conta-gotas do seletor de cor.
  final _colorPreviewKey = GlobalKey();
  List<ImageFrameAsset> _importedImageFrames = [];

  late ConversionSettings _settings = widget.initialSettings;
  late ComplexityProfile _profile = SizeEstimator.profileFromSource(
    widget.video,
  );

  VideoPlayerController? _player;
  bool _previewFailed = false;
  bool _measuring = false;
  bool _openingConversion = false;
  AspectPreset _aspect = AspectPreset.presets.first;
  bool _ditherExpanded = false;
  bool _paletteExpanded = false;
  bool _contentFitExpanded = false;

  /// Aba aberta no rodapé (índice em [_sections]); `null` fecha o painel e
  /// deixa a prévia com a tela inteira.
  int? _activeSection = 0;

  /// Histórico de desfazer/refazer das configurações, igual ao da tela de
  /// montagem: pilhas do próprio [ConversionSettings], com os gestos
  /// contínuos (sliders) empilhando um checkpoint só no começo.
  final List<ConversionSettings> _undoStack = [];
  final List<ConversionSettings> _redoStack = [];

  /// Regras de recorte compartilhadas com as telas de foto e SVG. O vídeo
  /// arredonda para par (exigência do filtro `crop` do FFmpeg) e, ao
  /// contrário das outras duas, não acumula a sobra fracionária do arrasto.
  late final _crop = CropController(
    sourceWidth: _video.width,
    sourceHeight: _video.height,
    evenOnly: true,
    accumulateDragRemainder: false,
  );

  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _widthFocus = FocusNode();
  final _heightFocus = FocusNode();

  final _textOverlay = TextOverlayController();

  VideoInfo get _video => widget.video;

  /// Estimativa de tamanho recalculada a cada mudança de configuração,
  /// usando o perfil de complexidade mais recente (medido ou aproximado).
  SizeEstimate get _estimate => SizeEstimator.estimate(
    settings: _settings,
    video: _video,
    profile: _profile,
  );

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadImportedFrames();
    _textOverlay.loadFonts();
  }

  /// Carrega as molduras de imagem importadas em sessões anteriores, para
  /// continuarem aparecendo na fileira de miniaturas.
  Future<void> _loadImportedFrames() async {
    final frames = await _importedFrameStore.loadAll();
    if (!mounted) return;
    setState(() => _importedImageFrames = frames);
  }

  /// Inicializa o player de vídeo para a prévia. Se o codec não for
  /// suportado pela plataforma, marca [_previewFailed] e deixa a conversão
  /// funcionar normalmente (que usa o FFmpeg, não este player).
  Future<void> _initPlayer() async {
    final controller = VideoPlayerController.file(File(_video.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.setPlaybackSpeed(_settings.speed);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _player = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _previewFailed = true);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _sectionsScrollController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _widthFocus.dispose();
    _heightFocus.dispose();
    _textOverlay.dispose();
    super.dispose();
  }

  /// Substitui as configurações atuais e reconstrói a tela.
  void _update(ConversionSettings next, {bool pushUndo = true}) {
    if (pushUndo) {
      _undoStack.add(_settings);
      _redoStack.clear();
    }
    setState(() => _settings = next);
  }

  /// Empilha o estado atual antes de um gesto contínuo (arrastar um slider),
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

  /// Move o player de prévia para o instante [seconds].
  Future<void> _seekPreview(double seconds) async {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    await player.seekTo(Duration(milliseconds: (seconds * 1000).round()));
  }

  /// Roda a calibração real (amostras codificadas pelo FFmpeg) e atualiza
  /// o perfil de complexidade usado nas estimativas.
  Future<void> _measure() async {
    setState(() => _measuring = true);
    try {
      final profile = await _ffmpeg.calibrate(
        video: _video,
        settings: _settings,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _measuring = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _measuring = false);
      _showMessage(
        'Não deu para medir este trecho. A estimativa aproximada continua valendo.',
      );
    }
  }

  /// Mostra uma snackbar simples, substituindo qualquer uma já visível.
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pausa a prévia e navega para a tela de conversão com as configurações
  /// atuais.
  Future<void> _convert() async {
    if (_openingConversion) return;
    setState(() => _openingConversion = true);
    await _player?.pause();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConvertingPage(
          video: _video,
          settings: _settings,
          estimate: _estimate,
        ),
      ),
    );

    if (mounted) setState(() => _openingConversion = false);
  }

  /// Todas as seções da tela como abas do rodapé, na ordem da barra — as de
  /// ajuste primeiro, depois o tamanho estimado e as de moldura. O seletor
  /// "Ajustar/Frame" que existia em cima saiu: uma barra só, que rola na
  /// horizontal, é o mesmo padrão da tela de montagem.
  List<EditorSection> _sections() {
    final isWebp = _settings.format == OutputFormat.webp;
    final (width, height) = _settings.outputDimensions(_video);
    final baseSummary =
        '$width×$height px · ${_settings.fps} FPS · '
        '${_settings.outputDurationSeconds.toStringAsFixed(1)} s';

    return [
      EditorSection.fromLabeled(_formatSection(), label: 'Formato'),
      EditorSection.fromLabeled(_durationSection(), label: 'Duração'),
      EditorSection.fromLabeled(_aspectSection(), label: 'Janela'),
      EditorSection.fromLabeled(_speedSection(), label: 'Velocidade'),
      EditorSection.fromLabeled(_fpsSection(), label: 'FPS'),
      EditorSection.fromLabeled(_resolutionSection(), label: 'Resolução'),
      if (isWebp)
        EditorSection.fromLabeled(_webpQualitySection(), label: 'Qualidade')
      else
        EditorSection.fromLabeled(_colorSection(), label: 'Cores'),
      EditorSection(
        icon: Icons.tune_rounded,
        title: 'Ajustar cor',
        label: 'Cor',
        value: _settings.adjustments.hasAdjustments ? 'Ajustada' : 'Original',
        builder: (_) => _colorAdjustSection(),
      ),
      EditorSection(
        icon: Icons.text_fields_rounded,
        title: 'Texto',
        value: _settings.frame.texts.isEmpty
            ? 'Nenhum'
            : '${_settings.frame.texts.length}',
        builder: (_) => _textSection(),
      ),
      EditorSection.fromLabeled(_frameStyleSection(), label: 'Moldura'),
      EditorSection.fromLabeled(_imageFrameSection(), label: 'Imagem'),
      EditorSection(
        icon: Icons.wallpaper_rounded,
        title: 'Fundo',
        value: _settings.frame.transparentBackground ? 'Transparente' : 'Cor',
        builder: (_) => _backgroundSection(),
      ),
      // Penúltima aba: fecha os ajustes de conteúdo com o resultado (tamanho
      // estimado), depois de todos os ajustes, formato/moldura incluídos.
      EditorSection(
        icon: Icons.data_usage_rounded,
        title: 'Estimativa de tamanho',
        label: 'Tamanho',
        value: isWebp ? null : _estimate.formatted,
        builder: (_) => isWebp
            ? WebpConvertPanel(
                summary: '$baseSummary · qualidade ${_settings.webpQuality}',
              )
            : SizePanel(
                estimate: _estimate,
                originalBytes: _video.fileSizeBytes,
                summary: '$baseSummary · ${_settings.colors} cores',
                measuring: _measuring,
                onMeasure: _measure,
              ),
      ),
      // Última aba da barra nas três telas de edição (vídeo, foto e
      // montagem) — configurações gerais, não deste vídeo em si.
      EditorSection(
        icon: Icons.settings_rounded,
        title: 'Configurações',
        label: 'Ajustes',
        builder: (_) => const PreviewSettingsPanel(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    final active = _activeSection != null && _activeSection! < sections.length
        ? _activeSection
        : null;
    // As alças de recorte só fazem sentido enquanto a pessoa está ajustando
    // a janela; em qualquer outra aba a prévia já mostra o corte aplicado
    // (ver _previewArea), como o resultado final vai sair.
    final isCropTabActive =
        active != null && sections[active].barLabel == 'Janela';
    final textTabActive =
        active != null && sections[active].barLabel == 'Texto';

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('Editar GIF'),
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
            tooltip: 'Converter em ${_settings.format.shortLabel}',
            onPressed: _openingConversion ? null : _convert,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PreviewAreaBackground(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Center(
                    child: RepaintBoundary(
                      key: _colorPreviewKey,
                      child: _previewArea(
                        showCropHandles: isCropTabActive,
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

  /// Duração da animação de tamanho da prévia ao trocar de moldura (ver
  /// [_previewArea]) — também o horizonte de tempo que
  /// [_updateFrameKeepingAnchorPosition] cobre ao reaplicar a compensação de
  /// rolagem quadro a quadro.
  static const _previewTransitionDuration = Duration(milliseconds: 220);

  /// Incrementado a cada [_updateFrameKeepingAnchorPosition], para
  /// [_correctAnchorScrollUntilSettled] saber se a cadeia de correção que
  /// está rodando ainda é a mais recente. Sem isso, tocar em várias opções
  /// de moldura em sequência rápida (antes dos ~220ms da correção anterior
  /// terminarem) deixava várias cadeias ativas ao mesmo tempo, cada uma
  /// perseguindo um alvo de rolagem diferente e brigando pela posição —
  /// visível como a tela "pulando" de forma imprevisível.
  int _frameTransitionGeneration = 0;

  /// Substitui as configurações da moldura, mantendo o resto igual.
  void _updateFrame(FrameSettings next, {bool pushUndo = true}) {
    _update(_settings.copyWith(frame: next), pushUndo: pushUndo);
  }

  /// Atualiza a moldura compensando a variação de altura da prévia. Assim o
  /// início das opções permanece na mesma posição da tela quando a troca
  /// entre moldura procedural e moldura de imagem muda a proporção do vídeo.
  ///
  /// A prévia muda de tamanho aos poucos (a [AnimatedSize] de
  /// [_previewArea]), não de uma vez — então a compensação também precisa
  /// ser reaplicada quadro a quadro enquanto ela anima, em vez de uma única
  /// vez. Uma correção única bastava quando a prévia mudava de tamanho
  /// instantaneamente, mas contra uma mudança gradual ela só corrigia o
  /// primeiro quadro (quase nenhuma diferença ainda) e deixava a rolagem
  /// desacompanhar nos quadros seguintes, terminando torta.
  void _updateFrameKeepingAnchorPosition(
    FrameSettings next, {
    required GlobalKey anchorKey,
  }) {
    final beforeBox = anchorKey.currentContext?.findRenderObject();
    final beforeY = beforeBox is RenderBox
        ? beforeBox.localToGlobal(Offset.zero).dy
        : null;

    _updateFrame(next);
    if (beforeY == null) return;

    final generation = ++_frameTransitionGeneration;
    _correctAnchorScrollUntilSettled(
      generation,
      anchorKey,
      beforeY,
      _previewTransitionDuration,
    );
  }

  /// Reaplica a compensação de rolagem a cada quadro, por [remaining] a
  /// partir de agora — cobrindo toda a animação de [_previewArea] — para que
  /// [anchorKey] termine exatamente na posição [targetY] da tela mesmo com a
  /// prévia mudando de tamanho aos poucos.
  ///
  /// [generation] é o valor de [_frameTransitionGeneration] capturado por
  /// [_updateFrameKeepingAnchorPosition] no momento do toque que iniciou
  /// esta cadeia. Se um toque mais recente já incrementou o contador, esta
  /// cadeia parou de corresponder ao estado atual da tela — encerra sem
  /// corrigir nem se reagendar, deixando a cadeia mais nova (a única com a
  /// posição "antes" certa) no controle.
  void _correctAnchorScrollUntilSettled(
    int generation,
    GlobalKey anchorKey,
    double targetY,
    Duration remaining,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _frameTransitionGeneration) return;
      if (!mounted || !_sectionsScrollController.hasClients) return;
      final afterBox = anchorKey.currentContext?.findRenderObject();
      if (afterBox is RenderBox) {
        final delta = afterBox.localToGlobal(Offset.zero).dy - targetY;
        if (delta.abs() >= 0.5) {
          final position = _sectionsScrollController.position;
          var target = (_sectionsScrollController.offset + delta)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();

          // Nunca deixa essa compensação empurrar o topo da prévia (com a
          // borda da moldura) para fora da tela só para manter o cabeçalho
          // da seção fixo — ver [_previewAreaKey]. Uma moldura bem mais alta
          // que a anterior pode exigir mais rolagem do que a prévia tem
          // altura para ceder sem desaparecer; aqui cede o cabeçalho (que
          // volta a acompanhar a prévia assim que ela terminar de crescer)
          // em vez da prévia. Só entra em ação com a prévia já visível — uma
          // rolagem manual da pessoa para longe dela continua intocada.
          final previewBox = _previewAreaKey.currentContext?.findRenderObject();
          if (previewBox is RenderBox) {
            final previewTop = previewBox.localToGlobal(Offset.zero).dy;
            if (previewTop >= 0) {
              final maxTarget = _sectionsScrollController.offset + previewTop;
              if (target > maxTarget) {
                target = maxTarget.clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                );
              }
            }
          }

          _sectionsScrollController.jumpTo(target);
        }
      }
      if (remaining > Duration.zero) {
        _correctAnchorScrollUntilSettled(
          generation,
          anchorKey,
          targetY,
          remaining - const Duration(milliseconds: 16),
        );
      }
    });
  }

  /// A prévia da aba atual. Com a aba "Janela" aberta mostra o vídeo
  /// inteiro e as alças de recorte (é lá que a janela é ajustada); em
  /// qualquer outra aba, sem moldura, mostra o vídeo já cortado — o que a
  /// pessoa vê ali é o que vai sair no GIF, não a área extra que só
  /// interessa durante o recorte em si. Com moldura, quem decide isso é
  /// [_framedPreview] (que já corta antes de encaixar no quadro escolhido).
  ///
  /// A [AnimatedSize] existe porque trocar de moldura (ou entre "Moldura" e
  /// "Moldura de imagem") quase sempre muda a proporção da prévia — cada
  /// arte de moldura tem sua própria proporção nativa. Sem ela, a mudança de
  /// altura empurrava tudo abaixo instantaneamente na mesma rolagem — e a
  /// correção de [_updateFrameKeepingAnchorPosition], que só reagia depois
  /// de pronto, aparecia como uma tremida. Com a mudança de tamanho gradual,
  /// a correção acompanha quadro a quadro e nunca precisa de um salto
  /// grande.
  Widget _previewArea({
    required bool showCropHandles,
    required bool textTabActive,
  }) {
    // Com uma barra de abas só, a prévia mostra a moldura sempre que houver
    // uma (antes isso dependia de estar na aba "Frame"), e a linha do tempo
    // fica sempre à mão — é o controle de duração.
    final hasFrame =
        _settings.frame.hasImageFrame ||
        _settings.frame.style != FrameStyle.none;
    // _framedPreview() já devolve o preview envolvido por _timelined() (é o
    // que garante a linha do tempo abaixo da moldura, não atrás dela) —
    // chamar _timelined() de novo aqui duplicava a barra "Atual Xs" quando
    // havia moldura.
    final preview = hasFrame
        ? _framedPreview(textTabActive)
        : _timelined(
            showCropHandles
                ? _preview()
                : _withTextOverlay(
                    _croppedPreview(showOutline: true),
                    textTabActive,
                  ),
          );
    return AnimatedSize(
      duration: _previewTransitionDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: preview,
    );
  }

  /// Sobrepõe as caixas de texto arrastáveis (aba "Texto") a [content] — um
  /// `Stack`/`LayoutBuilder` que mede exatamente a caixa que [content] já
  /// ocupa (a mesma proporção final do GIF/vídeo, moldura incluída, vinda de
  /// [CroppedView]/[AspectRatio] por dentro dele), para as coordenadas
  /// normalizadas de `CollageTextItem` baterem com o canvas de exportação —
  /// mesma técnica de `PhotoFramePage._framedPreview`.
  Widget _withTextOverlay(Widget content, bool textTabActive) {
    return Stack(
      children: [
        content,
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => TextOverlayStack(
              controller: _textOverlay,
              texts: _settings.frame.texts,
              onChanged: (texts) => _update(
                _settings.copyWith(
                  frame: _settings.frame.copyWith(texts: texts),
                ),
                pushUndo: false,
              ),
              canvasSize: constraints.biggest,
              interactive: textTabActive,
              onGestureStart: _pushUndoCheckpoint,
            ),
          ),
        ),
      ],
    );
  }

  /// Coloca a linha do tempo como um bloco abaixo de [preview], em vez de
  /// sobreposta por cima do vídeo — assim os gestos dela nunca invadem a
  /// área de recorte, e por ser irmã (não filha do `Stack`/`AspectRatio` do
  /// preview) ela também nunca fica atrás de uma moldura de imagem nem é
  /// reduzida para caber na janela dela.
  Widget _timelined(Widget preview) {
    final player = _player;
    if (player == null || !player.value.isInitialized) return preview;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        preview,
        const SizedBox(height: 10),
        _previewTimelineOverlay(player),
      ],
    );
  }

  /// Envolve o vídeo já cortado ([_croppedPreview]) com a moldura
  /// selecionada.
  Widget _framedPreview(bool textTabActive) {
    final frame = _settings.frame;
    final Widget framedVideo;

    if (frame.imageFrame != null) {
      framedVideo = _withTextOverlay(
        _imageFramedPreview(frame.imageFrame!),
        textTabActive,
      );
    } else if (frame.style == FrameStyle.none) {
      framedVideo = _withTextOverlay(
        _croppedPreview(showOutline: true),
        textTabActive,
      );
    } else {
      framedVideo = LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width;
          final thickness = frame.thicknessFor(width);
          final outerRadius = frame.cornerRadiusFor(width);
          final innerRadius = (outerRadius - thickness).clamp(0.0, outerRadius);

          final bordered = Container(
            color: frame.color,
            padding: EdgeInsets.all(thickness),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              child: _croppedPreview(showOutline: false),
            ),
          );

          // A moldura é sempre a forma arredondada. O que "Fundo
          // transparente" decide é o que aparece nos 4 cantos que sobram
          // fora dela: ligado, o que houver atrás; desligado, a cor de fundo
          // escolhida — os mesmos dois casos de `paintFrame`, que desenha a
          // versão exportada disso.
          final rounded = ClipRRect(
            borderRadius: BorderRadius.circular(outerRadius),
            child: bordered,
          );
          final framed = frame.transparentBackground
              ? rounded
              : ColoredBox(color: frame.backgroundColor, child: rounded);
          return _withTextOverlay(framed, textTabActive);
        },
      );
    }

    return _timelined(framedVideo);
  }

  /// Cartão escuro da linha do tempo, exibido abaixo do vídeo (e de
  /// qualquer moldura) para preservar a leitura e os gestos em todas as
  /// opções.
  Widget _previewTimelineOverlay(VideoPlayerController player) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(22)),
      child: ColoredBox(
        color: const Color(0xF0000000),
        child: _previewTimeline(player),
      ),
    );
  }

  /// Proporção do conteúdo que vai para dentro da moldura: a da janela de
  /// recorte quando há uma, senão a do vídeo inteiro. É a mesma base de
  /// [ConversionSettings.contentDimensions], que a exportação usa — sem
  /// isso a prévia e o GIF divergem sempre que há recorte.
  double get _contentAspectRatio =>
      _settings.crop?.aspectRatio ?? _video.aspectRatio;

  /// Prévia ao vivo de uma moldura de imagem: a arte (SVG das prontas do
  /// app ou importado pelo usuário, ou PNG importado no formato legado)
  /// sempre desenhada na sua proporção nativa (nunca
  /// distorcida), com o vídeo já cortado posicionado e ajustado (conforme
  /// [ContentFitMode]) exatamente dentro da janela de conteúdo
  /// ([ImageFrameAsset.contentRect]) por baixo dela, e ampliado conforme
  /// [FrameSettings.contentZoom] — o `Transform.scale` centraliza por
  /// padrão, mesmo alinhamento do `crop` que a exportação usa para o zoom
  /// (ver [FfmpegService._imageFramedGraph]), então prévia e GIF final nunca
  /// divergem.
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
            _settings.frame.contentFit,
            _contentAspectRatio,
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
    if (_settings.frame.transparentBackground) return preview;
    return ColoredBox(color: _settings.frame.backgroundColor, child: preview);
  }

  /// Conteúdo dentro da janela de uma moldura de imagem. Em "Expandir sem
  /// cortar", a área que não é ocupada pelo vídeo permanece preta, enquanto
  /// o zoom atua apenas sobre o vídeo nítido central — a mesma composição
  /// usada pelo FFmpeg na exportação.
  Widget _imageFrameContentPreview(ContentFitMode fit) {
    Widget video(BoxFit boxFit) => FittedBox(
      fit: boxFit,
      child: SizedBox(
        width: 1000,
        height: 1000 / _contentAspectRatio,
        child: _croppedPreview(showOutline: false),
      ),
    );

    if (fit != ContentFitMode.expand) {
      return ColoredBox(
        color: Colors.black,
        child: ClipRect(
          child: video(
            fit == ContentFitMode.fill ? BoxFit.cover : BoxFit.contain,
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: Transform.scale(
          scale: _settings.frame.effectiveContentZoom,
          child: video(BoxFit.contain),
        ),
      ),
    );
  }

  /// O estilo procedural que a fileira de "Moldura" deve marcar. Com uma
  /// moldura de imagem ativa é sempre "Sem moldura": as duas famílias são
  /// mutuamente exclusivas, então escolher uma tem que deixar a outra
  /// visivelmente desativada (ver [_selectFrameStyle]/[_selectImageFrame]).
  FrameStyle get _activeFrameStyle => _settings.frame.imageFrame == null
      ? _settings.frame.style
      : FrameStyle.none;

  /// Seção "Moldura": as opções procedurais e, quando uma delas está ativa,
  /// os controles de cor, espessura da borda e arredondamento dos cantos.
  LabeledSection _frameStyleSection() {
    final theme = Theme.of(context);
    final style = _activeFrameStyle;

    return LabeledSection(
      icon: Icons.smartphone_rounded,
      title: 'Moldura',
      value: style.label,
      hint: 'Escolha uma opção',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FrameStylePicker(
            active: _settings.frame.style,
            onSelected: _selectFrameStyle,
          ),
          if (style != FrameStyle.none) ...[
            const SizedBox(height: 18),
            SectionCard(
              children: [
                PanelColorRow(
                  label: 'Cor da moldura',
                  color: _settings.frame.color,
                  onTap: _pickFrameColor,
                ),
                Divider(
                  height: 13,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
                FrameThicknessRow(
                  frame: _settings.frame,
                  onChangeStart: _pushUndoCheckpoint,
                  onChanged: (next) => _updateFrame(next, pushUndo: false),
                ),
                Divider(
                  height: 13,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
                CornerRadiusRow(
                  frame: _settings.frame,
                  onChangeStart: _pushUndoCheckpoint,
                  onChanged: (next) => _updateFrame(next, pushUndo: false),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Seção "Moldura de imagem": as artes prontas do app, as importadas pelo
  /// usuário e o botão de importar. Fica numa caixa própria porque é a outra
  /// família de moldura — escolher aqui desativa a de cima, e vice-versa.
  ///
  /// Com uma arte selecionada ([FrameSettings.hasFixedAspect]), aparecem
  /// abaixo das miniaturas dois cards independentes: "Ajuste do conteúdo"
  /// (como o vídeo se encaixa na moldura) e "Resolução da moldura" (o
  /// tamanho/qualidade do arquivo final). São perguntas diferentes, então
  /// cada uma tem seu próprio card e a segunda nunca depende de a primeira
  /// estar expandida.
  LabeledSection _imageFrameSection() {
    final hasFixedAspect = _settings.frame.hasFixedAspect;
    return LabeledSection(
      icon: Icons.image_outlined,
      title: 'Moldura de imagem',
      value: _settings.frame.imageFrame?.label ?? FrameStyle.none.label,
      hint: 'Escolha uma opção',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImageFramePicker(
            selected: _settings.frame.imageFrame,
            imported: _importedImageFrames,
            onSelected: _selectImageFrame,
            onClear: () =>
                _updateFrame(_settings.frame.copyWith(clearImageFrame: true)),
            onImport: _importFrameImage,
            onRemoveImported: _confirmRemoveImportedFrame,
          ),
          if (hasFixedAspect) ...[
            const SizedBox(height: 18),
            SectionCard(children: [_contentFitSubsection()]),
            const SizedBox(height: 18),
            SectionCard(children: [_frameResolutionSelector()]),
          ],
        ],
      ),
    );
  }

  /// Seção "Fundo transparente": vale para as duas famílias de moldura.
  /// Fica sempre visível para o estado do GIF não depender de qual caixa
  /// está aberta.
  /// Ajuste de cor do vídeo: mesmo painel das outras duas telas, gravando em
  /// [ConversionSettings.adjustments]. Vale só para o conteúdo — a moldura e
  /// o fundo entram depois na cadeia de filtros e não passam pelo ajuste.
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

  Widget _textSection() {
    _textOverlay.dropSelectionIfGone(_settings.frame.texts);
    return TextOverlayPanel(
      controller: _textOverlay,
      texts: _settings.frame.texts,
      onChanged: (texts) => _update(
        _settings.copyWith(frame: _settings.frame.copyWith(texts: texts)),
      ),
      previewImageBuilder: _renderPreviewImage,
      onGestureStart: _pushUndoCheckpoint,
    );
  }

  Widget _backgroundSection() {
    final frame = _settings.frame;
    return Padding(
      // Mesma folga inferior dos Cards de [LabeledSection], já que aqui a
      // caixa é um item da lista, não o conteúdo de uma seção.
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(
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
            PanelColorRow(
              key: const ValueKey('backgroundColorRow'),
              label: 'Cor do fundo',
              color: _settings.frame.backgroundColor,
              onTap: _pickBackgroundColor,
            ),
          ],
        ],
      ),
    );
  }

  void _selectFrameStyle(FrameStyle style) {
    _updateFrameKeepingAnchorPosition(
      frameWithStyle(_settings.frame, style),
      anchorKey: _frameStyleAnchorKey,
    );
  }

  /// Seleciona uma moldura de imagem, sempre limpando o estilo procedural
  /// (as duas são mutuamente exclusivas).
  void _selectImageFrame(ImageFrameAsset asset) {
    _updateFrameKeepingAnchorPosition(
      _settings.frame.copyWith(style: FrameStyle.none, imageFrame: asset),
      anchorKey: _imageFrameAnchorKey,
    );
  }

  /// Abre o seletor de arquivos para importar um SVG de moldura próprio
  /// (mesmo formato das prontas, com uma janela transparente real), e o
  /// seleciona em caso de sucesso.
  Future<void> _importFrameImage() async {
    try {
      final asset = await _importedFrameStore.importFrame();
      if (!mounted) return;
      setState(() => _importedImageFrames = [..._importedImageFrames, asset]);
      _selectImageFrame(asset);
    } on ImportedFrameException catch (e) {
      _showMessage(e.message);
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
      if (_settings.frame.imageFrame?.id == asset.id) {
        _updateFrame(_settings.frame.copyWith(clearImageFrame: true));
      }
    });
  }

  void _pickFrameColor() => _pickColor(
    title: 'Cor da moldura',
    selectedColor: _settings.frame.color,
    onSelected: (color) =>
        _updateFrame(_settings.frame.copyWith(color: color), pushUndo: false),
  );

  void _pickBackgroundColor() => _pickColor(
    title: 'Cor do fundo',
    selectedColor: _settings.frame.backgroundColor,
    onSelected: (color) => _updateFrame(
      _settings.frame.copyWith(backgroundColor: color),
      pushUndo: false,
    ),
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

  /// Rasteriza exatamente o que está desenhado na prévia para o conta-gotas
  /// da folha de cor poder amostrar um pixel dela.
  Future<ui.Image> _renderPreviewImage() =>
      renderPreviewImage(context, _colorPreviewKey);

  /// Subseção recolhível "Ajuste do conteúdo", aninhada dentro de
  /// "Moldura de imagem": como o vídeo se encaixa quando a proporção da
  /// moldura escolhida é diferente da do recorte, mais o quanto ele é
  /// ampliado dentro dela. Mesmo padrão de [_collapsibleSubsection] usado
  /// por "Suavização de cor"/"Paleta" em [_colorSection].
  Widget _contentFitSubsection() {
    final selected = _settings.frame.contentFit;
    return _collapsibleSubsection(
      label: 'Ajuste do conteúdo',
      expanded: _contentFitExpanded,
      onToggle: () =>
          setState(() => _contentFitExpanded = !_contentFitExpanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final mode in _selectableContentFitModes) ...[
            ContentFitTile(
              mode: mode,
              selected: mode == selected,
              onSelected: (m) =>
                  _updateFrame(_settings.frame.copyWith(contentFit: m)),
              zoomRow: ContentZoomRow(
                frame: _settings.frame,
                onChangeStart: _pushUndoCheckpoint,
                onChanged: (next) => _updateFrame(next, pushUndo: false),
              ),
            ),
            if (mode != _selectableContentFitModes.last)
              const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// Card próprio de "Resolução da moldura": o tamanho/qualidade do GIF
  /// final, independente de "Ajuste do conteúdo" (como o vídeo se encaixa
  /// na moldura) — por isso sempre visível, não atrelada ao estado
  /// recolhido/expandido daquele outro card.
  Widget _frameResolutionSelector() {
    final theme = Theme.of(context);
    final selected = _settings.frame.frameResolutionMode;
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
                  'Ajustar',
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
              _settings.frame.copyWith(frameResolutionMode: selection.single),
            ),
          ),
        ],
      ),
    );
  }

  /// Prévia da aba "Ajustar": o vídeo inteiro com o overlay de recorte
  /// arrastável. A linha do tempo é adicionada depois, por [_timelined],
  /// para permanecer sempre visível.
  Widget _preview() {
    final theme = Theme.of(context);
    final player = _player;

    if (_previewFailed) {
      return Container(
        constraints: const BoxConstraints(minHeight: 180),
        decoration: const BoxDecoration(color: Colors.black),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, color: theme.colorScheme.primary),
            const SizedBox(height: 10),
            const Text('Prévia indisponível para este codec'),
            const SizedBox(height: 4),
            Text(
              'A conversão continua funcionando normalmente.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (player == null || !player.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _video.aspectRatio,
        child: Container(
          decoration: const BoxDecoration(color: Colors.black),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: player.value.aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(player),
            _playPauseOverlay(player),
            CropOverlay(
              bounds: Size(_video.width.toDouble(), _video.height.toDouble()),
              crop: _settings.crop,
              onResize: _resizeCropFromHandle,
              onMove: _moveCropFromHandle,
              freeform: _aspect == _customAspectPreset,
            ),
          ],
        ),
      ),
    );
  }

  /// Prévia da aba "Frame": só a janela de recorte, sem véu e sem alças —
  /// o enquadramento que vai sair no GIF, sempre com cantos retos (nunca
  /// arredondados por padrão). [showOutline] desenha a borda cinza fina só
  /// quando não há moldura em volta; dentro de uma moldura, quem desenha a
  /// borda (e arredonda o conteúdo, se for o caso) é a própria moldura.
  Widget _croppedPreview({required bool showOutline}) {
    final player = _player;
    if (_previewFailed || player == null || !player.value.isInitialized) {
      return _preview();
    }

    final adjustments = _settings.adjustments;
    Widget video = VideoPlayer(player);
    if (adjustments.hasAdjustments) {
      // O mesmo filtro que o FFmpeg reproduz na exportação (ver
      // `FfmpegService.colorAdjustFilters`), para a prévia mostrar o
      // resultado antes de converter.
      video = ColorFiltered(colorFilter: adjustments.filter, child: video);
    }
    final content = CroppedView(
      sourceWidth: _video.width,
      sourceHeight: _video.height,
      crop: _settings.crop,
      child: video,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: showOutline
            ? Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.45),
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [content, _playPauseOverlay(player)]),
    );
  }

  /// Botão central de play/pause, compartilhado pelas duas prévias. Voltar
  /// para o início do trecho quando a posição atual está fora dele evita
  /// dar play num pedaço que não vai para o GIF.
  Widget _playPauseOverlay(VideoPlayerController player) {
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (player.value.isPlaying) {
              await player.pause();
            } else {
              final position = player.value.position.inMilliseconds / 1000;
              if (position < _settings.startSeconds ||
                  position >= _settings.endSeconds) {
                await _seekPreview(_settings.startSeconds);
              }
              await player.play();
            }
            if (mounted) setState(() {});
          },
          child: Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0x99000000),
                shape: BoxShape.circle,
              ),
              child: Icon(
                player.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Converte o arraste de uma alça (em pixels da prévia exibida) para
  /// pixels do vídeo e recalcula o recorte, livre ou travado à proporção
  /// selecionada.
  void _resizeCropFromHandle(
    CropHandle handle,
    Offset displayDelta,
    Size previewSize,
  ) {
    final crop = _settings.crop;
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
    _update(_settings.copyWith(crop: next));
  }

  /// Converte o arraste do botão de mover (em pixels da prévia exibida)
  /// para pixels do vídeo e desloca a janela de recorte, sem sair da área
  /// do vídeo.
  void _moveCropFromHandle(Offset displayDelta, Size previewSize) {
    final crop = _settings.crop;
    if (crop == null || previewSize.width <= 0 || previewSize.height <= 0) {
      return;
    }

    final next = _crop.moveBy(
      crop: crop,
      sourceDelta: _toSourceDelta(displayDelta, previewSize),
    );
    if (next == null) return;
    _update(_settings.copyWith(crop: next));
  }

  /// Converte um arraste em pixels da prévia exibida para pixels do vídeo.
  Offset _toSourceDelta(Offset displayDelta, Size previewSize) => Offset(
    displayDelta.dx * _video.width / previewSize.width,
    displayDelta.dy * _video.height / previewSize.height,
  );

  /// Barra de progresso do vídeo com o trecho selecionado destacado; toca
  /// em qualquer ponto para pular a prévia para lá, e volta ao início do
  /// trecho automaticamente quando a reprodução passa do fim selecionado.
  Widget _previewTimeline(VideoPlayerController player) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final duration = _video.durationSeconds <= 0
            ? 1.0
            : _video.durationSeconds;
        final current = player.value.position.inMilliseconds / 1000.0;
        final start = (_settings.startSeconds / duration).clamp(0.0, 1.0);
        final end = (_settings.endSeconds / duration).clamp(0.0, 1.0);
        final position = (current / duration).clamp(0.0, 1.0);

        if (player.value.isPlaying && current >= _settings.endSeconds) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await player.seekTo(
              Duration(milliseconds: (_settings.startSeconds * 1000).round()),
            );
          });
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      final ratio = (details.localPosition.dx / width).clamp(
                        0.0,
                        1.0,
                      );
                      _seekPreview(ratio * duration);
                    },
                    child: SizedBox(
                      height: 24,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          Positioned(
                            left: width * start,
                            width: width * (end - start),
                            child: Container(
                              height: 7,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (width - 3) * position,
                            child: Container(
                              width: 3,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (width - 2) * start,
                            child: Container(
                              width: 2,
                              height: 18,
                              color: Colors.white70,
                            ),
                          ),
                          Positioned(
                            left: (width - 2) * end,
                            child: Container(
                              width: 2,
                              height: 18,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatSeconds(_settings.startSeconds),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'Atual ${_formatSeconds(current.clamp(0, duration).toDouble())}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  Text(
                    _formatSeconds(_settings.endSeconds),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Seção com o slider de intervalo (início/fim) do trecho a converter.
  LabeledSection _durationSection() {
    final start = _settings.startSeconds;
    final end = _settings.endSeconds;

    return LabeledSection(
      icon: Icons.content_cut_rounded,
      title: 'Duração',
      value: '${_settings.sourceDurationSeconds.toStringAsFixed(1)} s',
      originalValue: '${_video.durationSeconds.toStringAsFixed(1)} s',
      child: Column(
        children: [
          RangeSlider(
            min: 0,
            max: _video.durationSeconds,
            divisions: (_video.durationSeconds * 10).round().clamp(1, 2000),
            values: RangeValues(start, end),
            labels: RangeLabels(_formatSeconds(start), _formatSeconds(end)),
            onChangeStart: (_) => _pushUndoCheckpoint(),
            onChanged: (values) {
              if (values.end - values.start < 0.2) return;
              _update(
                _settings.copyWith(
                  startSeconds: values.start,
                  endSeconds: values.end,
                ),
                pushUndo: false,
              );
            },
            onChangeEnd: (values) => _seekPreview(values.start),
          ),
          const SizedBox(height: 4),
          _metricRow('Início', _formatSeconds(start)),
          _metricRow('Fim', _formatSeconds(end)),
          _metricRow(
            'Duração total',
            '${_settings.sourceDurationSeconds.toStringAsFixed(1)} s',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _update(
                  _settings.copyWith(
                    startSeconds: widget.initialSettings.startSeconds,
                    endSeconds: widget.initialSettings.endSeconds,
                  ),
                );
                _seekPreview(widget.initialSettings.startSeconds);
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Redefinir'),
            ),
          ),
        ],
      ),
    );
  }

  /// Seção de formato/recorte: presets de proporção e, quando há recorte
  /// ativo, os campos numéricos da janela.
  LabeledSection _aspectSection() {
    final crop = _settings.crop;
    final visiblePresets = <AspectPreset>[
      ...AspectPreset.presets,
      _customAspectPreset,
    ];

    return LabeledSection(
      icon: Icons.crop_rounded,
      title: 'Formato da janela',
      value: _aspect.ratio == null
          ? '${_video.width}×${_video.height}'
          : _aspect.label,
      originalValue: _ratioLabel(_video.width, _video.height),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionChips<AspectPreset>(
            options: visiblePresets,
            selected: visiblePresets.contains(_aspect)
                ? _aspect
                : visiblePresets.first,
            // Só a numeração da proporção quando ela existe (o rótulo já
            // é isso) — o texto por extenso ("Quadrado", "Retrato"...)
            // deixava os chips mais largos do que precisava.
            labelBuilder: (preset) => preset.label,
            onSelected: _selectAspectPreset,
          ),
          if (crop != null) ...[
            const SizedBox(height: 18),
            if (_aspect == _customAspectPreset) ...[
              CropSizeSummary(crop: crop, showPixelUnit: true),
              const SizedBox(height: 12),
              CropSizeInputs(
                crop: crop,
                widthController: _widthController,
                heightController: _heightController,
                widthFocus: _widthFocus,
                heightFocus: _heightFocus,
                onSubmitWidth: _applyCropWidth,
                onSubmitHeight: _applyCropHeight,
                showPixelUnit: true,
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
      ),
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

  /// Proporção travada pelo preset atual, ou `null` em "Personalizados".
  double? get _lockedRatio =>
      _aspect == _customAspectPreset ? null : _aspect.ratio;

  /// Interpreta o texto digitado no campo de largura e aplica, se válido.
  /// Avisa quando o valor é ajustado por passar dos limites do vídeo.
  void _applyCropWidth(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > _video.width) {
      _showMessage(
        'Largura máxima é ${_video.width}px (tamanho do vídeo original).',
      );
    } else if (parsed < 2) {
      _showMessage('A largura mínima é 2px.');
    }
    final crop = _settings.crop;
    if (crop == null) return;
    _update(
      _settings.copyWith(
        crop: _crop.withWidth(parsed, crop: crop, ratio: _lockedRatio),
      ),
    );
  }

  /// Interpreta o texto digitado no campo de altura e aplica, se válido.
  /// Avisa quando o valor é ajustado por passar dos limites do vídeo.
  void _applyCropHeight(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    if (parsed > _video.height) {
      _showMessage(
        'Altura máxima é ${_video.height}px (tamanho do vídeo original).',
      );
    } else if (parsed < 2) {
      _showMessage('A altura mínima é 2px.');
    }
    final crop = _settings.crop;
    if (crop == null) return;
    _update(
      _settings.copyWith(
        crop: _crop.withHeight(parsed, crop: crop, ratio: _lockedRatio),
      ),
    );
  }

  /// Recentraliza o recorte no tamanho padrão do preset atual.
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

  /// Seção de velocidade de reprodução do GIF.
  LabeledSection _speedSection() {
    const min = ConversionSettings.minSpeed;
    const max = ConversionSettings.maxSpeed;
    final speed = _settings.speed.clamp(min, max).toDouble();

    return LabeledSection(
      icon: Icons.speed_rounded,
      title: 'Velocidade',
      value: '${_formatSpeed(_settings.speed)}x',
      originalValue: '${_formatSpeed(1.0)}x',
      child: Column(
        children: [
          Slider(
            min: min,
            max: max,
            divisions: ((max - min) / 0.05).round(),
            value: speed,
            label: '${_formatSpeed(speed)}x',
            onChangeStart: (_) => _pushUndoCheckpoint(),
            onChanged: (value) {
              _update(_settings.copyWith(speed: value), pushUndo: false);
              _player?.setPlaybackSpeed(value);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatSpeed(min)}x',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${_formatSpeed(max)}x',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Seção de resolução: larguras maiores que o vídeo original ficam
  /// desabilitadas, para não deixar o usuário tentar ampliar a imagem.
  /// Slider de "Resolução": 100% mantém o tamanho original do vídeo — o
  /// padrão desde que a tela abre — e arrastar para a esquerda reduz.
  /// Antes eram chips de larguras fixas (160, 240, 320...px), começando já
  /// numa sugestão menor que o original; agora o ponto de partida é sempre
  /// a resolução cheia, e reduzir é uma escolha explícita.
  LabeledSection _resolutionSection() {
    final percent = ConversionSettings.percentForWidth(
      _video,
      _settings.targetWidth,
    );
    final (width, height) = _settings.contentDimensions(_video);

    return LabeledSection(
      icon: Icons.photo_size_select_large_rounded,
      title: 'Resolução',
      value: '$percent% · $width×$height',
      originalValue: '${_video.width}×${_video.height}',
      tip:
          '100% preserva a nitidez original; reduzir gera arquivos mais '
          'leves, mas com menos detalhe.',
      child: Slider(
        min: ConversionSettings.minResolutionPercent.toDouble(),
        max: 100,
        divisions: 100 - ConversionSettings.minResolutionPercent,
        value: percent.toDouble(),
        // O balão que segue o dedo já mostra o tamanho em pixels, não só a
        // porcentagem — não precisa soltar o slider para ver o resultado.
        label: '$percent% · $width×$height',
        onChangeStart: (_) => _pushUndoCheckpoint(),
        onChanged: (value) {
          final (newWidth, _) = ConversionSettings.dimensionsForPercent(
            _video,
            value.round(),
          );
          _update(_settings.copyWith(targetWidth: newWidth), pushUndo: false);
        },
      ),
    );
  }

  /// Seção de quadros por segundo do GIF.
  LabeledSection _fpsSection() {
    return LabeledSection(
      icon: Icons.animation_rounded,
      title: 'Quadros por segundo (FPS)',
      value: '${_settings.fps} FPS',
      originalValue: '${_video.frameRate.round()} FPS',
      hint:
          'Mais FPS deixa a animação mais fluida, mas aumenta o tamanho do arquivo.',
      tip: '12 FPS é um bom equilíbrio entre fluidez e tamanho.',
      child: OptionChips<int>(
        options: ConversionSettings.fpsOptions,
        selected: _settings.fps,
        labelBuilder: (fps) => '$fps FPS',
        isEnabled: (fps) => fps <= _video.frameRate.round(),
        onSelected: (fps) => _update(_settings.copyWith(fps: fps)),
      ),
    );
  }

  /// Seção de formato de saída — GIF ou WebP animado. Vem primeiro entre as
  /// seções de "Ajustar" porque muda qual seção de qualidade aparece logo
  /// abaixo ([_colorSection] ou [_webpQualitySection]) e se a estimativa de
  /// tamanho calibrada é mostrada ([SizePanel] ou [WebpConvertPanel]).
  LabeledSection _formatSection() {
    return LabeledSection(
      icon: Icons.image_outlined,
      title: 'Formato de saída',
      value: _settings.format.label,
      hint:
          'GIF é compatível com quase tudo; WebP costuma gerar arquivos bem '
          'menores com qualidade parecida, mas alguns apps mais antigos não '
          'abrem.',
      child: OptionChips<OutputFormat>(
        options: OutputFormat.values,
        selected: _settings.format,
        labelBuilder: (f) => f.label,
        onSelected: (f) => _update(_settings.copyWith(format: f)),
      ),
    );
  }

  /// Seção de qualidade do WebP: equivalente a [_colorSection], mas o
  /// `libwebp` não usa paleta nem dither — só o parâmetro `-quality`, então
  /// aqui sobra apenas o controle de qualidade e o loop (que continua
  /// valendo igual para os dois formatos).
  LabeledSection _webpQualitySection() {
    final options = <int>{
      ...ConversionSettings.webpQualityOptions,
      _settings.webpQuality,
    }.toList()..sort();

    return LabeledSection(
      icon: Icons.high_quality_outlined,
      title: 'Qualidade do WebP',
      value: '${_settings.webpQuality}',
      tip:
          '75 costuma equilibrar bem qualidade e tamanho; 95 preserva mais detalhe.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionChips<int>(
            options: options,
            selected: _settings.webpQuality,
            labelBuilder: (value) => '$value',
            onSelected: (value) =>
                _update(_settings.copyWith(webpQuality: value)),
          ),
          const SizedBox(height: 12),
          SectionCard(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repetir para sempre'),
                subtitle: const Text('Desligue para o WebP tocar uma vez só'),
                value: _settings.loop,
                onChanged: (v) => _update(_settings.copyWith(loop: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Seção de qualidade de cor: quantidade de cores, modo de dither, modo
  /// de paleta e se o GIF deve repetir em loop.
  LabeledSection _colorSection() {
    final theme = Theme.of(context);
    final colors = <int>{
      ...ConversionSettings.primaryColorOptions,
      _settings.colors,
    }.toList()..sort();

    return LabeledSection(
      icon: Icons.palette_outlined,
      title: 'Qualidade das cores',
      value: '${_settings.colors} cores',
      originalValue: 'Cores ilimitadas',
      tip:
          '128 cores costuma equilibrar bem qualidade e tamanho; 256 preserva mais detalhes.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionChips<int>(
            options: colors,
            selected: _settings.colors,
            labelBuilder: (value) => switch (value) {
              64 => '64 cores — Menor tamanho',
              128 => '128 cores — Equilibrado',
              256 => '256 cores — Melhor qualidade',
              _ => '$value cores',
            },
            onSelected: (value) => _update(_settings.copyWith(colors: value)),
          ),
          const SizedBox(height: 12),
          SectionCard(
            children: [
              _collapsibleSubsection(
                label: 'Suavização de cor',
                subtitle: _settings.dither.label,
                expanded: _ditherExpanded,
                onToggle: () =>
                    setState(() => _ditherExpanded = !_ditherExpanded),
                child: OptionChips<DitherMode>(
                  options: DitherMode.values,
                  selected: _settings.dither,
                  labelBuilder: (d) => d.label,
                  onSelected: (d) => _update(_settings.copyWith(dither: d)),
                ),
              ),
              Divider(
                height: 13,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              _collapsibleSubsection(
                label: 'Paleta',
                subtitle: _settings.palette.label,
                expanded: _paletteExpanded,
                onToggle: () =>
                    setState(() => _paletteExpanded = !_paletteExpanded),
                child: OptionChips<PaletteMode>(
                  options: PaletteMode.values,
                  selected: _settings.palette,
                  labelBuilder: (p) => p.label,
                  onSelected: (p) => _update(_settings.copyWith(palette: p)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repetir para sempre'),
                subtitle: const Text('Desligue para o GIF tocar uma vez só'),
                value: _settings.loop,
                onChanged: (v) => _update(_settings.copyWith(loop: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Agrupa subseções relacionadas em um card levemente destacado do fundo,
  /// como em "Suavização de cor" + "Paleta", "Repetir para sempre" e "Fundo
  /// transparente".
  ///
  /// É um [Material], não um [Container] com `BoxDecoration`: os
  /// [SwitchListTile] que moram aqui dentro pintam fundo e ondulação de
  /// toque no [Material] mais próximo, e uma caixa decorada no meio do
  /// caminho esconderia esses efeitos (o framework chega a avisar disso em
  /// tempo de execução).

  /// Linha "rótulo à esquerda, valor à direita" usada nos resumos de seção.
  Widget _metricRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Cabeçalho recolhível de uma subseção (usado em "Suavização de cor" e
  /// "Paleta", dentro de "Qualidade das cores"): toca no rótulo para
  /// mostrar ou esconder o conteúdo abaixo, que começa recolhido. O
  /// [subtitle] mostra a opção selecionada mesmo com a subseção fechada.
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

  /// Formata segundos como "Ns" ou "Mm Ns" quando passa de um minuto.
  static String _formatSeconds(double seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds - minutes * 60;
    return minutes > 0
        ? '${minutes}m ${rest.toStringAsFixed(1)}s'
        : '${rest.toStringAsFixed(1)}s';
  }

  /// Formata a velocidade com no máximo duas casas decimais, sem zeros
  /// desnecessários (1 em vez de 1.00, 1.5 em vez de 1.50). Arredondar antes
  /// de formatar evita artefatos de ponto flutuante vindos dos passos do
  /// slider (ex.: 1.9500000000000002).
  static String _formatSpeed(double speed) {
    final rounded = (speed * 100).round() / 100;
    if (rounded == rounded.roundToDouble()) return '${rounded.round()}';
    var text = rounded.toStringAsFixed(2);
    if (text.endsWith('0')) text = text.substring(0, text.length - 1);
    return text;
  }

  /// Reduz "largura×altura" para a proporção "W:H" mais simples (ex.:
  /// 1920×1080 → 16:9), usado para mostrar o formato original do vídeo.
  static String _ratioLabel(int width, int height) {
    if (width <= 0 || height <= 0) return '$width×$height';
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final g = gcd(width, height);
    return '${width ~/ g}:${height ~/ g}';
  }
}
