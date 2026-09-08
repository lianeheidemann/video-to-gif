import 'dart:io';

import 'package:flutter/material.dart';

import '../models/crop_rect.dart';
import 'widgets/crop_overlay.dart';

/// Tela cheia de recorte de uma única foto, travada numa [aspectRatio] fixa
/// (a da célula onde a foto vai entrar — recorte livre não faz sentido aqui,
/// já que o resultado sempre precisa preencher a célula sem sobra). Mesma
/// moldura de recorte (véu + alças + botão de mover) já usada pelo recorte
/// de vídeo, generalizada em `widgets/crop_overlay.dart`. Devolve o
/// [CropRect] escolhido via `Navigator.pop`, ou `null` se cancelado.
class PhotoCropPage extends StatefulWidget {
  const PhotoCropPage({
    super.key,
    required this.photoPath,
    required this.photoWidth,
    required this.photoHeight,
    required this.aspectRatio,
    this.initialCrop,
  });

  final String photoPath;
  final int photoWidth;
  final int photoHeight;
  final double aspectRatio;
  final CropRect? initialCrop;

  @override
  State<PhotoCropPage> createState() => _PhotoCropPageState();
}

class _PhotoCropPageState extends State<PhotoCropPage> {
  late CropRect _crop =
      widget.initialCrop ??
      CropRect.centeredIn(
        widget.photoWidth,
        widget.photoHeight,
        widget.aspectRatio,
      );

  void _resize(CropHandle handle, Offset delta, Size previewSize) {
    if (previewSize.width <= 0 || previewSize.height <= 0) return;
    final dx = delta.dx * widget.photoWidth / previewSize.width;
    final dy = delta.dy * widget.photoHeight / previewSize.height;
    final next = resizeLockedCrop(
      _crop,
      handle,
      dx,
      dy,
      widget.aspectRatio,
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
      body: Center(
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
                freeform: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
