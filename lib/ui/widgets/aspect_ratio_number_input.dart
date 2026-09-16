import 'package:flutter/material.dart';

/// Campos "Largura : Altura" com um botão de confirmar, para digitar uma
/// proporção customizada — usado pelo chip "x:y" tanto na Montagem quanto na
/// aba "Recorte" da edição de imagem, para as duas telas oferecerem
/// exatamente o mesmo jeito de digitar uma proporção fora dos presets.
class CustomAspectRatioInput extends StatefulWidget {
  const CustomAspectRatioInput({super.key, required this.onApply});

  final ValueChanged<double> onApply;

  @override
  State<CustomAspectRatioInput> createState() => _CustomAspectRatioInputState();
}

class _CustomAspectRatioInputState extends State<CustomAspectRatioInput> {
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _apply() {
    final w = double.tryParse(_widthController.text.replaceAll(',', '.'));
    final h = double.tryParse(_heightController.text.replaceAll(',', '.'));
    if (w == null || h == null || w <= 0 || h <= 0) return;
    widget.onApply(w / h);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _widthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Largura',
              hintText: 'X',
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('：', style: theme.textTheme.titleMedium),
        ),
        Expanded(
          child: TextField(
            controller: _heightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Altura',
              hintText: 'Y',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Aplicar proporção',
          onPressed: _apply,
          icon: const Icon(Icons.check_rounded),
        ),
      ],
    );
  }
}
