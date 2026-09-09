import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';

import '../models/collage_color_adjustment.dart';
import '../models/color_adjustments.dart';
import '../models/conversion_settings.dart';
import '../models/frame_settings.dart';
import '../models/image_frame.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import '../services/imported_frame_store.dart';
import '../services/size_estimator.dart';
import 'converting_page.dart';
import 'widgets/color_adjust_controls.dart';
import 'widgets/color_picker_sheet.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/cropped_view.dart';
import 'widgets/editor_tabs_footer.dart';
import 'widgets/frame_painter.dart';
import 'widgets/labeled_section.dart';
import 'widgets/size_panel.dart';
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

  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _widthFocus = FocusNode();
  final _heightFocus = FocusNode();

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
      EditorSection.fromLabeled(_resolutionSection(), label: 'Resolução'),
      EditorSection.fromLabeled(_fpsSection(), label: 'FPS'),
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
      EditorSection.fromLabeled(_frameStyleSection(), label: 'Moldura'),
      EditorSection.fromLabeled(_imageFrameSection(), label: 'Imagem'),
      EditorSection(
        icon: Icons.wallpaper_rounded,
        title: 'Fundo',
        value: _settings.frame.transparentBackground ? 'Transparente' : 'Cor',
        builder: (_) => _backgroundSection(),
      ),
      // Última aba da barra: fecha a edição com o resultado (tamanho
      // estimado) depois de todos os ajustes, formato/moldura incluídos.
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar GIF'),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Center(
                  child: RepaintBoundary(
                    key: _colorPreviewKey,
                    child: _previewArea(showCropHandles: isCropTabActive),
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
  Widget _previewArea({required bool showCropHandles}) {
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
        ? _framedPreview()
        : _timelined(
            showCropHandles ? _preview() : _croppedPreview(rounded: true),
          );
    return AnimatedSize(
      duration: _previewTransitionDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: preview,
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
  Widget _framedPreview() {
    final frame = _settings.frame;
    final Widget framedVideo;

    if (frame.imageFrame != null) {
      framedVideo = _imageFramedPreview(frame.imageFrame!);
    } else if (frame.style == FrameStyle.none) {
      framedVideo = _croppedPreview(rounded: true);
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
              child: _croppedPreview(rounded: false),
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
          if (frame.transparentBackground) return rounded;
          return ColoredBox(color: frame.backgroundColor, child: rounded);
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
                  child: _imageFrameArtwork(asset, fit: BoxFit.fill),
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
        child: _croppedPreview(rounded: false),
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

  Widget _backgroundSection() {
    final frame = _settings.frame;
    return Padding(
      // Mesma folga inferior dos Cards de [LabeledSection], já que aqui a
      // caixa é um item da lista, não o conteúdo de uma seção.
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

  /// Linha horizontal com uma miniatura por [FrameStyle], cada uma já
  /// desenhada com o [FramePainter] real do estilo — a miniatura é a
  /// prévia, não um ícone genérico. A marcação segue [_activeFrameStyle],
  /// então com uma moldura de imagem ativa quem fica marcada aqui é "Sem
  /// moldura".
  Widget _frameStyleThumbnails() {
    final active = _activeFrameStyle;
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

  /// A casca visual de todas as miniaturas de moldura: quadrado de 62px com
  /// borda, o selo de check quando marcada e o rótulo embaixo. Só o miolo
  /// ([child]) muda entre as fileiras — sem isto, as três variações
  /// (estilo procedural, "Sem moldura" da fileira de imagem, arte de
  /// imagem) seriam o mesmo layout copiado três vezes.
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

  /// Miniatura de um [FrameStyle]: para "Sem moldura", um ícone simples;
  /// para os demais, o [FramePainter] real do estilo (mesmos padrões de
  /// canto/espessura, fundo transparente para os cantos ficarem visíveis)
  /// com uma "tela" escura desenhada por cima da janela de conteúdo — sem
  /// ela, estilos com espessura pequena (ex. "Bordas finas") ou canto pouco
  /// arredondado (ex. "Celular Clássico") ficam indistinguíveis de um
  /// bloco sólido, já que não há vídeo por baixo nesta miniatura.
  ///
  /// A margem da "tela" é fixa (proporção do tamanho da própria miniatura),
  /// não a espessura real do estilo: a espessura real é calibrada para o
  /// canvas de exportação (centenas de pixels) e, escalada para os ~40px
  /// desta miniatura, ficaria sub-pixel — a moldura pareceria um bloco
  /// sólido de novo, exatamente o problema que essa margem resolve.
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

  /// Aplica o estilo de moldura escolhido, adotando os padrões de
  /// espessura e arredondamento sugeridos por ele (o usuário ainda pode
  /// ajustar cada um nos sliders depois). Cor, ajuste de conteúdo e fundo
  /// transparente são mantidos. Sempre limpa a moldura de imagem
  /// selecionada, já que as duas famílias são mutuamente exclusivas.
  void _selectFrameStyle(FrameStyle style) {
    final current = _settings.frame;
    _updateFrameKeepingAnchorPosition(
      current.copyWith(
        style: style,
        cornerRatio: style.defaultCornerRatio,
        thicknessAtReference: style.defaultThickness,
        clearImageFrame: true,
      ),
      anchorKey: _frameStyleAnchorKey,
    );
  }

  /// Fileira horizontal com "Sem moldura", as molduras de imagem prontas do
  /// app ([ImageFrameLibrary.bundled]), as importadas pelo usuário, e um
  /// botão "+" para importar mais.
  ///
  /// "Sem moldura" na frente é o par da miniatura de mesmo nome na fileira
  /// procedural: cada fileira mostra sempre exatamente uma opção marcada, e
  /// é assim que dá para ver que escolher de um lado desativou o outro.
  Widget _imageFrameThumbnails() {
    final selected = _settings.frame.imageFrame;
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

  /// Miniatura "Sem moldura" da fileira de molduras de imagem: desmarca a
  /// arte ativa sem mexer no estilo procedural (que já está em
  /// [FrameStyle.none] sempre que há uma moldura de imagem selecionada).
  Widget _noImageFrameThumb({required bool selected}) {
    final theme = Theme.of(context);
    return _frameThumbShell(
      key: const ValueKey('imageFrameThumb_none'),
      label: FrameStyle.none.label,
      selected: selected,
      padding: const EdgeInsets.all(11),
      onTap: () => _updateFrameKeepingAnchorPosition(
        _settings.frame.copyWith(clearImageFrame: true),
        anchorKey: _imageFrameAnchorKey,
      ),
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

  /// Desenha a arte de uma moldura de imagem, seja ela um SVG empacotado no
  /// app, um SVG importado pelo usuário, ou (formato legado) um PNG
  /// importado antes de o import passar a exigir SVG.
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

  /// Confirma e remove uma moldura de imagem importada.
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
      if (_settings.frame.imageFrame?.id == asset.id) {
        _updateFrame(_settings.frame.copyWith(clearImageFrame: true));
      }
    });
  }

  Widget _frameColorRow() => _colorPickerRow(
    label: 'Cor da moldura',
    color: _settings.frame.color,
    onTap: _pickFrameColor,
  );

  Widget _backgroundColorRow() => _colorPickerRow(
    key: const ValueKey('backgroundColorRow'),
    label: 'Cor do fundo',
    color: _settings.frame.backgroundColor,
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

  /// Mesma folha de cor da Montagem (swatches + conta-gotas na prévia atual
  /// + roda HSV completa) para os dois seletores de cor do editor — antes
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

  /// Rasteriza a prévia atual (já cortada/na moldura, o que estiver na tela)
  /// para o conta-gotas da folha de cor poder amostrar um pixel dela — mesma
  /// técnica de `CollagePage._renderPreviewImage`, mas capturando o que já
  /// está desenhado na tela em vez de recompor do zero.
  Future<ui.Image> _renderPreviewImage() async {
    final renderObject = _colorPreviewKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('Prévia indisponível para o conta-gotas.');
    }
    return renderObject.toImage(
      pixelRatio: MediaQuery.of(context).devicePixelRatio,
    );
  }

  Widget _frameThicknessRow() {
    final theme = Theme.of(context);
    final frame = _settings.frame;
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

  /// Slider contínuo do arredondamento dos cantos: no mínimo não há
  /// arredondamento nenhum (canto reto); no máximo
  /// ([FrameSettings.maxCornerRatio]) a moldura fica completamente
  /// arredondada. O valor é mostrado como porcentagem desse máximo, não em
  /// pixels — o arredondamento é proporcional ao canvas, não absoluto.
  Widget _cornerRadiusRow() {
    final theme = Theme.of(context);
    final frame = _settings.frame;
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
            _contentFitTile(mode, selected: mode == selected),
            if (mode != _selectableContentFitModes.last)
              const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// Slider disponível somente em "Expandir sem cortar". De 10% a 300%, ele
  /// reduz ou amplia o vídeo nítido central sobre o fundo preto.
  Widget _contentZoomRow() {
    final theme = Theme.of(context);
    final frame = _settings.frame;
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
            onTap: () =>
                _updateFrame(_settings.frame.copyWith(contentFit: mode)),
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

  /// Prévia da aba "Ajustar": o vídeo inteiro com o overlay de recorte
  /// arrastável. A linha do tempo é adicionada depois, por [_timelined],
  /// para permanecer sempre visível.
  Widget _preview() {
    final theme = Theme.of(context);
    final player = _player;

    if (_previewFailed) {
      return Container(
        constraints: const BoxConstraints(minHeight: 180),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(22),
        ),
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
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: player.value.aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(22),
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
  /// o enquadramento que vai sair no GIF. [rounded] aplica o cartão
  /// arredondado só quando não há moldura em volta; dentro de uma moldura
  /// quem arredonda o conteúdo é a própria moldura.
  Widget _croppedPreview({required bool rounded}) {
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
        borderRadius: rounded ? BorderRadius.circular(22) : null,
        border: rounded
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

    final dx = displayDelta.dx * _video.width / previewSize.width;
    final dy = displayDelta.dy * _video.height / previewSize.height;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    final next = ratio == null
        ? resizeFreeCrop(
            crop,
            handle,
            dx,
            dy,
            boundsWidth: _video.width,
            boundsHeight: _video.height,
          )
        : resizeLockedCrop(
            crop,
            handle,
            dx,
            dy,
            ratio,
            boundsWidth: _video.width,
            boundsHeight: _video.height,
          );

    if (next.width == crop.width &&
        next.height == crop.height &&
        next.x == crop.x &&
        next.y == crop.y) {
      return;
    }

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

    final dx = displayDelta.dx * _video.width / previewSize.width;
    final dy = displayDelta.dy * _video.height / previewSize.height;

    final maxX = (_video.width - crop.width).clamp(0, _video.width);
    final maxY = (_video.height - crop.height).clamp(0, _video.height);
    final x = (crop.x + dx.round()).clamp(0, maxX);
    final y = (crop.y + dy.round()).clamp(0, maxY);

    if (x == crop.x && y == crop.y) return;

    _update(
      _settings.copyWith(
        crop: crop.copyWith(x: x, y: y),
      ),
    );
  }

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
      ...AspectPreset.presets.take(5),
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
            labelBuilder: (preset) => preset.hint.isEmpty
                ? preset.label
                : '${preset.label} — ${preset.hint}',
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
          crop: _settings.crop ?? _defaultCustomCrop(),
        );
        return;
      }

      if (preset.ratio == null) {
        _settings = _settings.copyWith(clearCrop: true);
        return;
      }

      _settings = _settings.copyWith(
        crop: CropRect.centeredIn(_video.width, _video.height, preset.ratio!),
      );
    });
  }

  /// Recorte inicial do preset "Personalizado": 80% do vídeo, centralizado.
  CropRect _defaultCustomCrop() {
    final width = _even(((_video.width * 0.8).round()).clamp(2, _video.width));
    final height = _even(
      ((_video.height * 0.8).round()).clamp(2, _video.height),
    );
    return _cropAroundCenter(width, height);
  }

  /// Faixa de destaque mostrando as dimensões atuais da janela de recorte.
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
            '${crop.width}×${crop.height} px',
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
  /// estado atual enquanto não estão em foco (para não atrapalhar a
  /// digitação do usuário).
  Widget _cropSizeInputs(CropRect crop) {
    if (!_widthFocus.hasFocus) _syncSizeField(_widthController, crop.width);
    if (!_heightFocus.hasFocus) _syncSizeField(_heightController, crop.height);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _widthController,
            focusNode: _widthFocus,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Largura (px)',
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
              labelText: 'Altura (px)',
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

  /// Atualiza o texto de um campo sem mexer se já estiver correto, evitando
  /// perder a posição do cursor à toa.
  void _syncSizeField(TextEditingController controller, int value) {
    final text = value.toString();
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

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
    _setCropWidth(parsed);
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
    _setCropHeight(parsed);
  }

  /// Aplica uma nova largura ao recorte, ajustando a altura para manter a
  /// proporção quando um preset fixo está selecionado.
  void _setCropWidth(int width) {
    final crop = _settings.crop;
    if (crop == null) return;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    var w = _even(width.clamp(2, _video.width));
    int h;
    if (ratio != null) {
      h = _even((w / ratio).round().clamp(2, _video.height));
      w = _even((h * ratio).round().clamp(2, _video.width));
    } else {
      h = crop.height;
    }

    _update(_settings.copyWith(crop: _cropAroundCenter(w, h, around: crop)));
  }

  /// Aplica uma nova altura ao recorte, ajustando a largura para manter a
  /// proporção quando um preset fixo está selecionado.
  void _setCropHeight(int height) {
    final crop = _settings.crop;
    if (crop == null) return;

    final ratio = _aspect == _customAspectPreset ? null : _aspect.ratio;
    var h = _even(height.clamp(2, _video.height));
    int w;
    if (ratio != null) {
      w = _even((h * ratio).round().clamp(2, _video.width));
      h = _even((w / ratio).round().clamp(2, _video.height));
    } else {
      w = crop.width;
    }

    _update(_settings.copyWith(crop: _cropAroundCenter(w, h, around: crop)));
  }

  /// Recentraliza o recorte no tamanho padrão do preset atual.
  void _resetCurrentCrop() {
    if (_aspect == _customAspectPreset) {
      _update(_settings.copyWith(crop: _defaultCustomCrop()));
      return;
    }

    if (_aspect.ratio == null) {
      _update(_settings.copyWith(clearCrop: true));
      return;
    }

    _update(
      _settings.copyWith(
        crop: CropRect.centeredIn(_video.width, _video.height, _aspect.ratio!),
      ),
    );
  }

  /// Monta um [CropRect] com o tamanho dado, centralizado em [around] (ou
  /// no centro do vídeo, se omitido), sem ultrapassar as bordas.
  CropRect _cropAroundCenter(int width, int height, {CropRect? around}) {
    var safeWidth = width.clamp(2, _video.width);
    var safeHeight = height.clamp(2, _video.height);
    safeWidth = _even(safeWidth);
    safeHeight = _even(safeHeight);

    final centerX = around == null
        ? _video.width / 2
        : around.x + around.width / 2;
    final centerY = around == null
        ? _video.height / 2
        : around.y + around.height / 2;

    final maxX = _video.width - safeWidth;
    final maxY = _video.height - safeHeight;
    final x = (centerX - safeWidth / 2).round().clamp(0, maxX);
    final y = (centerY - safeHeight / 2).round().clamp(0, maxY);

    return CropRect(x: x, y: y, width: safeWidth, height: safeHeight);
  }

  /// Arredonda para o número par mais próximo abaixo (mínimo 2), exigido
  /// pelos filtros de crop/scale do FFmpeg.
  int _even(int value) {
    if (value <= 2) return 2;
    return value.isEven ? value : value - 1;
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
  LabeledSection _resolutionSection() {
    final available = ConversionSettings.widthOptions
        .where((w) => w <= _video.width)
        .toList();
    if (available.isEmpty) available.add(_video.width);

    final (width, height) = _settings.contentDimensions(_video);
    final selected = available.contains(_settings.targetWidth)
        ? _settings.targetWidth
        : available.last;

    return LabeledSection(
      icon: Icons.photo_size_select_large_rounded,
      title: 'Resolução',
      value: '$width×$height',
      originalValue: '${_video.width}×${_video.height}',
      tip:
          '720 px preserva melhor textos e cantos de molduras; '
          '480 px gera arquivos menores.',
      child: OptionChips<int>(
        options: ConversionSettings.widthOptions,
        selected: selected,
        labelBuilder: (w) => '$w px',
        isEnabled: (w) => w <= _video.width,
        onSelected: (w) => _update(_settings.copyWith(targetWidth: w)),
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
          _sectionCard(
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
          _sectionCard(
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
                height: 17,
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
          _sectionCard(
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
