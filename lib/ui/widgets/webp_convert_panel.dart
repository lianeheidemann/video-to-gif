import 'package:flutter/material.dart';

/// Painel final do editor quando o formato escolhido é WebP — equivalente
/// ao [SizePanel] usado para GIF, mas sem a estimativa calibrada: o modelo
/// de tamanho em `size_estimator.dart` é específico da paleta/LZW do GIF e
/// não se aplica ao encoder `libwebp` (cor cheia, sem paleta). Em vez de
/// mostrar um número que seria só um palpite do modelo errado, o painel
/// avisa que a estimativa não está disponível e vai direto ao botão de
/// converter.
class WebpConvertPanel extends StatelessWidget {
  const WebpConvertPanel({
    super.key,
    required this.summary,
    required this.onConvert,
  });

  final String summary;
  final VoidCallback onConvert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pronto para converter',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'A estimativa de tamanho ainda não está disponível para '
                  'WebP nesta versão — o peso final aparece na tela de '
                  'resultado, logo após a conversão.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onConvert,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Converter em WebP'),
        ),
      ],
    );
  }
}
