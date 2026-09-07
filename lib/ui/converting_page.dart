import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/conversion_settings.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import 'result_page.dart';

/// Tela exibida durante a conversão: mostra a barra de progresso e navega
/// para o [ResultPage] ao terminar, ou para uma tela de erro se falhar.
class ConvertingPage extends StatefulWidget {
  const ConvertingPage({
    super.key,
    required this.video,
    required this.settings,
    required this.estimate,
  });

  final VideoInfo video;
  final ConversionSettings settings;
  final SizeEstimate estimate;

  @override
  State<ConvertingPage> createState() => _ConvertingPageState();
}

class _ConvertingPageState extends State<ConvertingPage> {
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

  /// Dispara a conversão assim que a tela é montada, atualizando
  /// [_progress] a cada callback do FFmpeg e navegando para o resultado
  /// ao concluir.
  Future<void> _start() async {
    try {
      final result = await _ffmpeg.convert(
        video: widget.video,
        settings: widget.settings,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultPage(
            result: result,
            estimate: widget.estimate,
            settings: widget.settings,
            video: widget.video,
          ),
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

  /// Pede o cancelamento da conversão em andamento.
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

  /// Círculo de progresso com percentual, resumo do GIF previsto e botão
  /// de cancelar.
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
              : 'Convertendo em ${widget.settings.format.shortLabel}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          // A estimativa calibrada (widget.estimate) só é confiável para
          // GIF — ver o comentário em FfmpegService.calibrate(). Mostrar
          // "Peso previsto" com esse número para uma exportação em WebP
          // seria enganoso, então a linha some nesse caso.
          widget.settings.format == OutputFormat.gif
              ? '${widget.estimate.width}×${widget.estimate.height} px\n'
                    'Peso previsto: ${widget.estimate.formatted}'
              : '${widget.estimate.width}×${widget.estimate.height} px',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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

  /// Mensagem de erro com botão para voltar e ajustar as configurações.
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
          child: const Text('Voltar e ajustar'),
        ),
      ],
    );
  }

  /// Mostra o log bruto do FFmpeg num diálogo rolável, com opção de copiar
  /// — para o usuário poder relatar o problema com detalhes técnicos em
  /// vez de só "não deu certo".
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
