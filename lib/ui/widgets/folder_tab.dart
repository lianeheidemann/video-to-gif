import 'package:flutter/material.dart';

/// Contorno em forma de pasta: retângulo arredondado com uma abinha no canto
/// superior esquerdo, como o ícone de pasta de um gerenciador de arquivos.
/// Escrito como [ShapeBorder] (e não como um `CustomPainter` solto) para o
/// preenchimento, o contorno e o respingo de toque seguirem exatamente o
/// mesmo caminho — é o que `ShapeDecoration`/`Material.shape` esperam.
class FolderTabShape extends ShapeBorder {
  const FolderTabShape({
    this.radius = 10,
    this.tabHeight = 8,
    this.tabWidthRatio = 0.42,
    this.side = BorderSide.none,
  });

  /// Arredondamento dos cantos do corpo e da ponta da abinha.
  final double radius;

  /// Altura da abinha, medida acima do corpo da pasta.
  final double tabHeight;

  /// Largura da abinha como fração da largura total — uma fração (e não uma
  /// medida fixa) mantém a proporção da pasta em rótulos curtos ("Efeitos")
  /// e longos ("Importados") sem a abinha parecer sobrando ou espremida.
  final double tabWidthRatio;

  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(top: tabHeight);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Rect.fromLTRB(
      rect.left,
      rect.top + tabHeight,
      rect.right,
      rect.bottom,
    );
    final r = Radius.circular(radius);
    final tabWidth = (rect.width * tabWidthRatio).clamp(
      radius * 4,
      rect.width * 0.7,
    );
    // A abinha é um retângulo baixinho encostado no topo esquerdo do corpo,
    // com os dois cantos de cima arredondados; a união com o corpo apaga a
    // emenda entre os dois, deixando um contorno só.
    final tab = RRect.fromLTRBAndCorners(
      body.left,
      rect.top,
      body.left + tabWidth,
      body.top + radius,
      topLeft: r,
      topRight: r,
    );
    return Path.combine(
      PathOperation.union,
      Path()..addRRect(RRect.fromRectAndRadius(body, r)),
      Path()..addRRect(tab),
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawPath(
      getOuterPath(rect, textDirection: textDirection),
      side.toPaint(),
    );
  }

  @override
  ShapeBorder scale(double t) => FolderTabShape(
    radius: radius * t,
    tabHeight: tabHeight * t,
    tabWidthRatio: tabWidthRatio,
    side: side.scale(t),
  );
}

/// Uma pasta da barra da aba "Stickers" — as embutidas, as criadas pelo
/// usuário e o botão de criar uma nova (esse com [icon] no lugar do rótulo).
/// Selecionada fica preenchida de roxo; solta, só com o contorno.
class FolderTab extends StatelessWidget {
  const FolderTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Segurar abre o menu de renomear/apagar — só as pastas criadas pelo
  /// usuário passam algo aqui.
  final VoidCallback? onLongPress;

  /// Quando presente, aparece antes do rótulo (usado pelo botão de criar
  /// pasta, que mostra o ícone e o texto "Nova pasta").
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      shape: FolderTabShape(
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          // O respiro de cima soma a altura da abinha (a `FolderTabShape`
          // reserva ela em `dimensions`), para o rótulo ficar centralizado no
          // corpo da pasta e não colado na aba.
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
