import 'package:flutter/material.dart';

import '../../models/collage_layout.dart';

/// Painel da aba "Layout": as miniaturas dos arranjos e, para os arranjos que
/// aceitam, os contadores de linhas/colunas.
///
/// Só conhece o layout atual — quem recalcula as células e empilha o desfazer
/// é a tela, por [onSelectKind] e [onApplyLayout].
class CollageLayoutPanel extends StatelessWidget {
  const CollageLayoutPanel({
    super.key,
    required this.layout,
    required this.onSelectKind,
    required this.onApplyLayout,
  });

  final CollageLayout layout;
  final ValueChanged<CollageLayoutKind> onSelectKind;
  final ValueChanged<CollageLayout> onApplyLayout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: CollageLayoutKind.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) =>
                _layoutThumb(context, CollageLayoutKind.values[index]),
          ),
        ),
        if (layout.kind == CollageLayoutKind.freeGrid) ...[
          const SizedBox(height: 14),
          _freeGridSteppers(context),
        ],
        if (layout.kind == CollageLayoutKind.row ||
            layout.kind == CollageLayoutKind.column) ...[
          const SizedBox(height: 14),
          _rowColumnStepper(context),
        ],
      ],
    );
  }

  Widget _layoutThumb(BuildContext context, CollageLayoutKind kind) {
    final theme = Theme.of(context);
    final selected = layout.kind == kind;
    return GestureDetector(
      onTap: () => onSelectKind(kind),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 72,
              height: 56,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: selected ? 2 : 1,
                ),
              ),
              child: _layoutIcon(context, kind, theme.colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text(
              kind.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  /// Ícone de cada opção de layout: uma grade de pontinhos desenhada com o
  /// número EXATO de colunas/linhas de cada uma — em vez de escolher entre
  /// os ícones prontos do Material (nenhum bate exatamente com "2 colunas
  /// por 3 linhas", por exemplo; `Icons.grid_on_outlined` usado antes para
  /// "Grade 2x3" na real parece uma grade 3x3, confundindo com a opção
  /// vizinha), garante que o ícone sempre corresponda ao layout real.
  Widget _layoutIcon(
    BuildContext context,
    CollageLayoutKind kind,
    Color color,
  ) {
    final (columns, rows) = switch (kind) {
      CollageLayoutKind.row => (4, 1),
      CollageLayoutKind.column => (1, 4),
      CollageLayoutKind.grid2x2 => (2, 2),
      CollageLayoutKind.grid2x3 => (2, 3),
      CollageLayoutKind.grid3x3 => (3, 3),
      CollageLayoutKind.freeGrid => (0, 0),
    };
    if (kind == CollageLayoutKind.freeGrid) {
      return Icon(Icons.dashboard_customize_outlined, color: color);
    }
    const dot = 6.0;
    const gap = 3.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: gap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _freeGridSteppers(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _stepperRow(
            context,
            'Colunas',
            layout.columns < 1 ? 2 : layout.columns,
            min: CollageLayout.minFreeGridSpan,
            max: CollageLayout.maxFreeGridSpan,
            onChanged: (v) => onApplyLayout(layout.copyWith(columns: v)),
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          child: _stepperRow(
            context,
            'Linhas',
            layout.rows < 1 ? 2 : layout.rows,
            min: CollageLayout.minFreeGridSpan,
            max: CollageLayout.maxFreeGridSpan,
            onChanged: (v) => onApplyLayout(layout.copyWith(rows: v)),
          ),
        ),
      ],
    );
  }

  /// Contador de quantas fotos entram na linha/coluna única — mesmo padrão
  /// visual de [_freeGridSteppers], só que controlando o total de células em
  /// vez de colunas/linhas separadas (linha/coluna só tem um eixo com mais
  /// de uma célula).
  Widget _rowColumnStepper(BuildContext context) {
    final count = layout.cellCount < CollageLayout.minRowColumnCount
        ? CollageLayout.minRowColumnCount
        : layout.cellCount;
    return _stepperRow(
      context,
      'Fotos',
      count,
      min: CollageLayout.minRowColumnCount,
      max: CollageLayout.maxRowColumnCount,
      onChanged: (v) => onApplyLayout(
        layout.kind == CollageLayoutKind.row
            ? CollageLayout.row(v)
            : CollageLayout.column(v),
      ),
    );
  }

  Widget _stepperRow(
    BuildContext context,
    String label,
    int value, {
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(
          '$value',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
