import 'package:flutter/material.dart';

/// Card de configuração resumido e expansível.
class LabeledSection extends StatelessWidget {
  const LabeledSection({
    super.key,
    required this.title,
    required this.child,
    this.value,
    this.originalValue,
    this.hint,
    this.tip,
    this.icon,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? value;

  /// Valor do vídeo original, mostrado antes do valor selecionado para
  /// que o usuário compare o que vai mudar na conversão.
  final String? originalValue;
  final String? hint;
  final String? tip;
  final IconData? icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: icon == null
            ? null
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 21, color: theme.colorScheme.primary),
              ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: (value == null && originalValue == null)
            ? null
            : Row(
                children: [
                  if (originalValue != null) ...[
                    Flexible(
                      child: Text(
                        originalValue!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (value != null)
                    Flexible(
                      child: Text(
                        value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
        children: [
          if (hint != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hint!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          child,
          if (tip != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 17,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lista de opções em chips selecionáveis (só uma ativa por vez), com um
/// ícone de check na opção selecionada. Opções que [isEnabled] rejeita
/// aparecem esmaecidas e não podem ser tocadas — usado para opções que
/// excedem uma configuração do vídeo original (ex.: FPS ou resolução
/// maiores que os do arquivo importado).
class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.isEnabled,
  });

  final List<T> options;
  final T selected;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onSelected;
  final bool Function(T)? isEnabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((option) {
        final isSelected = option == selected;
        final enabled = isEnabled?.call(option) ?? true;
        return ChoiceChip(
          label: Text(labelBuilder(option)),
          // Compacto de propósito: são chips que só carregam um número ou
          // uma palavra curta (proporção, resolução, fps...), e o padding
          // padrão do Material sobrava em cada um deles.
          visualDensity: VisualDensity.compact,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          selected: isSelected,
          showCheckmark: true,
          onSelected: enabled ? (_) => onSelected(option) : null,
          avatar: isSelected ? const Icon(Icons.check, size: 14) : null,
        );
      }).toList(),
    );
  }
}
