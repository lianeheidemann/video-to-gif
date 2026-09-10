import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/ffmpeg_service.dart';
import 'quick_convert_format_page.dart';

/// Primeira tela de "Converter formato": só escolhe o arquivo, sem nenhuma
/// configuração. Aceita qualquer formato que o FFmpeg saiba abrir — vídeo,
/// GIF ou WebP —, ao contrário de "Escolher vídeo" (`FileType.video`, que
/// nunca inclui `.gif`/`.webp`) ou "Colocar moldura" (`FileType.image`, que
/// só aceita fotos).
class QuickConvertPickPage extends StatefulWidget {
  const QuickConvertPickPage({super.key});

  @override
  State<QuickConvertPickPage> createState() => _QuickConvertPickPageState();
}

class _QuickConvertPickPageState extends State<QuickConvertPickPage> {
  final _ffmpeg = FfmpegService();
  bool _loading = false;
  String? _error;

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.any,
        dialogTitle: 'Escolha um arquivo',
      );

      final path = picked?.path;
      if (path == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final video = await _ffmpeg.probe(path);
      if (!mounted) return;

      setState(() => _loading = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QuickConvertFormatPage(video: video),
        ),
      );
    } on FfmpegException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível abrir este arquivo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Converter formato')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.cached_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Escolha o arquivo',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Vídeo, GIF ou WebP — na próxima tela você escolhe para '
                  'qual formato converter.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (_error != null) ...[
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed: _loading ? null : _pickFile,
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(_loading ? 'Abrindo…' : 'Escolher arquivo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
