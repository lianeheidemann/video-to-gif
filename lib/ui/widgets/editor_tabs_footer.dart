import 'package:flutter/material.dart';

import 'labeled_section.dart';

/// Uma opção do rodapé de abas: o ícone e o rótulo que aparecem na barra, o
/// valor atual mostrado no cabeçalho do painel e o conteúdo do painel em si
/// (construído só quando a aba está aberta — seções pesadas, como as
/// miniaturas de moldura, não custam nada enquanto estão fechadas).
class EditorSection {
  const EditorSection({
    required this.icon,
    required this.title,
    required this.builder,
    this.value,
    this.label,
  });

  final IconData icon;
  final String title;

  /// Rótulo curto da barra; sem ele, vale o [title].
  final String? label;

  /// Valor atual, mostrado à direita no cabeçalho do painel (o mesmo resumo
  /// que os cards expansíveis mostravam antes de virar aba).
  final String? value;

  final WidgetBuilder builder;

  /// Converte uma seção que já existia como card expansível ([LabeledSection])
  /// em aba do rodapé: o ícone, o título e o valor viram a barra e o
  /// cabeçalho do painel, e o corpo do card vira o conteúdo do painel — sem
  /// reescrever nenhuma seção.
  factory EditorSection.fromLabeled(LabeledSection section, {String? label}) =>
      EditorSection(
        icon: section.icon ?? Icons.tune_rounded,
        title: section.title,
        value: section.value,
        label: label,
        builder: (_) => section.child,
      );

  String get barLabel => label ?? title;
}

/// Rodapé de abas no formato que a tela de montagem usa: uma barra que rola
/// na horizontal e, acima dela, o painel da aba aberta (com altura máxima e
/// rolagem própria, para uma seção longa não empurrar a prévia para fora da
/// tela). Tocar de novo na aba aberta fecha o painel e devolve o espaço para
/// a prévia.
class EditorTabsFooter extends StatefulWidget {
  const EditorTabsFooter({
    super.key,
    required this.sections,
    required this.activeIndex,
    required this.onSelected,
    this.maxPanelHeight = 200,
  });

  final List<EditorSection> sections;

  /// `null` = nenhuma aba aberta (só a barra).
  final int? activeIndex;
  final ValueChanged<int?> onSelected;

  /// Teto do painel. Baixo de propósito: o painel já rola sozinho, então o
  /// que passa daqui continua acessível arrastando — e a prévia, que é o que
  /// a pessoa está olhando enquanto mexe nos controles, fica com o resto da
  /// tela. Com 200, "Resolução" mostra as duas primeiras linhas de chips (a
  /// terceira aparece pela metade, indicando que há mais) e "Qualidade das
  /// cores" mostra as três opções de paleta.
  final double maxPanelHeight;

  @override
  State<EditorTabsFooter> createState() => _EditorTabsFooterState();
}

class _EditorTabsFooterState extends State<EditorTabsFooter> {
  /// `true` com o painel encolhido para só a alça. Recolher não é fechar: a
  /// aba continua aberta, o que importa nas telas em que o conteúdo da
  /// prévia responde a toque enquanto os controles estão à mostra.
  bool _collapsed = false;

  @override
  void didUpdateWidget(EditorTabsFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Abrir ou trocar de aba sempre mostra o conteúdo.
    if (oldWidget.activeIndex != widget.activeIndex) _collapsed = false;
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.activeIndex;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (activeIndex != null && activeIndex < widget.sections.length)
          _panel(context, widget.sections[activeIndex]),
        _bar(context),
      ],
    );
  }

  /// Alça no topo do painel: puxar para baixo encolhe até só ela, puxar para
  /// cima traz os controles de volta, e tocar alterna os dois — a prévia fica
  /// com quase toda a tela sem perder a aba aberta.
  Widget _dragHandle(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _collapsed = !_collapsed),
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity;
        if (velocity == null || velocity == 0) return;
        setState(() => _collapsed = velocity > 0);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, EditorSection section) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(maxHeight: widget.maxPanelHeight),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dragHandle(context),
            if (!_collapsed)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      editorPanelHeader(context, section.title, section.value),
                      section.builder(context),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          for (var i = 0; i < widget.sections.length; i++)
            _tabButton(context, i, widget.sections[i]),
        ],
      ),
    );
  }

  Widget _tabButton(BuildContext context, int index, EditorSection section) {
    final theme = Theme.of(context);
    final selected = widget.activeIndex == index;
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => widget.onSelected(selected ? null : index),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(section.icon, color: color),
            const SizedBox(height: 4),
            Text(
              section.barLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Título + valor atual no topo de um painel de aba — o mesmo resumo que o
/// card expansível mostrava no cabeçalho antes de a seção virar aba.
Widget editorPanelHeader(BuildContext context, String title, [String? value]) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (value != null)
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    ),
  );
}
