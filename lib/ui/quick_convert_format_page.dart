import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/quick_convert_format.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import '../services/output_service.dart';

/// Segunda tela de "Converter formato": mostra o arquivo escolhido e deixa
/// escolher, entre os 5 formatos suportados, para qual converter — sem
/// nenhuma outra configuração (sem corte, qualidade ou prévia).
class QuickConvertFormatPage extends StatefulWidget {
  const QuickConvertFormatPage({super.key, required this.video});

  final VideoInfo video;

  @override
  State<QuickConvertFormatPage> createState() => _QuickConvertFormatPageState();
}

class _QuickConvertFormatPageState extends State<QuickConvertFormatPage> {
  QuickConvertFormat? _selected;

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

    return Scaffold(
      appBar: AppBar(title: const Text('Converter para')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _SourceCard(video: video, extension: _sourceExtension),
            const SizedBox(height: 28),
            Text(
              'Formato de saída',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final format in QuickConvertFormat.values)
                  ChoiceChip(
                    label: Text(format.label),
                    selected: _selected == format,
                    onSelected: format.extension == _sourceExtension
                        ? null
                        : (value) =>
                              setState(() => _selected = value ? format : null),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _QuickConvertConvertingPage(
                          video: video,
                          format: _selected!,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Converter'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.video, required this.extension});

  final VideoInfo video;

  /// Extensão do arquivo escolhido (sem o ponto, minúscula), já calculada
  /// pela tela — mesmo valor usado para desmarcar o formato de saída igual
  /// ao de origem. Aqui só vira o selo "PNG"/"MP4"/etc. ao lado do nome.
  final String extension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minutes = video.durationSeconds ~/ 60;
    final seconds = (video.durationSeconds % 60).round();
    final duration = minutes > 0
        ? '${minutes}min ${seconds}s'
        : '${video.durationSeconds.toStringAsFixed(1)}s';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.insert_drive_file_outlined,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 14),
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
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (extension.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            extension.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${video.width} × ${video.height} px • $duration',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
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
  });

  final VideoInfo video;
  final QuickConvertFormat format;

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
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: _progress > 0.01 ? _progress : null,
                  strokeWidth: 8,
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
        const SizedBox(height: 28),
        Text(
          _cancelling
              ? 'Cancelando…'
              : 'Convertendo para ${widget.format.label}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 32),
        TextButton.icon(
          onPressed: _cancelling ? null : _cancel,
          icon: const Icon(Icons.close),
          label: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _errorView(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 20),
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
      appBar: AppBar(title: Text('${widget.format.label} pronto')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 56,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    SizeEstimate.formatBytes(bytes),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.format.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving || _saved ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_saved ? Icons.check_rounded : Icons.download_rounded),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : _saved
                    ? 'Salvo na galeria'
                    : 'Salvar na galeria',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _output.share(
                widget.file,
                mimeType: widget.format.mimeType,
                text: '${widget.format.label} feito com o app Video to GIF',
              ),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartilhar'),
            ),
          ],
        ),
      ),
    );
  }
}
