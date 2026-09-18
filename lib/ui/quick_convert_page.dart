import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/conversion_settings.dart' show ConversionSettings;
import '../models/quick_convert_format.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import '../services/output_service.dart';
import 'widgets/app_bar_title.dart';
import 'widgets/export_progress_dialog.dart' show ExportProgress;
import 'widgets/labeled_section.dart';

/// Tela única de "Converter formato": escolhe o arquivo, o formato de saída,
/// a qualidade e (em "Mais opções") a resolução — sem navegar para outra
/// página. Progresso e resultado da conversão aparecem como popups
/// ([_QuickConvertProgressDialog]/[_QuickConvertResultDialog]) por cima desta
/// mesma tela, em vez de páginas próprias.
///
/// Proporções compactas de propósito — mesmo padrão de densidade da tela
/// inicial ([HomePage]): ícones pequenos, `visualDensity: VisualDensity.compact`
/// nos botões e cartões de seleção baixos, em vez dos blocos grandes do
/// design de referência.
class QuickConvertPage extends StatefulWidget {
  const QuickConvertPage({super.key});

  @override
  State<QuickConvertPage> createState() => _QuickConvertPageState();
}

class _QuickConvertPageState extends State<QuickConvertPage> {
  final _ffmpeg = FfmpegService();

  VideoInfo? _video;
  bool _loadingFile = false;
  QuickConvertFormat? _selected;
  QuickConvertQuality _quality = QuickConvertQuality.standard;
  int? _targetWidth;

  /// Extensões de imagem que podem ser estáticas ou animadas — só para elas
  /// vale a pena decodificar o arquivo e conferir `frameCount` (ver
  /// [_isStaticImage]). Extensões de vídeo nunca entram aqui: o arquivo pode
  /// ser enorme, e `ui.instantiateImageCodec` exigiria ler tudo em memória só
  /// para falhar a decodificação.
  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'bmp',
    'heic',
    'heif',
    'tif',
    'tiff',
    'gif',
    'webp',
  };

  /// O FFprobe trata uma foto parada (JPG/PNG/...) como um "vídeo" de um
  /// quadro só (por isso `probe()` não rejeita), mas converter isso para
  /// vídeo de verdade (MP4) não faz sentido e falha no FFmpeg — o app já
  /// tem uma tela própria para fotos ("Colocar moldura"). Mesma checagem de
  /// `frameCount` que `home_page.dart._pickPhoto` usa, só que invertida
  /// (aqui rejeita a estática, lá rejeitava a animada).
  Future<bool> _isStaticImage(String path) async {
    final extension = path.split('.').last.toLowerCase();
    if (!_imageExtensions.contains(extension)) return false;

    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final isStatic = codec.frameCount <= 1;
      codec.dispose();
      return isStatic;
    } catch (_) {
      // Não decodificou como imagem — não é uma foto estática, então segue
      // o fluxo normal (o probe() abaixo decide se o arquivo é utilizável).
      return false;
    }
  }

  Future<void> _pickFile() async {
    setState(() => _loadingFile = true);

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.media,
        dialogTitle: 'Escolha um arquivo',
      );

      final path = picked?.path;
      if (path == null) {
        if (mounted) setState(() => _loadingFile = false);
        return;
      }

      if (await _isStaticImage(path)) {
        if (mounted) setState(() => _loadingFile = false);
        _showPickError(
          'Essa é uma foto parada, sem vídeo ou animação. '
          '"Converter formato" é para vídeos, GIF ou WebP animado — '
          'para fotos, use "Colocar moldura" na tela inicial.',
        );
        return;
      }

      final video = await _ffmpeg.probe(path);
      if (!mounted) return;

      setState(() {
        _loadingFile = false;
        _video = video;
        _selected = null;
        _quality = QuickConvertQuality.standard;
        _targetWidth = ConversionSettings.recommendedFor(video).targetWidth;
      });
    } on FfmpegException catch (e) {
      if (mounted) setState(() => _loadingFile = false);
      _showPickError(e.message);
    } catch (_) {
      if (mounted) setState(() => _loadingFile = false);
      _showPickError('Não foi possível abrir este arquivo.');
    }
  }

  /// Popup por cima desta mesma tela — em vez de um aviso fixo no layout,
  /// que ficava exibido até a próxima tentativa. Fechar o popup não navega
  /// nem reseta nada: a tela continua exatamente como estava, pronta para
  /// tocar em "Escolher arquivo" de novo.
  void _showPickError(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Não é possível usar este arquivo'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  /// Larguras disponíveis para "Mais opções" — mesmo critério da seção
  /// "Resolução" do editor completo: nunca amplia além do vídeo original.
  List<int> _availableWidths(VideoInfo video) {
    final available = ConversionSettings.widthOptions
        .where((w) => w <= video.width)
        .toList();
    return available.isEmpty ? [video.width] : available;
  }

  /// Extensão do arquivo escolhido (sem o ponto, minúscula) — só para
  /// desmarcar a opção igual ao formato de origem, quando detectável: converter
  /// um arquivo para o próprio formato não faz sentido nessa tela.
  String _sourceExtension(VideoInfo video) {
    final name = video.fileName;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Roda a conversão mostrando o popup de progresso — nunca uma página
  /// própria. O popup fecha sempre (sucesso, cancelamento ou erro); depois,
  /// erro vira um `AlertDialog` e sucesso vira o popup de resultado. Vídeo,
  /// formato e qualidade continuam escolhidos na tela ao final, prontos para
  /// converter de novo (o X do cartão de origem já serve pra trocar de
  /// arquivo).
  Future<void> _convert() async {
    final video = _video!;
    final format = _selected!;
    final quality = _quality;
    final width =
        _targetWidth ?? ConversionSettings.recommendedFor(video).targetWidth;

    final progress = ValueNotifier(const ExportProgress());
    var cancelling = false;
    final navigator = Navigator.of(context, rootNavigator: true);

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _QuickConvertProgressDialog(
          progress: progress,
          formatLabel: format.label,
          onCancel: () {
            cancelling = true;
            progress.value = ExportProgress(
              value: progress.value.value,
              cancelling: true,
            );
            unawaited(_ffmpeg.cancel());
          },
        ),
      ),
    );

    File? file;
    String? errorMessage;
    String? errorLogs;
    try {
      file = await _ffmpeg.quickConvert(
        video: video,
        format: format,
        quality: quality,
        targetWidth: width,
        onProgress: (value) {
          progress.value = ExportProgress(value: value, cancelling: cancelling);
        },
      );
    } on FfmpegException catch (e) {
      if (!cancelling) {
        errorMessage = e.message;
        errorLogs = e.logs.trim().isEmpty ? null : e.logs;
      }
    } catch (_) {
      if (!cancelling) errorMessage = 'Algo deu errado durante a conversão.';
    } finally {
      navigator.pop();
    }

    if (!mounted) return;
    if (errorMessage != null) {
      await _showConvertError(errorMessage, errorLogs);
      return;
    }
    if (file == null) return; // cancelado pelo usuário, sem erro pra mostrar

    await showDialog<void>(
      context: context,
      builder: (_) => _QuickConvertResultDialog(file: file!, format: format),
    );
  }

  Future<void> _showConvertError(String message, String? logs) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Não deu certo'),
        content: Text(message),
        actions: [
          if (logs != null)
            TextButton(
              onPressed: () => _showLogs(dialogContext, logs),
              child: const Text('Ver detalhes técnicos'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showLogs(BuildContext context, String logs) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Detalhes técnicos'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              logs,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: logs));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(const SnackBar(content: Text('Log copiado.')));
              }
            },
            child: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;

    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('Converter formato')),
      body: SafeArea(
        child: video == null ? _buildPicker() : _buildForm(context, video),
      ),
    );
  }

  /// Mesma `ListView` de [_buildForm] de propósito: num `Padding` direto, o
  /// cartão herdaria a altura cheia que o `Scaffold` passa para o corpo e
  /// esticaria pela tela inteira. Aqui ele fica do tamanho do próprio
  /// conteúdo, no mesmo lugar onde o cartão do arquivo aparece depois.
  Widget _buildPicker() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [_PickFileCard(loading: _loadingFile, onTap: _pickFile)],
    );
  }

  Widget _buildForm(BuildContext context, VideoInfo video) {
    final availableWidths = _availableWidths(video);
    final selectedWidth = availableWidths.contains(_targetWidth)
        ? _targetWidth!
        : availableWidths.last;
    final sourceExtension = _sourceExtension(video);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SourceCard(
          video: video,
          extension: sourceExtension,
          onRemove: () => setState(() => _video = null),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Formato de saída'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final format in QuickConvertFormat.values) ...[
              if (format != QuickConvertFormat.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: _SelectableCard(
                  icon: format.icon,
                  label: format.label,
                  selected: _selected == format,
                  onTap: format.extension == sourceExtension
                      ? null
                      : () => setState(() => _selected = format),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        _SectionLabel('Qualidade'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final quality in QuickConvertQuality.values) ...[
              if (quality != QuickConvertQuality.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: _SelectableCard(
                  label: quality.label,
                  sublabel: quality.hint,
                  selected: _quality == quality,
                  onTap: () => setState(() => _quality = quality),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        LabeledSection(
          icon: Icons.tune_rounded,
          title: 'Mais opções',
          value: '$selectedWidth px',
          originalValue: '${video.width} px',
          hint:
              'Resolução do arquivo de saída — nunca amplia além do original.',
          child: OptionChips<int>(
            options: availableWidths,
            selected: selectedWidth,
            labelBuilder: (w) => '$w px',
            isEnabled: (w) => w <= video.width,
            onSelected: (w) => setState(() => _targetWidth = w),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: _selected == null ? null : _convert,
          icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
          label: const Text('Converter'),
        ),
      ],
    );
  }
}

/// Cartão compacto de "Escolher arquivo", exibido enquanto nenhum arquivo
/// ainda foi escolhido — troca de lugar com [_SourceCard] no mesmo espaço da
/// tela quando o arquivo é selecionado (ou removido pelo X do cartão de
/// origem), sem navegar para outra página.
class _PickFileCard extends StatelessWidget {
  const _PickFileCard({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: scheme.surfaceContainerLow,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimaryContainer,
                        ),
                      )
                    : Icon(
                        Icons.add,
                        color: scheme.onPrimaryContainer,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Escolher arquivo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Vídeo, GIF ou WebP',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Título de seção compacto, mesmo peso visual usado no resto da tela.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// Cartão de seleção compacto, usado tanto para o formato de saída (com
/// ícone) quanto para a qualidade (só texto) — bem menor que os blocos do
/// design de referência, no mesmo espírito discreto dos botões da tela
/// inicial.
class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.selected,
    required this.onTap,
    required this.label,
    this.icon,
    this.sublabel,
  });

  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final String label;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: selected
                      ? scheme.primary.withValues(alpha: 0.10)
                      : scheme.surfaceContainerLow,
                  border: Border.all(
                    color: selected
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.6),
                    width: selected ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 18,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? scheme.primary : null,
                      ),
                    ),
                    if (sublabel != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        sublabel!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.video,
    required this.extension,
    required this.onRemove,
  });

  final VideoInfo video;

  /// Extensão do arquivo escolhido (sem o ponto, minúscula), já calculada
  /// pela tela — mesmo valor usado para desmarcar o formato de saída igual
  /// ao de origem. Aqui só vira o selo "PNG"/"MP4"/etc. ao lado do nome.
  final String extension;

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minutes = video.durationSeconds ~/ 60;
    final seconds = (video.durationSeconds % 60).round();
    final duration = minutes > 0
        ? '${minutes}min ${seconds}s'
        : '${video.durationSeconds.toStringAsFixed(1)}s';
    final size = SizeEstimate.formatBytes(video.fileSizeBytes);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.insert_drive_file_outlined,
                color: scheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          video.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (extension.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            extension.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${video.width} × ${video.height} px • $duration • $size',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remover arquivo',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// Popup de progresso da conversão — mesmo padrão de
/// [ExportProgressDialog]/`ExportProgress` já usado pela exportação animada
/// da montagem ([collage_page.dart]): o estado (`value`/`cancelling`) vive
/// num `ValueNotifier` de quem chama, então este diálogo nunca precisa dele
/// mesmo ter `setState` — só escuta.
class _QuickConvertProgressDialog extends StatelessWidget {
  const _QuickConvertProgressDialog({
    required this.progress,
    required this.formatLabel,
    required this.onCancel,
  });

  final ValueListenable<ExportProgress> progress;
  final String formatLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          child: ValueListenableBuilder<ExportProgress>(
            valueListenable: progress,
            builder: (context, state, _) {
              final percent = (state.value * 100).clamp(0, 100).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: state.value > 0.01 ? state.value : null,
                            strokeWidth: 7,
                          ),
                        ),
                        Text(
                          '$percent%',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    state.cancelling
                        ? 'Cancelando…'
                        : 'Convertendo para $formatLabel',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Isso pode levar alguns segundos.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: state.cancelling ? null : onCancel,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancelar'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Popup de resultado — ícone de sucesso, tamanho do arquivo e as ações de
/// salvar/compartilhar, dono do próprio estado de salvamento (mesmo padrão
/// de `_TextInputDialog` em `collage_page.dart`: um diálogo que guarda seu
/// próprio estado em vez de depender da tela que o abriu).
class _QuickConvertResultDialog extends StatefulWidget {
  const _QuickConvertResultDialog({required this.file, required this.format});

  final File file;
  final QuickConvertFormat format;

  @override
  State<_QuickConvertResultDialog> createState() =>
      _QuickConvertResultDialogState();
}

class _QuickConvertResultDialogState extends State<_QuickConvertResultDialog> {
  static const _output = OutputService();

  bool _saving = false;
  bool _saved = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _output.saveToGallery(
        widget.file,
        asVideo: !widget.format.isAnimatedImage,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      _message('${widget.format.label} salvo na galeria.');
    } on OutputException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message(e.message);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bytes = widget.file.lengthSync();

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 44,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Tamanho do arquivo',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              SizeEstimate.formatBytes(bytes),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.format.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _saving || _saved ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _saved ? Icons.check_rounded : Icons.download_rounded,
                      size: 20,
                    ),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : _saved
                    ? 'Salvo na galeria'
                    : 'Salvar na galeria',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _output.share(
                widget.file,
                mimeType: widget.format.mimeType,
                text: '${widget.format.label} feito com o app Video to GIF',
              ),
              icon: const Icon(Icons.share_outlined, size: 20),
              label: const Text('Compartilhar'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}
