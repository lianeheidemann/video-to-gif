import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/conversion_settings.dart';
import '../models/photo_info.dart';
import '../services/ffmpeg_service.dart';
import '../theme_controller.dart';
import 'widgets/gif_weight_help_sheet.dart';
import 'collage_page.dart';
import 'editor_page.dart';
import 'photo_frame_page.dart';
import 'quick_convert_pick_page.dart';

/// Tela inicial: apresenta o app e deixa o usuário escolher um vídeo para
/// começar a edição.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ffmpeg = FfmpegService();
  bool _loading = false;
  String? _error;

  /// Abre o seletor de arquivos, lê os metadados do vídeo escolhido com o
  /// FFprobe e navega para o [EditorPage] com as configurações recomendadas.
  Future<void> _pickVideo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // O seletor do sistema devolve acesso só ao arquivo escolhido, por isso
      // o app não precisa de permissão de leitura de mídia.
      final picked = await FilePicker.pickFile(
        type: FileType.video,
        dialogTitle: 'Escolha um vídeo',
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
          builder: (_) => EditorPage(
            video: video,
            initialSettings: ConversionSettings.recommendedFor(video),
          ),
        ),
      );
    } on FfmpegException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível abrir este vídeo.';
        });
      }
    }
  }

  /// Abre o seletor de arquivos para uma foto, decodifica as dimensões
  /// nativas localmente (sem FFprobe — não há nada além do tamanho para
  /// sondar numa imagem estática) e navega para [PhotoFramePage].
  Future<void> _pickPhoto() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: 'Escolha uma foto',
      );

      final path = picked?.path;
      if (path == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      // "Colocar moldura" só sabe desenhar uma foto parada — um GIF/WebP
      // animado decodificaria normalmente (é só imagem pra esse codec), mas
      // ia perder o resto dos quadros em silêncio, virando uma foto parada
      // sem ninguém pedir isso. Vídeo nem chega aqui: o seletor já filtra
      // por `FileType.image`.
      if (codec.frameCount > 1) {
        codec.dispose();
        if (mounted) {
          setState(() {
            _loading = false;
            _error =
                'Essa imagem é animada (GIF/WebP). "Colocar moldura" só '
                'aceita fotos paradas.';
          });
        }
        return;
      }
      final frame = await codec.getNextFrame();
      final photo = PhotoInfo(
        path: path,
        width: frame.image.width,
        height: frame.image.height,
      );
      frame.image.dispose();
      if (!mounted) return;

      setState(() => _loading = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PhotoFramePage(photo: photo)),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível abrir esta foto.';
        });
      }
    }
  }

  /// Abre o seletor de arquivos permitindo escolher várias fotos de uma vez
  /// (`FilePicker.pickFiles` com seleção múltipla, ao contrário de
  /// `_pickPhoto`'s `pickFile` singular) e navega para [CollagePage], onde o
  /// usuário monta a colagem. Exige pelo menos duas fotos — uma única foto já
  /// tem sua própria tela dedicada em "Colocar moldura".
  Future<void> _pickPhotosForCollage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: 'Escolha as fotos da montagem',
      );

      if (picked.length < 2) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = picked.isEmpty
                ? null
                : 'Escolha pelo menos duas fotos para montar uma colagem.';
          });
        }
        return;
      }

      final photos = <PhotoInfo>[];
      for (final file in picked) {
        final path = file.path;
        if (path == null) continue;
        final bytes = await File(path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        photos.add(
          PhotoInfo(
            path: path,
            width: frame.image.width,
            height: frame.image.height,
          ),
        );
        frame.image.dispose();
      }
      if (!mounted) return;

      if (photos.length < 2) {
        setState(() {
          _loading = false;
          _error = 'Escolha pelo menos duas fotos para montar uma colagem.';
        });
        return;
      }

      setState(() => _loading = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CollagePage(photos: photos)),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível abrir essas fotos.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Como deixar o GIF mais leve',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showGifWeightHelpSheet(context),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return IconButton(
                tooltip: isDark ? 'Ativar modo claro' : 'Ativar modo escuro',
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                ),
                onPressed: toggleThemeMode,
              );
            },
          ),
          IconButton(
            tooltip: 'Sobre e licenças',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Video to GIF',
              applicationVersion: '1.0.0',
              applicationLegalese:
                  'Conversão feita no próprio aparelho com FFmpeg (LGPL). '
                  'Nenhum vídeo é enviado para a internet.',
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/icon/icon-v4.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                  semanticLabel: 'Ícone do conversor de vídeo para GIF',
                ),
                const SizedBox(height: 24),
                Text(
                  'Video to GIF',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Corte, ajuste o tamanho e a velocidade — e veja quanto o '
                  'GIF vai pesar antes de converter.',
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
                  onPressed: _loading ? null : _pickVideo,
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.video_library_outlined),
                  label: Text(_loading ? 'Abrindo…' : 'Escolher vídeo'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickPhoto,
                  icon: const Icon(Icons.photo_filter_outlined),
                  label: const Text('Colocar moldura'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickPhotosForCollage,
                  icon: const Icon(Icons.dashboard_customize_outlined),
                  label: const Text('Montagem'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const QuickConvertPickPage(),
                          ),
                        ),
                  icon: const Icon(Icons.cached_outlined),
                  label: const Text('Converter formato'),
                ),
                const SizedBox(height: 28),
                const _StepsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _kStepCircleSize = 56.0;

/// Etapas do fluxo de conversão, exibidas como um pequeno guia visual.
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  static const _steps = [
    (icon: Icons.folder_open_outlined, label: 'Selecionar vídeo'),
    (icon: Icons.tune_rounded, label: 'Ajustar'),
    (icon: Icons.auto_fix_high_rounded, label: 'Converter'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              if (i > 0) const Expanded(child: _StepConnector()),
              _StepIcon(icon: _steps[i].icon, label: _steps[i].label),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _kStepCircleSize,
          height: _kStepCircleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _kStepCircleSize,
      child: Row(
        children: [
          const Expanded(child: _DashedLine()),
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
            ),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 15,
              color: theme.colorScheme.onPrimary,
            ),
          ),
          const Expanded(child: _DashedLine()),
        ],
      ),
    );
  }
}

/// Linha tracejada usada para ligar os ícones de etapa em [_StepsCard].
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.4);

    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dashWidth + gap)).floor().clamp(
          1,
          100,
        );
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: dashWidth,
              height: 2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      },
    );
  }
}
