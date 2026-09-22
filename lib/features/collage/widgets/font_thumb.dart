import 'package:flutter/material.dart';

/// Miniatura de uma fonte na folha de escolha de fonte do texto: o nome da
/// família desenhado na própria fonte, com marca de seleção.
class CollageFontThumb extends StatelessWidget {
  const CollageFontThumb({
    super.key,
    required this.family,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.icon,
  });

  final String? family;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Segurar remove — só as fontes importadas passam algo aqui.
  final VoidCallback? onLongPress;

  /// No lugar do "Aa": usado pelo tile de importar, que não tem fonte para
  /// mostrar ainda.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 22, color: theme.colorScheme.primary)
            else
              Text('Aa', style: TextStyle(fontFamily: family, fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
