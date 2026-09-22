import 'dart:io';

import 'package:flutter/material.dart';

import '../models/background_image.dart';

/// Desenha uma imagem de fundo da montagem, venha ela dos fundos prontos do
/// app ou de um arquivo importado.
///
/// As duas origens convivem em `CollageBackground.imagePath`, então prévia
/// da montagem e prévia de célula precisavam do mesmo desvio — está aqui
/// para não sair copiado nos dois lugares.
class BackgroundImageView extends StatelessWidget {
  const BackgroundImageView({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
  });

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return isBundledBackgroundPath(path)
        ? Image.asset(path, fit: fit)
        : Image.file(File(path), fit: fit);
  }
}
