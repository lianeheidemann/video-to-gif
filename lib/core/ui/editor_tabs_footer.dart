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

  /// `true` quando a tira da alça está encostada na barra de abas — painel
  /// aberto, mas recolhido. Nesse caso as duas viram um bloco só: a tira
  /// empresta a cor da barra e fica com a única borda de cima.
  ///
  /// Antes cada uma trazia cor e borda próprias, e recolhido isso desenhava
  /// duas linhas paralelas a 17px uma da outra, com uma faixa de outro tom
  /// entre elas — lia-se como falha de renderização, não como parte do
  /// controle.
  bool get _handleTopsTheBar {
    final index = widget.activeIndex;
    return _collapsed && index != null && index < widget.sections.length;
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = widget.activeIndex;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        collapsibleEditorPanel(
          child: activeIndex != null && activeIndex < widget.sections.length
              ? _panel(context, widget.sections[activeIndex])
              : null,
        ),
        _bar(context),
      ],
    );
  }

  /// A linha que separa o rodapé da prévia. Só uma por vez desenha: com o
  /// painel recolhido ela é da tira da alça, senão é da barra.
  BorderSide _topLine(ThemeData theme) => BorderSide(
    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
  );

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
        padding: const EdgeInsets.symmetric(vertical: 6),
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
      // Recolher pela alça e trocar de aba: o painel continua montado e só
      // muda de altura. Abrir e fechar são do `collapsibleEditorPanel`.
      duration: editorPanelMotionDuration,
      curve: editorPanelMotionCurve,
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(maxHeight: widget.maxPanelHeight),
        decoration: BoxDecoration(
          color: _handleTopsTheBar
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainerLow,
          border: Border(top: _topLine(theme)),
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
                      editorPanelValueLine(context, section.value),
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
      height: 60,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        // Recolhido, quem desenha a linha de cima é a tira da alça.
        border: _handleTopsTheBar ? null : Border(top: _topLine(theme)),
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
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(section.icon, size: 20, color: color),
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

/// Duração e curva de todo movimento do rodapé: abrir, fechar, trocar de aba
/// e recolher pela alça.
///
/// A curva é simétrica de propósito — abrir e fechar ganham o mesmo caráter.
/// Um `easeOut` puro fica bom abrindo e abrupto no começo do fechamento. E o
/// padrão do `AnimatedSize` é [Curves.linear], que arranca em velocidade cheia
/// e para seco: é o que fazia a transição parecer mecânica.
const Duration editorPanelMotionDuration = Duration(milliseconds: 240);
const Curve editorPanelMotionCurve = Curves.easeInOutCubic;

/// Dá movimento ao abrir e fechar do painel de uma aba. [child] nulo é nenhuma
/// aba aberta.
///
/// Precisa ficar sempre montado: quem troca é o filho, não este widget. Antes
/// o painel inteiro entrava e saía da árvore com a aba, e nada animava —
/// aparecia e sumia num quadro só.
///
/// É [AnimatedSwitcher], e não [AnimatedSize] com um filho vazio, porque o
/// switcher mantém o painel que está saindo vivo durante a transição: ele
/// desliza e desaparece junto com a altura. Com o filho vazio, o conteúdo
/// sumiria num quadro e sobraria uma caixa colorida encolhendo — o salto
/// mudaria de lugar em vez de sumir.
///
/// Trocar de aba não passa por aqui: dois painéis são do mesmo tipo e sem
/// chave, então o switcher os atualiza no lugar e quem anima a diferença de
/// altura é o [AnimatedSize] de dentro do painel.
Widget collapsibleEditorPanel({required Widget? child}) {
  return AnimatedSwitcher(
    // Chave estável: é por ela que o teste mede a altura no meio da
    // transição, que é o que distingue movimento de salto.
    key: const ValueKey('painelDaAba'),
    duration: editorPanelMotionDuration,
    switchInCurve: editorPanelMotionCurve,
    switchOutCurve: editorPanelMotionCurve,
    layoutBuilder: (atual, anteriores) => Stack(
      alignment: Alignment.bottomCenter,
      children: [...anteriores, ?atual],
    ),
    transitionBuilder: (filho, animacao) => SizeTransition(
      sizeFactor: animacao,
      // Ancorado no topo: o painel cresce para baixo, contra a barra de abas,
      // em vez de se abrir a partir do meio.
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: animacao, child: filho),
    ),
    child: child ?? const SizedBox(key: ValueKey('rodapeSemAba')),
  );
}

/// Valor atual de uma aba, alinhado à direita — sem repetir o nome da aba:
/// a própria aba do rodapé já fica marcada em cor diferente e em negrito
/// quando selecionada (`_tabButton`), então escrevê-lo de novo aqui só
/// custava espaço vertical num painel com teto de 200px (mesma economia já
/// feita para a tela de Montagem, que tem seu próprio rodapé em
/// `collage_page.dart`). `null` (a maioria das abas, que não tem um valor
/// de resumo) não desenha nada.
Widget editorPanelValueLine(BuildContext context, [String? value]) {
  if (value == null) return const SizedBox.shrink();
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    ),
  );
}
