import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/features/svg/models/svg_info.dart';
import 'package:video_to_gif/features/svg/svg_edit_page.dart';

// Os quatro botões da aba "Girar" ficam dois a dois numa linha, então cada um
// tem menos da metade da largura da tela. Com o padding padrão do botão
// sobrava tão pouco espaço que "90° à esquerda" quebrava em três linhas num
// celular estreito — e até "Horizontal" quebrava em duas.
//
// O contrato é: cada rótulo cabe numa linha só, em qualquer largura de
// celular. Quando não couber nem assim (texto do sistema aumentado), a fonte
// encolhe em vez de a palavra quebrar ou ser cortada.

void main() {
  late Directory tempDir;
  late String svgPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('svg_transform_test');
    svgPath = '${tempDir.path}/a.svg';
    await File(svgPath).writeAsString(
      '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">'
      '<rect width="120" height="80" fill="red"/></svg>',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  for (final largura in [320.0, 360.0, 412.0]) {
    testWidgets('rótulos de girar/espelhar cabem numa linha em ${largura}dp', (
      tester,
    ) async {
      tester.view.physicalSize = Size(largura, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: SvgEditPage(
            svg: SvgInfo(path: svgPath, width: 120, height: 80),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Girar" aqui é a aba do rodapé; os botões têm nomes próprios.
      await tester.tap(find.text('Girar').last);
      await tester.pumpAndSettle();

      // Altura de uma linha no tamanho de fonte dos botões. Duas linhas
      // passariam bem disso.
      const umaLinha = 24.0;
      for (final rotulo in [
        '90° à esquerda',
        '90° à direita',
        'Horizontal',
        'Vertical',
      ]) {
        final alvo = find.text(rotulo);
        expect(alvo, findsOneWidget, reason: 'sumiu o rótulo "$rotulo"');
        expect(
          tester.getSize(alvo).height,
          lessThanOrEqualTo(umaLinha),
          reason: '"$rotulo" quebrou em mais de uma linha',
        );
      }

      expect(tester.takeException(), isNull);
    });
  }
}
