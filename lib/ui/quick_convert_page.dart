import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/quick_convert_format.dart';
import '../models/size_estimate.dart';
import '../models/video_info.dart';
import '../services/ffmpeg_service.dart';
import '../services/output_service.dart';
import 'widgets/app_bar_title.dart';
import 'widgets/source_file_card.dart';

/// Tela única de "Converter formato": escolher o arquivo e escolher para qual
/// formato converter acontecem no mesmo lugar.
///
/// Antes eram duas telas empilhadas — uma só com o botão de escolher, outra só
/// com as informações e os formatos, sem como trocar de arquivo sem voltar.
/// Aqui o arquivo vive no estado da tela: escolher um atualiza o cartão de
/// informações no lugar, e o botão de escolher continua visível para trocar
/// quantas vezes quiser.
///
/// Aceita qualquer formato que o FFmpeg saiba abrir — vídeo, GIF ou WebP. Usa
/// `FileType.media` (seletor de mídia estilo galeria, aceitando vídeo e imagem
/// no mesmo seletor), validando depois se o conteúdo pode ser convertido.
class QuickConvertPage extends StatefulWidget {
  const QuickConvertPage({super.key});

  @override
  State<QuickConvertPage> createState() => _QuickConvertPageState();
}

class _QuickConvertPageState extends State<QuickConvertPage> {
  /// `late`: o construtor de [FfmpegService] chama `enableLogCallback`, um
  /// canal de plataforma que lança `MissingPluginException` em `flutter test`.
  /// Adiando a construção até o primeiro toque, a tela vazia fica testável.
  late final _ffmpeg = FfmpegService();

  bool _loading = false;
  VideoInfo? _video;
  QuickConvertFormat? _selected;

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

  /// Extensão do arquivo escolhido (sem o ponto, minúscula) — serve para o
  /// selo no cartão e para desmarcar a opção igual ao formato de origem:
  /// converter um arquivo para o próprio formato não faz sentido nesta tela.
  String get _sourceExtension {
    final name = _video?.fileName;
    if (name == null) return '';
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

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
    setState(() => _loading = true);

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
        if (mounted) setState(() => _loading = false);
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
        _loading = false;
        _video = video;
        // O chip do formato igual ao da origem vem desabilitado. Sem zerar a
        // escolha, quem pega GIF para um MP4 e depois troca para um arquivo
        // GIF fica com uma seleção apontando para o formato do próprio
        // arquivo.
        _selected = null;
      });
    } on FfmpegException catch (e) {
      if (mounted) setState(() => _loading = false);
      _showPickError(e.message);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _showPickError('Não foi possível abrir este arquivo.');
    }
  }

  /// Popup por cima desta mesma tela — em vez de um aviso fixo no layout,
  /// que ficava exibido até a próxima tentativa. Fechar o popup não navega
  /// nem reseta nada: quem já tinha um arquivo bom e tentou um inválido volta
  /// para o estado que tinha, não para a tela vazia.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = _video;

    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('Converter formato')),
      body: SafeArea(
        // Sem arquivo o conteúdo fica centralizado, como era na tela de
        // escolha; com arquivo, alinhado no topo. O `ConstrainedBox` dá ao
        // `Column` a altura da tela para poder centralizar, e o
        // `SingleChildScrollView` por fora evita estouro em tela baixa.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // Menos o padding vertical, para o estado vazio preencher a
                // viewport exatamente e não sobrar rolagem. O clamp cobre a
                // viewport mais baixa que o próprio padding, que faria um
                // minHeight negativo estourar a asserção do BoxConstraints.
                minHeight: (constraints.maxHeight - 48).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Column(
                mainAxisAlignment: video == null
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (video == null) ...[
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
                      'Vídeo, GIF ou WebP — depois de escolher, o formato de '
                      'saída aparece aqui mesmo.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ] else ...[
                    SourceFileCard(video: video, extension: _sourceExtension),
                    const SizedBox(height: 16),
                  ],
                  _pickButton(video != null),
                  if (video != null) ...[
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
                                : (value) => setState(
                                    () => _selected = value ? format : null,
                                  ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Escolher arquivo é a ação principal enquanto não há nenhum; depois que
  /// há, "Converter" assume o destaque e trocar de arquivo vira secundário.
  Widget _pickButton(bool hasVideo) {
    final icon = _loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.folder_open_outlined);
    final label = Text(
      _loading
          ? 'Abrindo…'
          : hasVideo
          ? 'Escolher outro arquivo'
          : 'Escolher arquivo',
    );
    final onPressed = _loading ? null : _pickFile;

    return hasVideo
        ? OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label)
        : FilledButton.icon(onPressed: onPressed, icon: icon, label: label);
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
