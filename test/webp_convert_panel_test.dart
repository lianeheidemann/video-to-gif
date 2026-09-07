import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/ui/widgets/webp_convert_panel.dart';

const _summary = '480×270 px · 12 FPS · 6.0 s · qualidade 75';

Future<void> _pumpPanel(WidgetTester tester, {VoidCallback? onConvert}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: WebpConvertPanel(
            summary: _summary,
            onConvert: onConvert ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('WebpConvertPanel', () {
    testWidgets('mostra o resumo das configurações e o botão de converter', (
      tester,
    ) async {
      await _pumpPanel(tester);

      expect(find.text(_summary), findsOneWidget);
      expect(find.text('Converter em WebP'), findsOneWidget);
    });

    testWidgets('converte ao tocar no botão', (tester) async {
      var chamou = false;
      await _pumpPanel(tester, onConvert: () => chamou = true);

      await tester.tap(find.text('Converter em WebP'));
      expect(chamou, isTrue);
    });
  });
}
