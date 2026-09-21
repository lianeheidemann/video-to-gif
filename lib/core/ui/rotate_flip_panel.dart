import 'package:flutter/material.dart';

import '../models/output_transform.dart';

/// Painel da aba "Girar": dois botões de rotação e dois de espelhamento, dois
/// a dois numa linha.
///
/// Sem rótulos de seção acima dos pares — os nomes dos botões já dizem o que
/// cada um faz, e a aba do rodapé já se chama "Girar".
class RotateFlipPanel extends StatelessWidget {
  const RotateFlipPanel({
    super.key,
    required this.transform,
    required this.onChanged,
  });

  final OutputTransform transform;
  final ValueChanged<OutputTransform> onChanged;

  /// Só o padding: serve tanto ao contornado quanto ao preenchido (os de
  /// espelhar trocam de tipo quando estão ligados), então não pode carregar
  /// nada específico de um dos dois.
  ///
  /// Os quatro botões ficam dois a dois numa linha, então cada um tem menos
  /// da metade da largura da tela. Com o padding padrão sobrava tão pouco
  /// espaço que "90° à esquerda" quebrava em três linhas num celular
  /// estreito — e até "Horizontal" quebrava em duas, mesmo num de 412dp.
  static const _buttonStyle = ButtonStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
  );

  /// Rótulo travado em uma linha. O `FittedBox` encolhe a fonte só quando
  /// ainda assim não couber (texto do sistema aumentado), em vez de cortar a
  /// palavra com reticências.
  static Widget _label(String text) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(text, maxLines: 1),
  );

  Widget _flipButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) => selected
      ? FilledButton.tonalIcon(
          onPressed: onTap,
          style: _buttonStyle,
          icon: Icon(icon),
          label: _label(label),
        )
      : OutlinedButton.icon(
          onPressed: onTap,
          style: _buttonStyle,
          icon: Icon(icon),
          label: _label(label),
        );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onChanged(transform.rotatedBy(-1)),
                style: _buttonStyle,
                icon: const Icon(Icons.rotate_left_rounded),
                label: _label('90° à esquerda'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onChanged(transform.rotatedBy(1)),
                style: _buttonStyle,
                icon: const Icon(Icons.rotate_right_rounded),
                label: _label('90° à direita'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _flipButton(
                label: 'Horizontal',
                icon: Icons.swap_horiz_rounded,
                selected: transform.flipHorizontal,
                onTap: () => onChanged(
                  transform.copyWith(flipHorizontal: !transform.flipHorizontal),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _flipButton(
                label: 'Vertical',
                icon: Icons.swap_vert_rounded,
                selected: transform.flipVertical,
                onTap: () => onChanged(
                  transform.copyWith(flipVertical: !transform.flipVertical),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Aplica [transform] a um widget: gira e depois espelha, a mesma ordem que
/// a exportação usa.
///
/// `RotatedBox` em vez de `Transform.rotate` de propósito — ele troca as
/// dimensões no layout, então o que está em volta já reserva o espaço certo
/// para a mídia girada.
Widget applyOutputTransform(OutputTransform transform, Widget child) {
  var result = child;
  if (transform.quarterTurns != 0) {
    result = RotatedBox(quarterTurns: transform.quarterTurns, child: result);
  }
  if (transform.flipHorizontal || transform.flipVertical) {
    result = Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(
        transform.flipHorizontal ? -1.0 : 1.0,
        transform.flipVertical ? -1.0 : 1.0,
        1.0,
      ),
      child: result,
    );
  }
  return result;
}
