import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/ui/widgets/collage_overlay_view.dart';

const _canvasSize = Size(300, 300);

Widget _harness({
  required bool interactive,
  required bool selected,
  required VoidCallback onSelect,
  required void Function(double, double, double, double) onTransformChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: _canvasSize.width,
        height: _canvasSize.height,
        child: Stack(
          children: [
            CollageOverlayView(
              centerX: 0.5,
              centerY: 0.5,
              scale: 1,
              rotation: 0,
              minScale: 0.2,
              maxScale: 3.0,
              canvasSize: _canvasSize,
              selected: selected,
              interactive: interactive,
              onSelect: onSelect,
              onTransformChanged: onTransformChanged,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: ColoredBox(
                  key: Key('overlay_content'),
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('interactive: false — toque e arrasto não fazem nada', (
    tester,
  ) async {
    var selected = false;
    var transformChanged = false;
    await tester.pumpWidget(
      _harness(
        interactive: false,
        selected: false,
        onSelect: () => selected = true,
        onTransformChanged: (_, _, _, _) => transformChanged = true,
      ),
    );

    final center = tester.getCenter(find.byKey(const Key('overlay_content')));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(selected, isFalse);

    await tester.dragFrom(center, const Offset(30, 30));
    await tester.pumpAndSettle();
    expect(transformChanged, isFalse);
  });

  testWidgets('interactive: true — toque seleciona e arrasto move', (
    tester,
  ) async {
    var selected = false;
    var transformChanged = false;
    await tester.pumpWidget(
      _harness(
        interactive: true,
        selected: false,
        onSelect: () => selected = true,
        onTransformChanged: (_, _, _, _) => transformChanged = true,
      ),
    );

    final center = tester.getCenter(find.byKey(const Key('overlay_content')));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(selected, isTrue);

    await tester.dragFrom(center, const Offset(30, 30));
    await tester.pumpAndSettle();
    expect(transformChanged, isTrue);
  });

  testWidgets(
    'alça de redimensionar só aparece quando selecionado, e arrastá-la '
    'aumenta a escala',
    (tester) async {
      var lastScale = 1.0;
      await tester.pumpWidget(
        _harness(
          interactive: true,
          selected: false,
          onSelect: () {},
          onTransformChanged: (_, _, scale, _) => lastScale = scale,
        ),
      );
      expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);

      await tester.pumpWidget(
        _harness(
          interactive: true,
          selected: true,
          onSelect: () {},
          onTransformChanged: (_, _, scale, _) => lastScale = scale,
        ),
      );
      final handle = find.byIcon(Icons.open_in_full_rounded);
      expect(handle, findsOneWidget);

      await tester.dragFrom(tester.getCenter(handle), const Offset(40, 40));
      await tester.pumpAndSettle();
      expect(lastScale, greaterThan(1.0));
    },
  );
}
