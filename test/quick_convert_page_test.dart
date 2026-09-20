import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/ui/quick_convert_page.dart';

/// A tela "Converter formato" escolhe o arquivo e o formato no mesmo lugar.
/// Só o estado vazio dá para montar aqui: o estado com arquivo depende do
/// seletor do sistema e de um `probe()` de verdade, e o que ele desenha está
/// coberto por `source_file_card_test.dart`.
void main() {
  testWidgets('sem arquivo, mostra só o convite para escolher', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuickConvertPage()));

    expect(find.text('Escolha o arquivo'), findsOneWidget);
    expect(find.text('Escolher arquivo'), findsOneWidget);

    expect(find.text('Escolher outro arquivo'), findsNothing);
    expect(find.text('Formato de saída'), findsNothing);
    expect(find.text('Converter'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });
}
