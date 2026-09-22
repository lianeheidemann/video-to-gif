import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/services/imported_asset_store.dart';

/// Ladrilho de "importar" das fileiras de assets — abas "Fundo" e
/// "Stickers".
class ImportAssetTile extends StatelessWidget {
  const ImportAssetTile({
    super.key,
    required this.onTap,
    required this.label,
    this.size = 62,
    this.height = 46,
  });

  final VoidCallback onTap;
  final String label;
  final double size;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          children: [
            Container(
              width: size,
              height: height,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: theme.colorScheme.primary,
                size: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura de um asset importado pela pessoa (sticker ou imagem de fundo),
/// com borda de selecionado. Desenha SVG e imagem rasterizada.
class ImportedAssetThumb extends StatelessWidget {
  const ImportedAssetThumb({
    super.key,
    required this.asset,
    required this.selected,
    this.size = 62,
    this.height = 46,
  });

  final ImportedAsset asset;
  final bool selected;
  final double size;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 2 : 1,
        ),
      ),
      child: asset.isVector
          ? SvgPicture.file(File(asset.filePath), fit: BoxFit.contain)
          : Image.file(File(asset.filePath), fit: BoxFit.contain),
    );
  }
}
