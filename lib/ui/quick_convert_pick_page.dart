import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/ffmpeg_service.dart';
import 'quick_convert_format_page.dart';

/// Primeira tela de "Converter formato": só escolhe o arquivo, sem nenhuma
/// configuração. Aceita qualquer formato que o FFmpeg saiba abrir — vídeo,
/// GIF ou WebP. Usa o seletor de mídia do sistema (`FileType.media`) para
/// manter a mesma interface visual de galeria usada em "Escolher vídeo" e
/// "Colocar moldura", validando depois se o conteúdo pode ser convertido.
class QuickConvertPickPage extends StatefulWidget {
  const QuickConvertPickPage({super.key});

  @override
  State<QuickConvertPickPage> createState() => _QuickConvertPickPageState();
}

class _QuickConvertPickPageState extends State<QuickConvertPickPage> {
  final _ffmpeg = FfmpegService();
  bool _loading = false;
  String? _error;

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
  /// vídeo de verdade (MP4/WebM/MOV) não faz sentido e falha no FFmpeg — o
  /// app já tem uma tela própria para fotos ("Colocar moldura"). Mesma
  /// checagem de `frameCount` que `home_page.dart._pickPhoto` usa, só que
  /// invertida (aqui rejeita a estática, lá rejeitava a animada).
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
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.media,
        dialogTitle: 'Escolha um arquivo',
      );

      final path = picked?.path;
      if (path == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      if (await _isStaticImage(path)) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Essa é uma foto parada, sem vídeo ou animação. '
                '"Converter formato" é para vídeos, GIF ou WebP animado — '
                'para fotos, use "Colocar moldura" na tela inicial.';
          });
        }
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
