import 'package:flutter/material.dart';

import '../../models/crop_rect.dart';

/// Faixa com o tamanho atual da janela de recorte, acima dos campos
/// numéricos. Compartilhada pelas telas de vídeo, foto e SVG.
class CropSizeSummary extends StatelessWidget {
  const CropSizeSummary({
    super.key,
    required this.crop,
    this.showPixelUnit = false,
  });

  final CropRect crop;

  /// A tela de vídeo escreve "1280×720 px"; foto e SVG, só "1280×720".
  final bool showPixelUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.aspect_ratio_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Janela de recorte',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${crop.width}×${crop.height}${showPixelUnit ? ' px' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campos numéricos de largura/altura do recorte, sincronizados com o estado
/// atual enquanto não estão em foco — sincronizar com o campo em foco
/// atrapalharia a digitação e jogaria o cursor para o fim a cada tecla.
///
/// Os controllers e os focus nodes ficam na página: é ela que os cria no
/// `initState` e os descarta no `dispose`.
class CropSizeInputs extends StatelessWidget {
  const CropSizeInputs({
    super.key,
    required this.crop,
    required this.widthController,
    required this.heightController,
    required this.widthFocus,
    required this.heightFocus,
    required this.onSubmitWidth,
    required this.onSubmitHeight,
    this.showPixelUnit = false,
  });

  final CropRect crop;
  final TextEditingController widthController;
  final TextEditingController heightController;
  final FocusNode widthFocus;
  final FocusNode heightFocus;
  final ValueChanged<String> onSubmitWidth;
  final ValueChanged<String> onSubmitHeight;

  /// A tela de vídeo rotula "Largura (px)"; foto e SVG, só "Largura".
  final bool showPixelUnit;

  /// Atualiza o texto sem mexer se já estiver correto, para não perder a
  /// posição do cursor à toa.
  static void _sync(TextEditingController controller, int value) {
    final text = value.toString();
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widthFocus.hasFocus) _sync(widthController, crop.width);
    if (!heightFocus.hasFocus) _sync(heightController, crop.height);

    final unit = showPixelUnit ? ' (px)' : '';
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: widthController,
            focusNode: widthFocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Largura$unit',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: onSubmitWidth,
            onTapOutside: (_) => onSubmitWidth(widthController.text),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: heightController,
            focusNode: heightFocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Altura$unit',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: onSubmitHeight,
            onTapOutside: (_) => onSubmitHeight(heightController.text),
          ),
        ),
      ],
    );
  }
}
