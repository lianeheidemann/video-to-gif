import 'package:flutter/material.dart';

/// Casca das miniaturas de moldura: quadrado de 46px com borda, marca de
/// seleção no canto e rótulo embaixo. Serve tanto para os estilos
/// procedurais quanto para as molduras de imagem, nas telas de vídeo e foto.
///
/// A [key] vai no gesto, não no widget, porque os testes procuram a
/// miniatura por `ValueKey` e checam o ícone de confirmação dentro dela.
class FrameThumbShell extends StatelessWidget {
  const FrameThumbShell({
    required Key key,
    required this.label,
    required this.selected,
    required this.padding,
    required this.onTap,
    required this.child,
    this.onLongPress,
  }) : super(key: key);

  final String label;
  final bool selected;
  final EdgeInsets padding;
  final VoidCallback onTap;
  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 46,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  padding: padding,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: child,
                ),
                if (selected)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão de fundo das subseções das telas de moldura.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
