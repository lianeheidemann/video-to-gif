import 'dart:io';
import 'dart:math' as math;
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
  const QuickConvertPage({super.key, this.initialVideo});

  /// Só para teste: o estado com arquivo depende de um `probe()` de verdade,
  /// que não roda em `flutter test`. Em produção a tela sempre nasce vazia.
  @visibleForTesting
  final VideoInfo? initialVideo;

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

  @override
  void initState() {
    super.initState();
    _video = widget.initialVideo;
  }

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
        // Os dois estados têm a mesma estrutura, alinhada ao topo: anexar um
        // arquivo troca só o bloco de cima e liga os controles de baixo, que
        // nunca mudam de lugar.
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (video == null)
              _PickDropzone(
                loading: _loading,
                onTap: _loading ? null : _pickFile,
              )
            else ...[
              SourceFileCard(video: video, extension: _sourceExtension),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loading ? null : _pickFile,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open_outlined),
                label: Text(_loading ? 'Abrindo…' : 'Escolher outro arquivo'),
              ),
            ],
            // Sem o botão contornado ocupando espaço, o estado vazio precisa
            // de um vão maior para o miolo não subir.
            SizedBox(height: video == null ? 40 : 28),
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
                    // Desligado enquanto não há arquivo, e desligado para o
                    // formato do próprio arquivo: converter algo para o
                    // formato que ele já tem não faz sentido aqui.
                    onSelected:
                        video == null || format.extension == _sourceExtension
                        ? null
                        : (value) =>
                              setState(() => _selected = value ? format : null),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              // O `video == null` é redundante hoje (sem arquivo não dá para
              // marcar chip, e `_pickFile` zera a escolha), mas deixa a
              // garantia no próprio botão.
              onPressed: video == null || _selected == null
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      // Só fecha pelos botões do próprio popup: tocar fora
                      // durante a conversão abandonaria o FFmpeg rodando.
                      barrierDismissible: false,
                      builder: (_) =>
                          _QuickConvertDialog(video: video, format: _selected!),
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

/// Área tracejada que convida a anexar o arquivo, no lugar do cartão de
/// informações enquanto não há nenhum escolhido. A área inteira é o alvo do
/// toque, não só o "+".
class _PickDropzone extends StatelessWidget {
  const _PickDropzone({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  static const _radius = 22.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      // Mesmo raio dos Card do tema, para a área vazia e o cartão que a
      // substitui terem a mesma silhueta.
      color: scheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: scheme.primary.withValues(alpha: 0.55),
            radius: _radius,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: loading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: scheme.onPrimary,
                          ),
                        )
                      : Icon(
                          Icons.add_rounded,
                          size: 30,
                          color: scheme.onPrimary,
                        ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loading ? 'Abrindo…' : 'Escolher arquivo',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Vídeo, GIF ou WebP',
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
        ),
      ),
    );
  }
}

/// Contorno tracejado de canto arredondado. O `_DashedLine` da tela inicial
/// não serve aqui: ele é uma fileira de quadradinhos, que não acompanha
/// curva. Este percorre o contorno com `computeMetrics` e desenha pedaços.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _stroke = 1.6;
  static const _dash = 7.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    // Encolhe meio traço para dentro: o traço é centrado no caminho, então
    // sem isso metade dele cairia fora da área do widget.
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// Em que ponto a conversão está. As três fases moram no mesmo popup, em
/// vez das duas telas cheias que o fluxo empilhava antes.
enum _ConvertPhase { converting, failed, done }

/// Popup que conduz a conversão do começo ao fim por cima da tela de
/// "Converter formato": progresso, erro e resultado sem nunca sair de onde
/// o arquivo e o formato foram escolhidos.
class _QuickConvertDialog extends StatefulWidget {
  const _QuickConvertDialog({required this.video, required this.format});

  final VideoInfo video;
  final QuickConvertFormat format;

  @override
  State<_QuickConvertDialog> createState() => _QuickConvertDialogState();
}

class _QuickConvertDialogState extends State<_QuickConvertDialog> {
  final _ffmpeg = FfmpegService();
  static const _output = OutputService();

  _ConvertPhase _phase = _ConvertPhase.converting;
  double _progress = 0;
  bool _cancelling = false;

  File? _file;
  String? _error;
  String? _errorLogs;

  bool _saving = false;
  bool _saved = false;
  String? _saveError;

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
      setState(() {
        _file = file;
        _phase = _ConvertPhase.done;
      });
    } on FfmpegException catch (e) {
      if (!mounted) return;
      // Cancelar faz o FFmpeg falhar de propósito: aí o popup só fecha.
      if (_cancelling) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = e.message;
        _errorLogs = e.logs.trim().isEmpty ? null : e.logs;
        _phase = _ConvertPhase.failed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Algo deu errado durante a conversão.';
        _phase = _ConvertPhase.failed;
      });
    }
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    await _ffmpeg.cancel();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _output.saveToGallery(
        _file!,
        asVideo: !widget.format.isAnimatedImage,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
    } on OutputException catch (e) {
      if (!mounted) return;
      // Dentro de um popup o SnackBar sairia atrás do véu do diálogo, por
      // isso o aviso vem aqui no corpo. O sucesso não precisa de aviso: o
      // próprio botão passa a dizer "Salvo na galeria".
      setState(() {
        _saving = false;
        _saveError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // Durante a conversão o "voltar" do sistema não fecha o popup: parar
      // é pelo botão Cancelar, que também encerra o FFmpeg.
      canPop: _phase != _ConvertPhase.converting,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        // A fase de resultado tem cartão e três botões: em tela baixa, ou
        // com fonte grande do sistema, precisa rolar em vez de estourar.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (_phase) {
              _ConvertPhase.converting => _converting(theme),
              _ConvertPhase.failed => _failed(theme),
              _ConvertPhase.done => _done(theme),
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _converting(ThemeData theme) {
    final percent = (_progress * 100).clamp(0, 100).round();

    return [
      Center(
        child: SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  // Sem progresso ainda, roda indefinido em vez de fingir 0%.
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
      ),
      const SizedBox(height: 28),
      Text(
        _cancelling ? 'Cancelando…' : 'Convertendo para ${widget.format.label}',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 20),
      TextButton.icon(
        onPressed: _cancelling ? null : _cancel,
        icon: const Icon(Icons.close),
        label: const Text('Cancelar'),
      ),
    ];
  }

  List<Widget> _failed(ThemeData theme) {
    return [
      Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
      const SizedBox(height: 16),
      Text(
        'Não deu certo',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      if (_errorLogs != null)
        TextButton(
          onPressed: () => _showLogs(context),
          child: const Text('Ver detalhes técnicos'),
        ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Fechar'),
      ),
    ];
  }

  List<Widget> _done(ThemeData theme) {
    final scheme = theme.colorScheme;
    final bytes = _file!.lengthSync();

    return [
      Text(
        '${widget.format.label} pronto',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 52,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              SizeEstimate.formatBytes(bytes),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.format.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      if (_saveError != null) ...[
        const SizedBox(height: 14),
        Text(
          _saveError!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
        ),
      ],
      const SizedBox(height: 20),
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
          _file!,
          mimeType: widget.format.mimeType,
          text: '${widget.format.label} feito com o app Video to GIF',
        ),
        icon: const Icon(Icons.share_outlined),
        label: const Text('Compartilhar'),
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Fechar'),
      ),
    ];
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
