import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/ui/quick_convert_page.dart';

// "Converter formato" é uma tela só: enquanto nenhum arquivo foi escolhido
// ela mostra o cartão "Escolher arquivo" no mesmo lugar onde o cartão do
// arquivo aparece depois. Este teste trava o tamanho desse cartão: num
// `Padding` direto dentro do `Scaffold`, ele herdava a altura cheia do corpo
// e esticava pela tela inteira.

void main() {
  testWidgets('o cartão "Escolher arquivo" é compacto, não estica pela tela', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: QuickConvertPage()));
    await tester.pumpAndSettle();

    final label = find.text('Escolher arquivo');
    expect(label, findsOneWidget);
    expect(find.text('Vídeo, GIF ou WebP'), findsOneWidget);

    final card = tester.getSize(
      find.ancestor(of: label, matching: find.byType(InkWell)).first,
    );
    expect(card.height, lessThan(120));
    expect(card.height, lessThan(900 / 3));
  });
}
