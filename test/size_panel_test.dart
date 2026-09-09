import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/size_estimate.dart';
import 'package:video_to_gif/ui/widgets/labeled_section.dart';
import 'package:video_to_gif/ui/widgets/size_panel.dart';

const _summary = '480×270 px · 12 FPS · 6.0 s · 256 cores';

SizeEstimate _estimate({
  required int bytes,
  EstimateConfidence confidence = EstimateConfidence.rough,
}) {
  return SizeEstimate(
    bytes: bytes,
    frames: 72,
    width: 480,
    height: 270,
    bytesPerPixel: 0.16,
    confidence: confidence,
    durationSeconds: 6,
  );
}

/// Monta o painel numa superfície alta e rolável, como na produção.
///
/// No app o `SizePanel` é um filho do `ListView` do editor, então ele pode ser
/// tão alto quanto precisar. A superfície padrão do teste (800×600) é menor do
/// que o painel inteiro; sem isto o `Column` estoura e o erro de layout
/// mascara a asserção que interessa.
Future<void> _pumpPanel(
  WidgetTester tester, {
  required SizeEstimate estimate,
  int originalBytes = 24 * 1024 * 1024,
  VoidCallback? onMeasure,
  bool measuring = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SizePanel(
            estimate: estimate,
            originalBytes: originalBytes,
            summary: _summary,
            measuring: measuring,
            onMeasure: onMeasure ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('classificação de tamanho', () {
    const mb = 1024 * 1024;

    test('considera leve até 15 MB', () {
      expect(SizeVerdict.forBytes(15 * mb), SizeVerdict.light);
    });

    test('considera moderado acima de 15 MB e abaixo de 25 MB', () {
      expect(SizeVerdict.forBytes(15 * mb + 1), SizeVerdict.good);
      expect(SizeVerdict.forBytes(25 * mb - 1), SizeVerdict.good);
    });

    test('considera pesado a partir de 25 MB', () {
      expect(SizeVerdict.forBytes(25 * mb), SizeVerdict.heavy);
    });
  });

  group('SizePanel', () {
    testWidgets('mostra peso, classificação e resumo das configurações', (
      tester,
    ) async {
      await _pumpPanel(tester, estimate: _estimate(bytes: 3 * 1024 * 1024));

      expect(find.text('3.0 MB'), findsOneWidget);
      expect(find.text('Leve'), findsWidgets);
      expect(find.text(_summary), findsOneWidget);
    });

    testWidgets('classifica um arquivo grande como pesado', (tester) async {
      await _pumpPanel(tester, estimate: _estimate(bytes: 30 * 1024 * 1024));

      expect(find.text('30 MB'), findsOneWidget);
      expect(_estimate(bytes: 30 * 1024 * 1024).verdict, SizeVerdict.heavy);
      expect(find.text('Pesado'), findsWidgets);
    });

    testWidgets('oferece recalcular enquanto a estimativa é aproximada', (
      tester,
    ) async {
      var chamou = false;
      await _pumpPanel(
        tester,
        estimate: _estimate(bytes: 3 * 1024 * 1024),
        onMeasure: () => chamou = true,
      );

      expect(find.textContaining('Faixa provável: '), findsOneWidget);

      await tester.tap(find.text('Recalcular'));
      expect(chamou, isTrue);
    });

    testWidgets(
      'depois de medir, anuncia a faixa medida e permite recalcular',
      (tester) async {
        await _pumpPanel(
          tester,
          estimate: _estimate(
            bytes: 3 * 1024 * 1024,
            confidence: EstimateConfidence.calibrated,
          ),
        );

        expect(find.textContaining('Faixa medida: '), findsOneWidget);
        expect(find.text('Medir'), findsNothing);
        expect(find.text('Medir novamente'), findsNothing);
        expect(find.text('Recalcular'), findsOneWidget);
      },
    );

    testWidgets('a faixa aperta quando a estimativa é medida', (tester) async {
      final aproximada = _estimate(bytes: 3 * 1024 * 1024);
      final medida = _estimate(
        bytes: 3 * 1024 * 1024,
        confidence: EstimateConfidence.calibrated,
      );

      await _pumpPanel(tester, estimate: medida);

      expect(find.textContaining(medida.formattedRange), findsOneWidget);
      expect(
        medida.highBytes - medida.lowBytes,
        lessThan(aproximada.highBytes - aproximada.lowBytes),
      );
    });

    testWidgets('desabilita o botão enquanto mede', (tester) async {
      var chamou = false;
      await _pumpPanel(
        tester,
        estimate: _estimate(bytes: 3 * 1024 * 1024),
        measuring: true,
        onMeasure: () => chamou = true,
      );

      expect(find.text('Medindo…'), findsOneWidget);
      await tester.tap(find.text('Medindo…'));
      expect(chamou, isFalse);
    });

    testWidgets('não mostra mais um botão de converter — isso é papel da '
        'AppBar', (tester) async {
      await _pumpPanel(tester, estimate: _estimate(bytes: 3 * 1024 * 1024));

      expect(find.text('Converter em GIF'), findsNothing);
    });
  });

  group('OptionChips', () {
    testWidgets('marca a opção atual e avisa quando outra é escolhida', (
      tester,
    ) async {
      int? escolhido;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OptionChips<int>(
              options: const [10, 12, 15],
              selected: 12,
              labelBuilder: (fps) => '$fps FPS',
              onSelected: (fps) => escolhido = fps,
            ),
          ),
        ),
      );

      final selecionado = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '12 FPS'),
      );
      expect(selecionado.selected, isTrue);

      await tester.tap(find.text('15 FPS'));
      expect(escolhido, 15);
    });
  });
}
