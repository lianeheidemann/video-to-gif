import 'package:flutter/material.dart';

/// Diálogo de uma caixa de texto só. Devolve o texto digitado pelo
/// `Navigator.pop`, ou `null` quando a pessoa cancela.
class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    super.key,
    required this.initial,
    this.title = 'Texto',
    this.maxLines = 3,
  });

  final String initial;

  /// Título do diálogo — o mesmo campo serve para escrever um texto da
  /// montagem e para nomear/renomear uma pasta de stickers.
  final String title;
  final int maxLines;

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    // Num campo de uma linha só (nome de pasta), a tecla de confirmar do
    // teclado deve valer o mesmo que o botão "OK" — sem isso, ela só fecha o
    // teclado e a pessoa acha que confirmou sem ter confirmado nada.
    final singleLine = widget.maxLines == 1;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        textInputAction: singleLine ? TextInputAction.done : null,
        onSubmitted: singleLine ? (_) => _submit() : null,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}

/// Miniatura "Aa" de uma fonte, renderizada na própria [family] — mesma
/// forma de miniatura em grade usada por [_bundledStickerThumb].
