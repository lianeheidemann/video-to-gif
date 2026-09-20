import 'package:flutter/material.dart';

import '../../models/size_estimate.dart';
import '../../models/video_info.dart';

/// Cartão com as informações do arquivo de entrada — nome, selo da extensão,
/// resolução, duração, FPS e tamanho.
///
/// Fica na tela "Converter formato", que mostra e atualiza este cartão no
/// lugar a cada arquivo escolhido. É público (e não privado à tela) para ter
/// teste de widget próprio: o estado "com arquivo" da tela depende de um
/// `probe()` de verdade, que não roda em `flutter test`.
class SourceFileCard extends StatelessWidget {
  const SourceFileCard({
    super.key,
    required this.video,
    required this.extension,
  });

  final VideoInfo video;

  /// Extensão do arquivo escolhido (sem o ponto, minúscula), já calculada
  /// pela tela — mesmo valor usado para desmarcar o formato de saída igual
  /// ao de origem. Aqui só vira o selo "GIF"/"MP4"/etc. ao lado do nome.
  final String extension;

  /// Duração em texto curto: acima de um minuto vira "1min 5s"; abaixo,
  /// "6.0s", que é a precisão que interessa em vídeo curto.
  String get _duration {
    final minutes = video.durationSeconds ~/ 60;
    final seconds = (video.durationSeconds % 60).round();
    return minutes > 0
        ? '${minutes}min ${seconds}s'
        : '${video.durationSeconds.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detailStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

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
                  // `width`/`height` já vêm com a rotação aplicada, então
                  // vídeo de celular gravado em pé aparece em pé aqui.
                  Text(
                    '${video.width} × ${video.height} px • $_duration',
                    style: detailStyle,
                  ),
                  Text(
                    '${video.frameRate.round()} FPS • '
                    '${SizeEstimate.formatBytes(video.fileSizeBytes)}',
                    style: detailStyle,
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
