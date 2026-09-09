import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/ui/widgets/webp_convert_panel.dart';

const _summary = '480×270 px · 12 FPS · 6.0 s · qualidade 75';

Future<void> _pumpPanel(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: WebpConvertPanel(summary: _summary),
        ),
      ),
    ),
  );
}

void main() {
  group('WebpConvertPanel', () {
    testWidgets('mostra o resumo das configurações', (tester) async {
      await _pumpPanel(tester);

      expect(find.text(_summary), findsOneWidget);
    });

    testWidgets(
      'não mostra mais um botão de converter — isso é papel da AppBar',
      (tester) async {
        await _pumpPanel(tester);

        expect(find.text('Converter em WebP'), findsNothing);
      },
    );
  });
}
