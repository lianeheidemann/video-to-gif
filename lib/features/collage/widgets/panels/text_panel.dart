import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/models/collage_text.dart';
import '../../../../core/models/default_colors.dart';
import '../../../../core/ui/color_picker_sheet.dart';
import '../../../../core/ui/panel_rows.dart';

/// Painel da aba "Texto": o campo de escrever (que também edita a caixa
/// trazida pelo lápis da barra de seleção) e, com uma caixa selecionada, cor,
/// fundo, opacidade e arredondamento dela.
///
/// O controller e o foco do campo são da tela, não deste widget: ela os cria
/// no `initState`, descarta no `dispose` e limpa o campo quando o desfazer,
/// o refazer ou a aba Stickers apagam a caixa que estava sendo editada.
///
/// As mudanças saem por [onReplaceText] em vez de montarem as configurações
/// aqui. A folha de cor sobrevive a vários rebuilds e aplica cada cor no
/// momento em que ela é escolhida — um retrato das configurações estaria
/// velho quando a segunda cor chegasse. Pelo mesmo motivo [findText] é uma
/// função, não um valor.
class CollageTextPanel extends StatelessWidget {
  const CollageTextPanel({
    super.key,
    required this.selectedText,
    required this.editingTextId,
    required this.textController,
    required this.textFocus,
    required this.findText,
    required this.onReplaceText,
    required this.onPushUndoCheckpoint,
    required this.onSubmit,
    required this.onCancelEdit,
    required this.previewImageBuilder,
  });

  /// Caixa de texto selecionada agora, ou `null` — os controles de estilo só
  /// aparecem com uma selecionada, porque mexem naquela caixa, não em todas.
  final CollageTextItem? selectedText;

  /// Id da caixa que o lápis trouxe para o campo, ou `null` ao criar uma nova.
  final String? editingTextId;

  final TextEditingController textController;
  final FocusNode textFocus;
  final CollageTextItem? Function(String id) findText;
  final void Function(String id, CollageTextItem item, {bool pushUndo})
  onReplaceText;
  final VoidCallback onPushUndoCheckpoint;
  final VoidCallback onSubmit;
  final VoidCallback onCancelEdit;

  /// Rasteriza a prévia atual para o conta-gotas da folha de cor.
  final Future<ui.Image> Function() previewImageBuilder;

  @override
  Widget build(BuildContext context) {
    final selected = selectedText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textComposer(context),
        // Os controles de estilo só fazem sentido com um texto selecionado —
        // eles mexem naquele texto, não em todos.
        if (selected != null) ...[
          const SizedBox(height: 8),
          PanelColorRow(
            label: 'Cor do texto',
            color: selected.color,
            onTap: () => _pickTextColor(context, selected.id),
          ),
          PanelSwitchRow(
            label: 'Fundo do texto',
            value: selected.hasBackground,
            onChanged: (on) => _toggleTextBackground(selected.id, on),
          ),
          if (selected.hasBackground) ...[
            const SizedBox(height: 4),
            _textBackgroundGroup(context, selected),
          ],
        ],
      ],
    );
  }

  /// Cor/opacidade/arredondamento do fundo do texto, agrupados numa caixa com
  /// destaque à esquerda — deixa claro que os três são sub-opções de "Fundo
  /// do texto" logo acima, então os rótulos aqui dentro não repetem "do
  /// fundo" (a folha de cor, mais longe desse contexto, continua dizendo
  /// "Cor do fundo do texto").
  Widget _textBackgroundGroup(BuildContext context, CollageTextItem selected) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Column(
        children: [
          PanelColorRow(
            label: 'Cor',
            color: selected.backgroundColor!,
            onTap: () => _pickTextBackgroundColor(context, selected.id),
          ),
          const SizedBox(height: 4),
          PanelSliderRow(
            onChangeStart: onPushUndoCheckpoint,
            label: 'Opacidade',
            value: selected.backgroundColor!.a,
            min: 0,
            max: 1,
            valueLabel: '${(selected.backgroundColor!.a * 100).round()}%',
            onChanged: (v) => onReplaceText(
              selected.id,
              selected.copyWith(
                backgroundColor: selected.backgroundColor!.withValues(alpha: v),
              ),
              pushUndo: false,
            ),
          ),
          const SizedBox(height: 4),
          PanelSliderRow(
            onChangeStart: onPushUndoCheckpoint,
            label: 'Arredondamento',
            value: selected.backgroundCornerRatio,
            min: 0,
            max: CollageTextItem.maxBackgroundCornerRatio,
            valueLabel:
                '${(selected.backgroundCornerRatio / CollageTextItem.maxBackgroundCornerRatio * 100).round()}%',
            onChanged: (v) => onReplaceText(
              selected.id,
              selected.copyWith(backgroundCornerRatio: v),
              pushUndo: false,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleTextBackground(String id, bool on) {
    final item = findText(id);
    if (item == null) return;
    onReplaceText(
      id,
      on
          ? item.copyWith(
              backgroundColor: item.backgroundColor ?? defaultBackgroundColor,
            )
          : item.copyWith(clearBackgroundColor: true),
    );
  }

  void _pickTextColor(BuildContext context, String id) => _pickOverlayTextColor(
    context,
    id: id,
    title: 'Cor do texto',
    current: (item) => item.color,
    apply: (item, color) => item.copyWith(color: color),
  );

  void _pickTextBackgroundColor(BuildContext context, String id) =>
      _pickOverlayTextColor(
        context,
        id: id,
        title: 'Cor do fundo do texto',
        current: (item) => item.backgroundColor ?? defaultBackgroundColor,
        apply: (item, color) => item.copyWith(backgroundColor: color),
      );

  /// Mesma folha de cor do resto da montagem (com conta-gotas na prévia),
  /// servindo tanto à cor do texto quanto à do fundo dele — [current]/[apply]
  /// são o que muda entre as duas, no mesmo espírito de [_pickBorderColor].
  void _pickOverlayTextColor(
    BuildContext context, {
    required String id,
    required String title,
    required Color Function(CollageTextItem item) current,
    required CollageTextItem Function(CollageTextItem item, Color color) apply,
  }) {
    final item = findText(id);
    if (item == null) return;
    var checkpointPushed = false;
    showCollageColorPickerSheet(
      context: context,
      title: title,
      initialColor: current(item),
      onColorSelected: (color) {
        final latest = findText(id);
        if (latest == null) return;
        if (!checkpointPushed) {
          checkpointPushed = true;
          onPushUndoCheckpoint();
        }
        onReplaceText(id, apply(latest, color), pushUndo: false);
      },
      previewImageBuilder: previewImageBuilder,
    );
  }

  /// Campo de escrever texto do painel: o botão da ponta cria a caixa (ou
  /// confirma a edição, quando o lápis carregou uma aqui). Escrever direto no
  /// painel evita a janela que existia só para digitar uma frase.
  Widget _textComposer(BuildContext context) {
    final theme = Theme.of(context);
    final editing = editingTextId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              editing ? 'Editar texto' : 'Novo texto',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (editing)
              TextButton(
                onPressed: onCancelEdit,
                child: const Text('Cancelar'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: textController,
          builder: (context, value, _) {
            final canSubmit = value.text.trim().isNotEmpty;
            return TextField(
              controller: textController,
              focusNode: textFocus,
              minLines: 1,
              // Até 3 linhas, o mesmo que o diálogo antigo aceitava — com
              // `TextInputType.multiline` o Enter quebra linha e quem
              // confirma é o botão da ponta.
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: 'Digite seu texto...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                contentPadding: const EdgeInsets.fromLTRB(18, 12, 4, 12),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    tooltip: editing ? 'Salvar texto' : 'Adicionar texto',
                    onPressed: canSubmit ? onSubmit : null,
                    icon: Icon(
                      editing ? Icons.check_rounded : Icons.add_rounded,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: canSubmit
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      foregroundColor: canSubmit
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
