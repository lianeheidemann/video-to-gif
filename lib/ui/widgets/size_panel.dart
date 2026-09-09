import 'package:flutter/material.dart';

import '../../models/size_estimate.dart';
import '../../theme.dart';

/// Painel final do editor: compara o peso do vídeo original com a
/// estimativa do GIF e traz a ação de recalcular. Converter é feito pelo
/// botão de download na AppBar — este painel não duplica mais essa ação.
class SizePanel extends StatelessWidget {
  const SizePanel({
    super.key,
    required this.estimate,
    required this.originalBytes,
    required this.summary,
    required this.measuring,
    required this.onMeasure,
  });

  final SizeEstimate estimate;

  /// Tamanho em bytes do vídeo original, mostrado ao lado da estimativa do
  /// GIF para o usuário comparar o antes e o depois.
  final int originalBytes;
  final String summary;
  final bool measuring;
  final VoidCallback onMeasure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = verdictColor(estimate.verdict, theme.colorScheme);
    final calibrated = estimate.confidence == EstimateConfidence.calibrated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Icon(Icons.data_usage_rounded, color: color, size: 19),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Estimativa de tamanho',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      SizeEstimate.formatBytes(originalBytes),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    Text(
                      estimate.formatted,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: color.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Text(
                        _verdictLabel(estimate.verdict),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Faixa e resumo das configurações num único texto — eram
                // duas linhas separadas antes, só para caber a mesma
                // informação num painel mais compacto.
                Text(
                  '${calibrated ? 'Faixa medida' : 'Faixa provável'}: '
                  '${estimate.formattedRange} · $summary',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ImpactBar(verdict: estimate.verdict),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  onPressed: measuring ? null : onMeasure,
                  icon: measuring
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(measuring ? 'Medindo…' : 'Recalcular'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Rótulo curto do veredito, usado no selo ao lado do tamanho.
  static String _verdictLabel(SizeVerdict verdict) => switch (verdict) {
    SizeVerdict.light => 'Leve',
    SizeVerdict.good => 'Moderado',
    SizeVerdict.heavy || SizeVerdict.tooHeavy => 'Pesado',
  };
}

/// Barra contínua "leve → moderado → pesado" com um marcador indicando
/// onde o veredito atual cai.
class _ImpactBar extends StatelessWidget {
  const _ImpactBar({required this.verdict});

  final SizeVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = switch (verdict) {
      SizeVerdict.light => 0.16,
      SizeVerdict.good => 0.5,
      SizeVerdict.heavy => 0.78,
      SizeVerdict.tooHeavy => 0.94,
    };

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const markerSize = 18.0;

            return SizedBox(
              height: markerSize,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: const Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 8,
                            child: ColoredBox(color: Color(0xFF58C78C)),
                          ),
                        ),
                        Expanded(
                          child: SizedBox(
                            height: 8,
                            child: ColoredBox(color: Color(0xFFB8B36A)),
                          ),
                        ),
                        Expanded(
                          child: SizedBox(
                            height: 8,
                            child: ColoredBox(color: Color(0xFFE57373)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: (constraints.maxWidth - markerSize) * position,
                    child: Container(
                      width: markerSize,
                      height: markerSize,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 3,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        const Row(
          children: [
            Expanded(
              child: Text(
                'Leve',
                style: TextStyle(
                  color: Color(0xFF58C78C),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Moderado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFB8B36A),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Pesado',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: Color(0xFFE57373),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
