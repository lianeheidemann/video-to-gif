import 'package:flutter/material.dart';

import '../../app/preview_background_controller.dart';

/// Conteúdo da aba "Ajustes" (ícone de engrenagem, sempre a última da barra)
/// nas três telas de edição — hoje só a preferência do fundo quadriculado da
/// prévia, mas é o lugar para outras configurações gerais no futuro.
class PreviewSettingsPanel extends StatelessWidget {
  const PreviewSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: previewCheckerboardNotifier,
      builder: (context, enabled, _) => Row(
        children: [
          Expanded(
            child: Text(
              'Fundo quadriculado na prévia',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Switch(value: enabled, onChanged: setPreviewCheckerboardEnabled),
        ],
      ),
    );
  }
}
