import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Swatches rápidos oferecidos antes da roda HSV completa — mesmas cores de
/// `PhotoFramePage`'s `_colorSwatches`, para as duas telas ficarem
/// consistentes.
const collageColorSwatches = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFC9A8FF),
  Color(0xFFE57373),
  Color(0xFF58C78C),
  Color(0xFFB8B36A),
  Color(0xFF64B5F6),
  Color(0xFFE6A15D),
];

/// Abre um bottom sheet para escolher a cor de fundo da montagem: swatches
/// rápidos, roda HSV completa ([ColorPicker], pacote `flutter_colorpicker`) e
/// um conta-gotas que amostra um pixel da prévia atual — [previewImageBuilder]
/// rasteriza a montagem inteira (ver `composeCollage`) para o usuário poder
/// escolher uma cor de qualquer foto/sticker visível, não só de uma paleta
/// fixa.
Future<void> showCollageColorPickerSheet({
  required BuildContext context,
  required String title,
  required Color initialColor,
  required ValueChanged<Color> onColorSelected,
  required Future<ui.Image> Function() previewImageBuilder,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _ColorPickerSheet(
      title: title,
      initialColor: initialColor,
      onColorSelected: onColorSelected,
      previewImageBuilder: previewImageBuilder,
    ),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({
    required this.title,
    required this.initialColor,
    required this.onColorSelected,
    required this.previewImageBuilder,
  });

  final String title;
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;
  final Future<ui.Image> Function() previewImageBuilder;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late Color _color = widget.initialColor;
  bool _samplingPreview = false;

  void _select(Color color) {
    setState(() => _color = color);
    widget.onColorSelected(color);
  }

  Future<void> _startEyedropper() async {
    setState(() => _samplingPreview = true);
    try {
      final ui.Image image;
      try {
        image = await widget.previewImageBuilder();
      } catch (_) {
        // Sem isso o erro virava uma exceção assíncrona sem dono e o botão
        // simplesmente não fazia nada, sem explicação nenhuma.
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Não foi possível preparar a prévia para o conta-gotas.',
                ),
              ),
            );
        }
        return;
      }
      if (!mounted) {
        image.dispose();
        return;
      }
      final result = await showDialog<Color>(
        context: context,
        builder: (dialogContext) => _EyedropperDialog(image: image),
      );
      image.dispose();
      if (result != null) _select(result);
    } finally {
      if (mounted) setState(() => _samplingPreview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final color in collageColorSwatches)
                    _SwatchButton(
                      color: color,
                      selected: color == _color,
                      onTap: () => _select(color),
                    ),
                  _EyedropperButton(
                    busy: _samplingPreview,
                    onTap: _startEyedropper,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ColorPicker(
                key: const ValueKey('collageColorPickerWheel'),
                pickerColor: _color,
                onColorChanged: _select,
                enableAlpha: false,
                displayThumbColor: true,
                labelTypes: const [],
                pickerAreaHeightPercent: 0.7,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 3 : 1.5,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 18,
                color: color.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}

class _EyedropperButton extends StatelessWidget {
  const _EyedropperButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.colorize_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
      ),
    );
  }
}

/// Deixa o usuário tocar/arrastar sobre a prévia rasterizada da montagem
/// para escolher um pixel exato como cor — leitura direta dos bytes RGBA
/// (mesma técnica de `imported_frame_store.dart`'s detecção de buraco alfa),
/// sem precisar reencodar a imagem para PNG/arquivo.
class _EyedropperDialog extends StatefulWidget {
  const _EyedropperDialog({required this.image});

  final ui.Image image;

  @override
  State<_EyedropperDialog> createState() => _EyedropperDialogState();
}

class _EyedropperDialogState extends State<_EyedropperDialog> {
  ByteData? _raw;
  Color _preview = Colors.white;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await widget.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (!mounted) return;
    setState(() => _raw = raw);
  }

  Color? _colorAt(Offset localPosition, Size widgetSize) {
    final raw = _raw;
    if (raw == null || widgetSize.width <= 0 || widgetSize.height <= 0) {
      return null;
    }
    final px = (localPosition.dx / widgetSize.width * widget.image.width)
        .floor()
        .clamp(0, widget.image.width - 1);
    final py = (localPosition.dy / widgetSize.height * widget.image.height)
        .floor()
        .clamp(0, widget.image.height - 1);
    final offset = (py * widget.image.width + px) * 4;
    final a = raw.getUint8(offset + 3);
    // Sem cor nenhuma ali: transparência já é seu próprio modo de fundo, então
    // tocar numa área vazia da prévia não escolhe nada (antes devolvia preto,
    // porque num buffer pré-multiplicado o RGB de um pixel transparente é 0).
    if (a == 0) return null;
    // `rawRgba` vem pré-multiplicado pelo alfa: desfaz a multiplicação para
    // que uma área semitransparente devolva a cor que aparenta ter, e não uma
    // versão escurecida dela. O conta-gotas sempre devolve uma cor opaca.
    int channel(int index) {
      final value = raw.getUint8(offset + index);
      if (a == 255) return value;
      return (value * 255 / a).round().clamp(0, 255);
    }

    return Color.fromARGB(255, channel(0), channel(1), channel(2));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Toque na imagem para escolher a cor'),
      content: SizedBox(
        width: double.maxFinite,
        child: AspectRatio(
          aspectRatio: widget.image.width / widget.image.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              void handle(Offset localPosition) {
                final color = _colorAt(localPosition, size);
                if (color != null) setState(() => _preview = color);
              }

              return GestureDetector(
                onTapUp: (details) => handle(details.localPosition),
                onPanUpdate: (details) => handle(details.localPosition),
                child: RawImage(image: widget.image, fit: BoxFit.fill),
              );
            },
          ),
        ),
      ),
      actions: [
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: _preview,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_preview),
          child: const Text('Usar esta cor'),
        ),
      ],
    );
  }
}
