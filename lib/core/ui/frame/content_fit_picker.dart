import 'package:flutter/material.dart';

import '../../models/frame_settings.dart';

/// Ladrilho de um modo de encaixe do conteúdo na moldura de imagem. O modo
/// "Preencher" (expand) abre o slider de zoom quando está selecionado.
class ContentFitTile extends StatelessWidget {
  const ContentFitTile({
    super.key,
    required this.mode,
    required this.selected,
    required this.onSelected,
    this.zoomRow,
  });

  final ContentFitMode mode;
  final bool selected;
  final ValueChanged<ContentFitMode> onSelected;

  /// Slider de zoom mostrado dentro do ladrilho selecionado de "Preencher".
  final Widget? zoomRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showZoom =
        selected && mode == ContentFitMode.expand && zoomRow != null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            key: ValueKey('contentFitTile_${mode.name}'),
            onTap: () => onSelected(mode),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: ContentFitTileHeader(mode: mode, selected: selected),
            ),
          ),
          if (showZoom)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                  ),
                  const SizedBox(height: 12),
                  zoomRow!,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Cabeçalho do ladrilho: ícone, nome do modo e a marca de selecionado.
class ContentFitTileHeader extends StatelessWidget {
  const ContentFitTileHeader({
    super.key,
    required this.mode,
    required this.selected,
  });

  final ContentFitMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            contentFitIcon(mode),
            size: 16,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            mode.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (selected)
          Icon(
            Icons.check_circle_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
      ],
    );
  }
}

IconData contentFitIcon(ContentFitMode mode) => switch (mode) {
  ContentFitMode.auto => Icons.auto_fix_high_rounded,
  ContentFitMode.fill => Icons.crop_free_rounded,
  ContentFitMode.fit => Icons.fit_screen_rounded,
  ContentFitMode.expand => Icons.open_in_full_rounded,
};
