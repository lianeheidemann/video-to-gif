import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/ui/quick_convert_page.dart';
import 'package:video_to_gif/ui/widgets/source_file_card.dart';

const _mp4 = VideoInfo(
  path: '/tmp/preview-v2.mp4',
  fileName: 'preview-v2.mp4',
  rawWidth: 2274,
  rawHeight: 1352,
  durationSeconds: 22.3,
  frameRate: 30,
  bitrateBps: 13000000,
  fileSizeBytes: 35 * 1024 * 1024,
  codec: 'h264',
);

Future<void> _pumpPage(WidgetTester tester, {VideoInfo? video}) async {
  await tester.pumpWidget(
    MaterialApp(home: QuickConvertPage(initialVideo: video)),
  );
}

/// Um chip desligado é o que tem `onSelected` nulo — é assim que a tela
/// apaga o formato de origem e, sem arquivo, todos eles.
bool _chipEnabled(WidgetTester tester, String label) {
  final chip = tester.widget<ChoiceChip>(
    find.widgetWithText(ChoiceChip, label),
  );
  return chip.onSelected != null;
}

bool _convertEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Converter'),
  );
  return button.onPressed != null;
}

void main() {
  group('sem arquivo', () {
    testWidgets('mostra a área tracejada para anexar', (tester) async {
      await _pumpPage(tester);

      expect(find.text('Escolher arquivo'), findsOneWidget);
      expect(find.text('Vídeo, GIF ou WebP'), findsOneWidget);

      expect(find.byType(SourceFileCard), findsNothing);
      expect(find.text('Escolher outro arquivo'), findsNothing);
    });

    testWidgets('mostra os formatos e o Converter, todos desligados', (
      tester,
    ) async {
      await _pumpPage(tester);

      expect(find.text('Formato de saída'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.text('Converter'), findsOneWidget);

      expect(_chipEnabled(tester, 'GIF'), isFalse);
      expect(_chipEnabled(tester, 'WebP animado'), isFalse);
      expect(_chipEnabled(tester, 'MP4'), isFalse);
      expect(_convertEnabled(tester), isFalse);
    });
  });

  group('com arquivo', () {
    testWidgets('troca a área tracejada pelo cartão de informações', (
      tester,
    ) async {
      await _pumpPage(tester, video: _mp4);

      expect(find.byType(SourceFileCard), findsOneWidget);
      expect(find.text('preview-v2.mp4'), findsOneWidget);
      expect(find.text('Escolher outro arquivo'), findsOneWidget);

      expect(find.text('Escolher arquivo'), findsNothing);
      expect(find.text('Vídeo, GIF ou WebP'), findsNothing);
    });

    testWidgets('liga os formatos, menos o do próprio arquivo', (tester) async {
      await _pumpPage(tester, video: _mp4);

      expect(_chipEnabled(tester, 'GIF'), isTrue);
      expect(_chipEnabled(tester, 'WebP animado'), isTrue);
      expect(_chipEnabled(tester, 'MP4'), isFalse);
    });

    testWidgets('Converter só liga depois de escolher um formato', (
      tester,
    ) async {
      await _pumpPage(tester, video: _mp4);
      expect(_convertEnabled(tester), isFalse);

      await tester.tap(find.widgetWithText(ChoiceChip, 'GIF'));
      await tester.pumpAndSettle();

      expect(_convertEnabled(tester), isTrue);
    });

    testWidgets('resolução começa em 100%, sem reduzir o arquivo sozinha', (
      tester,
    ) async {
      await _pumpPage(tester, video: _mp4);

      expect(find.text('Resolução'), findsOneWidget);
      expect(find.text('100% · 2274×1352 px'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 100.0);
    });

    testWidgets('arrastar o slider reduz a resolução mostrada', (tester) async {
      await _pumpPage(tester, video: _mp4);

      await tester.drag(find.byType(Slider), const Offset(-250, 0));
      await tester.pump();

      final value = tester.widget<Slider>(find.byType(Slider)).value;
      expect(value, lessThan(100.0));
      expect(find.text('100% · 2274×1352 px'), findsNothing);
    });
  });
}
