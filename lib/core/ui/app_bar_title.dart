import 'package:flutter/material.dart';

/// Título de `AppBar` que nunca corta com reticências — encolhe a fonte o
/// quanto for preciso para caber (nunca quebra linha, nunca corta), ao
/// contrário do `Text` padrão de um `AppBar`, que trunca com "…" quando o
/// título não cabe ao lado dos ícones de ação.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(text),
  );
}
