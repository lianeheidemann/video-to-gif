import 'dart:io';

import 'package:flutter/material.dart';

import '../models/crop_rect.dart';
import 'widgets/crop_overlay.dart';

/// Proporções oferecidas na fileira de baixo da [PhotoCropPage]. `null` em
/// [ratio] é o recorte livre (padrão); [PhotoCropPage.cellAspectRatio] entra
/// como "Da célula", e "Personalizada…" abre um campo para digitar `L:A`.
const _cropRatioPresets = <(String label, double? ratio)>[
  ('Livre', null),
  ('1:1', 1.0),
  ('4:5', 4 / 5),
  ('5:4', 5 / 4),
  ('3:4', 3 / 4),
  ('4:3', 4 / 3),
  ('9:16', 9 / 16),
  ('16:9', 16 / 9),
];

/// Tela cheia de recorte de uma única foto. O recorte é **livre por padrão**
/// — quem escolhe a proporção é o usuário, na fileira de baixo: livre, a da
/// própria célula, um dos presets ou uma proporção digitada. Como o resultado
/// pode ter qualquer proporção, quem chama coloca a foto recortada em
/// "encaixar" (ver `CollagePage._openCropTool`), para ela aparecer inteira
/// dentro da célula em vez de esticada.
///
/// Mesma moldura de recorte (véu + alças + botão de mover) já usada pelo
/// recorte de vídeo, generalizada em `widgets/crop_overlay.dart`. Devolve o
/// [CropRect] escolhido via `Navigator.pop`, ou `null` se cancelado.
class PhotoCropPage extends StatefulWidget {
  const PhotoCropPage({
    super.key,
    required this.photoPath,
    required this.photoWidth,
    required this.photoHeight,
    required this.cellAspectRatio,
    this.initialCrop,
  });

  final String photoPath;
  final int photoWidth;
  final int photoHeight;

  /// Proporção da célula onde a foto vai entrar — oferecida como a opção "Da
  /// célula", não mais imposta ao recorte inteiro.
  final double cellAspectRatio;

  final CropRect? initialCrop;

  @override
  State<PhotoCropPage> createState() => _PhotoCropPageState();
}

class _PhotoCropPageState extends State<PhotoCropPage> {
  /// `null` = recorte livre (cada alça mexe só no seu lado/canto).
  double? _lockedRatio;

  /// Rótulo da opção marcada na fileira — guardado à parte de [_lockedRatio]
  /// porque "Da célula" e uma proporção digitada podem cair no mesmo número
  /// de um preset, e o chip marcado tem que continuar sendo o que foi tocado.
  String _selectedLabel = 'Livre';

  /// Última proporção digitada em "Personalizada…", para o chip continuar
  /// mostrando o valor escolhido.
  String? _customLabel;

  late CropRect _crop =
      widget.initialCrop ??
      CropRect(
        x: 0,
        y: 0,
        width: widget.photoWidth,
        height: widget.photoHeight,
      );

  void _resize(CropHandle handle, Offset delta, Size previewSize) {
    if (previewSize.width <= 0 || previewSize.height <= 0) return;
    final dx = delta.dx * widget.photoWidth / previewSize.width;
    final dy = delta.dy * widget.photoHeight / previewSize.height;
    final ratio = _lockedRatio;
    final next = ratio == null
        ? resizeFreeCrop(
            _crop,
            handle,
            dx,
            dy,
            boundsWidth: widget.photoWidth,
            boundsHeight: widget.photoHeight,
          )
        : resizeLockedCrop(
            _crop,
            handle,
            dx,
            dy,
            ratio,
            boundsWidth: widget.photoWidth,
            boundsHeight: widget.photoHeight,
          );
    if (next.width == _crop.width &&
        next.height == _crop.height &&
        next.x == _crop.x &&
        next.y == _crop.y) {
      return;
    }
    setState(() => _crop = next);
  }

  void _move(Offset delta, Size previewSize) {
    if (previewSize.width <= 0 || previewSize.height <= 0) return;
    final dx = delta.dx * widget.photoWidth / previewSize.width;
    final dy = delta.dy * widget.photoHeight / previewSize.height;
    final maxX = (widget.photoWidth - _crop.width).clamp(0, widget.photoWidth);
    final maxY = (widget.photoHeight - _crop.height).clamp(
      0,
      widget.photoHeight,
    );
    final x = (_crop.x + dx.round()).clamp(0, maxX);
    final y = (_crop.y + dy.round()).clamp(0, maxY);
    if (x == _crop.x && y == _crop.y) return;
    setState(() => _crop = _crop.copyWith(x: x, y: y));
  }

  /// Troca a proporção travada: o recorte vira o maior retângulo centralizado
  /// com a nova proporção. No modo livre nada é reenquadrado — o recorte que
  /// já estava na tela continua igual, só param de valer as travas.
  void _selectRatio(String label, double? ratio) {
    setState(() {
      _selectedLabel = label;
      _lockedRatio = ratio;
      if (ratio != null) {
        _crop = CropRect.centeredIn(
          widget.photoWidth,
          widget.photoHeight,
          ratio,
        );
      }
    });
  }

  Future<void> _askCustomRatio() async {
    final result = await showDialog<(String, double)>(
      context: context,
      builder: (_) => const _CustomRatioDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _customLabel = result.$1);
    _selectRatio(result.$1, result.$2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Recortar foto'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_crop),
            child: const Text(
              'Usar recorte',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.photoWidth / widget.photoHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(widget.photoPath), fit: BoxFit.fill),
                    CropOverlay(
                      bounds: Size(
                        widget.photoWidth.toDouble(),
                        widget.photoHeight.toDouble(),
                      ),
                      crop: _crop,
                      onResize: _resize,
                      onMove: _move,
                      freeform: _lockedRatio == null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _ratioBar(),
        ],
      ),
    );
  }

  Widget _ratioBar() {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 64,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          children: [
            for (final preset in _cropRatioPresets) ...[
              _ratioChip(preset.$1, () => _selectRatio(preset.$1, preset.$2)),
              const SizedBox(width: 8),
            ],
            _ratioChip(
              'Da célula',
              () => _selectRatio('Da célula', widget.cellAspectRatio),
            ),
            const SizedBox(width: 8),
            _ratioChip(_customLabel ?? 'Personalizada…', _askCustomRatio),
          ],
        ),
      ),
    );
  }

  Widget _ratioChip(String label, VoidCallback onTap) {
    final selected = _selectedLabel == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: Colors.white10,
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: selected
            ? Theme.of(context).colorScheme.onPrimary
            : Colors.white,
        fontWeight: FontWeight.w600,
      ),
      side: const BorderSide(color: Colors.white24),
      showCheckmark: false,
    );
  }
}

/// Pergunta uma proporção `L:A` digitada. Devolve o rótulo já formatado
/// ("5:7") e a proporção correspondente, ou `null` se cancelado/inválido.
class _CustomRatioDialog extends StatefulWidget {
  const _CustomRatioDialog();

  @override
  State<_CustomRatioDialog> createState() => _CustomRatioDialogState();
}

class _CustomRatioDialogState extends State<_CustomRatioDialog> {
  final _width = TextEditingController();
  final _height = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _confirm() {
    final w = double.tryParse(_width.text.trim().replaceAll(',', '.'));
    final h = double.tryParse(_height.text.trim().replaceAll(',', '.'));
    if (w == null || h == null || w <= 0 || h <= 0) {
      setState(() => _error = 'Digite dois números maiores que zero.');
      return;
    }
    final label = '${_trim(w)}:${_trim(h)}';
    Navigator.of(context).pop((label, w / h));
  }

  /// "5" em vez de "5.0" quando o número é inteiro — o rótulo do chip fica
  /// com a cara das proporções prontas ("4:5"), não "4.0:5.0".
  String _trim(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Proporção personalizada'),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _width,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Largura',
                errorText: _error,
                errorMaxLines: 2,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: Text(':'),
          ),
          Expanded(
            child: TextField(
              controller: _height,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Altura'),
              onSubmitted: (_) => _confirm(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('Usar')),
      ],
    );
  }
}
