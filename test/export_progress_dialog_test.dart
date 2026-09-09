import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/ui/widgets/export_progress_dialog.dart';

Widget _harness(ValueNotifier<ExportProgress> progress, VoidCallback onCancel) {
  return MaterialApp(
    home: Scaffold(
      body: ExportProgressDialog(
        progress: progress,
        formatLabel: 'GIF',
        width: 720,
        height: 1280,
        onCancel: onCancel,
      ),
    ),
  );
}

void main() {
  testWidgets('mostra percentual, formato e tamanho da exportação', (
    tester,
  ) async {
    final progress = ValueNotifier(const ExportProgress(value: 0.41));
    addTearDown(progress.dispose);

    await tester.pumpWidget(_harness(progress, () {}));

    expect(find.text('41%'), findsOneWidget);
    expect(find.text('Exportando em GIF'), findsOneWidget);
    expect(find.text('720×1280 px'), findsOneWidget);
    // Sem "peso previsto": a montagem não tem a estimativa calibrada que o
    // vídeo tem.
    expect(find.textContaining('Peso'), findsNothing);
  });

  testWidgets('acompanha o progresso sem ser reconstruído de fora', (
    tester,
  ) async {
    final progress = ValueNotifier(const ExportProgress(value: 0.1));
    addTearDown(progress.dispose);

    await tester.pumpWidget(_harness(progress, () {}));
    expect(find.text('10%'), findsOneWidget);

    progress.value = const ExportProgress(value: 0.9);
    await tester.pump();

    expect(find.text('90%'), findsOneWidget);
    expect(find.text('10%'), findsNothing);
  });

  testWidgets('cancelar avisa uma vez e o botão desliga em seguida', (
    tester,
  ) async {
    final progress = ValueNotifier(const ExportProgress(value: 0.5));
    addTearDown(progress.dispose);
    var cancels = 0;

    await tester.pumpWidget(_harness(progress, () => cancels++));
    await tester.tap(find.text('Cancelar'));
    expect(cancels, 1);

    progress.value = const ExportProgress(value: 0.5, cancelling: true);
    await tester.pump();

    expect(find.text('Cancelando…'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    expect(cancels, 1);
  });
}
