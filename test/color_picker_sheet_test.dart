import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/ui/widgets/color_picker_sheet.dart';

Future<ui.Image> _neverCalledPreview() =>
    Future<ui.Image>.error('não deveria ser chamado neste teste');

Future<void> _openSheet(
  WidgetTester tester, {
  required Color initialColor,
  required ValueChanged<Color> onColorSelected,
}) async {
  // Retrato (mesma proporção de um celular real, como os outros testes de
  // tela deste app) — o `ColorPicker` do `flutter_colorpicker` escolhe entre
  // dois layouts internos conforme `MediaQuery.orientation`; a janela padrão
  // do `flutter_test` (800×600) é "paisagem" e cai no layout largo do
  // pacote, que estoura em telas estreitas. Nenhum aparelho real roda essa
  // tela deitado, então retrato é o cenário que precisa passar.
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCollageColorPickerSheet(
              context: context,
              title: 'Cor',
              initialColor: initialColor,
              onColorSelected: onColorSelected,
              previewImageBuilder: _neverCalledPreview,
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('roda HSV começa recolhida quando a cor atual é um swatch fixo', (
    tester,
  ) async {
    await _openSheet(
      tester,
      initialColor: const Color(0xFFFFFFFF), // um dos swatches fixos
      onColorSelected: (_) {},
    );

    expect(find.byKey(const ValueKey('collageColorPickerWheel')), findsNothing);
  });

  testWidgets('roda HSV começa aberta quando a cor atual já é customizada', (
    tester,
  ) async {
    await _openSheet(
      tester,
      initialColor: const Color(0xFF123456), // fora da paleta fixa
      onColorSelected: (_) {},
    );

    expect(
      find.byKey(const ValueKey('collageColorPickerWheel')),
      findsOneWidget,
    );
  });

  testWidgets('tocar a bolinha customizada abre a roda HSV', (tester) async {
    await _openSheet(
      tester,
      initialColor: const Color(0xFFFFFFFF),
      onColorSelected: (_) {},
    );

    expect(find.byKey(const ValueKey('collageColorPickerWheel')), findsNothing);

    // A bolinha customizada é o círculo logo depois dos swatches fixos e
    // antes do conta-gotas — identificado aqui pelo tooltip do conta-gotas
    // vizinho para não depender de posição exata na lista.
    final customButton = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_CustomColorButton',
    );
    expect(customButton, findsOneWidget);
    await tester.tap(customButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('collageColorPickerWheel')),
      findsOneWidget,
    );
  });

  testWidgets('escolher um swatch fixo fecha a roda se estava aberta', (
    tester,
  ) async {
    await _openSheet(
      tester,
      initialColor: const Color(0xFF123456),
      onColorSelected: (_) {},
    );
    expect(
      find.byKey(const ValueKey('collageColorPickerWheel')),
      findsOneWidget,
    );

    final customButton = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_SwatchButton',
    );
    await tester.tap(customButton.first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('collageColorPickerWheel')), findsNothing);
  });
}
