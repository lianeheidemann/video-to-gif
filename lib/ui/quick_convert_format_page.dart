import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/conversion_settings.dart' show ConversionSettings;
import '../models/quick_convert_format.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import '../services/output_service.dart';
import 'widgets/app_bar_title.dart';
import 'widgets/labeled_section.dart';

/// Segunda tela de "Converter formato": mostra o arquivo escolhido e deixa
/// escolher, entre os 3 formatos suportados, para qual converter, além de
/// um nível de qualidade e (em "Mais opções") a resolução de saída.
///
/// Proporções compactas de propósito — mesmo padrão de densidade da tela
/// inicial ([HomePage]): ícones pequenos, `visualDensity: VisualDensity.compact`
/// nos botões e cartões de seleção baixos, em vez dos blocos grandes do
/// design de referência.
class QuickConvertFormatPage extends StatefulWidget {
  const QuickConvertFormatPage({super.key, required this.video});

  final VideoInfo video;

  @override
  State<QuickConvertFormatPage> createState() => _QuickConvertFormatPageState();
}

class _QuickConvertFormatPageState extends State<QuickConvertFormatPage> {
  QuickConvertFormat? _selected;
  QuickConvertQuality _quality = QuickConvertQuality.standard;
  late int _targetWidth;

  @override
  void initState() {
    super.initState();
    _targetWidth = ConversionSettings.recommendedFor(widget.video).targetWidth;
  }

  /// Larguras disponíveis para "Mais opções" — mesmo critério da seção
  /// "Resolução" do editor completo: nunca amplia além do vídeo original.
  List<int> get _availableWidths {
    final available = ConversionSettings.widthOptions
        .where((w) => w <= widget.video.width)
        .toList();
    return available.isEmpty ? [widget.video.width] : available;
  }

  /// Extensão do arquivo escolhido (sem o ponto, minúscula) — só para
  /// desmarcar a opção igual ao formato de origem, quando detectável: converter
  /// um arquivo para o próprio formato não faz sentido nessa tela.
  String get _sourceExtension {
    final name = widget.video.fileName;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = widget.video;
    final availableWidths = _availableWidths;
    final selectedWidth = availableWidths.contains(_targetWidth)
        ? _targetWidth
        : availableWidths.last;

    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('Converter')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Escolha o arquivo e o formato de saída',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _SourceCard(
              video: video,
              extension: _sourceExtension,
              onRemove: () => Navigator.of(context).pop(),
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
                      onTap: format.extension == _sourceExtension
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
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _selected == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _QuickConvertConvertingPage(
                          video: video,
                          format: _selected!,
                          quality: _quality,
                          targetWidth: selectedWidth,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
              label: const Text('Converter'),
            ),
          ],
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

/// Tela de progresso da conversão — mesmo desenho visual de
/// `ConvertingPage`, mas chamando `quickConvert` em vez de `convert`, já que
/// aqui não existe `ConversionSettings`/estimativa de tamanho nenhuma.
class _QuickConvertConvertingPage extends StatefulWidget {
  const _QuickConvertConvertingPage({
    required this.video,
    required this.format,
    required this.quality,
    required this.targetWidth,
  });

  final VideoInfo video;
  final QuickConvertFormat format;
  final QuickConvertQuality quality;
  final int targetWidth;

  @override
  State<_QuickConvertConvertingPage> createState() =>
      _QuickConvertConvertingPageState();
}

class _QuickConvertConvertingPageState
    extends State<_QuickConvertConvertingPage> {
  final _ffmpeg = FfmpegService();

  double _progress = 0;
  String? _error;
  String? _errorLogs;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final file = await _ffmpeg.quickConvert(
        video: widget.video,
        format: widget.format,
        quality: widget.quality,
        targetWidth: widget.targetWidth,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              _QuickConvertResultPage(file: file, format: widget.format),
        ),
      );
    } on FfmpegException catch (e) {
      if (!mounted) return;
      if (_cancelling) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = e.message;
        _errorLogs = e.logs.trim().isEmpty ? null : e.logs;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Algo deu errado durante a conversão.');
    }
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    await _ffmpeg.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _error != null,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: _error != null ? _errorView(theme) : _progressView(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressView(ThemeData theme) {
    final percent = (_progress * 100).clamp(0, 100).round();

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
                  value: _progress > 0.01 ? _progress : null,
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
          _cancelling
              ? 'Cancelando…'
              : 'Convertendo para ${widget.format.label}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Isso pode levar alguns segundos.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: _cancelling ? null : _cancel,
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _errorView(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text('Não deu certo', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (_errorLogs != null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _showLogs(context),
            child: const Text('Ver detalhes técnicos'),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Voltar'),
        ),
      ],
    );
  }

  void _showLogs(BuildContext context) {
    final logs = _errorLogs!;
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
}

/// Tela final simples — nome, tamanho e as ações de salvar/compartilhar,
/// sem a linha de estimativa de tamanho de `ResultPage` (específica do GIF).
class _QuickConvertResultPage extends StatefulWidget {
  const _QuickConvertResultPage({required this.file, required this.format});

  final File file;
  final QuickConvertFormat format;

  @override
  State<_QuickConvertResultPage> createState() =>
      _QuickConvertResultPageState();
}

class _QuickConvertResultPageState extends State<_QuickConvertResultPage> {
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

    return Scaffold(
      appBar: AppBar(title: AppBarTitle('${widget.format.label} pronto')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
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
                ],
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
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Fechar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
