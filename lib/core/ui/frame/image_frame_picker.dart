import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/frame_settings.dart';
import '../../models/image_frame.dart';
import '../../services/bundled_frame_store.dart';
import 'frame_thumb_shell.dart';

/// Fileira horizontal de miniaturas das molduras de imagem: "sem moldura",
/// as prontas do app, as importadas pela pessoa e, no fim, o botão de
/// importar.
class ImageFramePicker extends StatelessWidget {
  const ImageFramePicker({
    super.key,
    required this.selected,
    required this.imported,
    required this.onSelected,
    required this.onClear,
    required this.onImport,
    required this.onRemoveImported,
  });

  final ImageFrameAsset? selected;
  final List<ImageFrameAsset> imported;
  final ValueChanged<ImageFrameAsset> onSelected;
  final VoidCallback onClear;
  final VoidCallback onImport;
  final ValueChanged<ImageFrameAsset> onRemoveImported;

  @override
  Widget build(BuildContext context) {
    final assets = [...bundledImageFrames, ...imported];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: assets.length + 2,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return NoImageFrameThumb(
              selected: selected == null,
              onTap: onClear,
            );
          }
          if (index == assets.length + 1) {
            return ImportFrameThumb(onTap: onImport);
          }
          final asset = assets[index - 1];
          return ImageFrameThumb(
            asset: asset,
            selected: asset.id == selected?.id,
            onTap: () => onSelected(asset),
            onRemove: asset.source == ImageFrameSource.bundledSvg
                ? null
                : () => onRemoveImported(asset),
          );
        },
      ),
    );
  }
}

/// Primeira miniatura da fileira: nenhuma moldura de imagem.
class NoImageFrameThumb extends StatelessWidget {
  const NoImageFrameThumb({
    super.key,
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FrameThumbShell(
      key: const ValueKey('imageFrameThumb_none'),
      label: FrameStyle.none.label,
      selected: selected,
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: Icon(
        Icons.crop_free_rounded,
        size: 16,
        color: theme.colorScheme.primary.withValues(alpha: 0.6),
      ),
    );
  }
}

/// Miniatura de uma moldura de imagem. Só as importadas podem ser removidas,
/// daí [onRemove] nulo nas que vêm com o app.
class ImageFrameThumb extends StatelessWidget {
  const ImageFrameThumb({
    super.key,
    required this.asset,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });

  final ImageFrameAsset asset;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return FrameThumbShell(
      key: ValueKey('imageFrameThumb_${asset.id}'),
      label: asset.label,
      selected: selected,
      padding: const EdgeInsets.all(4),
      onTap: onTap,
      onLongPress: onRemove,
      child: ImageFrameArtwork(asset: asset, fit: BoxFit.contain),
    );
  }
}

/// Última miniatura da fileira: importar uma moldura nova.
class ImportFrameThumb extends StatelessWidget {
  const ImportFrameThumb({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 46,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Importar',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Desenha a arte de uma moldura de imagem, seja ela SVG do app, SVG
/// importado ou imagem rasterizada importada.
class ImageFrameArtwork extends StatelessWidget {
  const ImageFrameArtwork({super.key, required this.asset, required this.fit});

  final ImageFrameAsset asset;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return switch (asset.source) {
      ImageFrameSource.bundledSvg => SvgPicture.asset(
        asset.svgAssetPath!,
        fit: fit,
      ),
      ImageFrameSource.importedSvg => SvgPicture.file(
        File(asset.imageFilePath!),
        fit: fit,
      ),
      ImageFrameSource.importedImage => Image.file(
        File(asset.imageFilePath!),
        fit: fit,
      ),
    };
  }
}

/// Pergunta antes de remover uma moldura importada. Devolve `true` quando a
/// pessoa confirmou.
Future<bool> confirmRemoveImportedFrame(
  BuildContext context,
  ImageFrameAsset asset,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remover moldura?'),
      content: Text('"${asset.label}" vai ser removida da lista.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remover'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
