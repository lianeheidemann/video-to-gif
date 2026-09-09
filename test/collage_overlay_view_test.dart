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
    'o overlay acompanha o dedo 1:1, sem perder o começo do arrasto',
    (tester) async {
      // Com o `dragStartBehavior` padrão (`start`), os ~18px que o dedo anda
      // até a arena aceitar o gesto eram descartados: um arrasto de 100px
      // deslocava só ~80px e o objeto ficava atrasado o gesto inteiro — a
      // reclamação de "está se movendo muito lentamente".
      // Harness próprio: o overlay precisa RECEBER de volta a posição nova a
      // cada quadro (como a tela de montagem faz), senão cada update parte
      // sempre do mesmo centro e o teste mediria só o último delta.
      var centerX = 0.5;
      var centerY = 0.5;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: _canvasSize.width,
              height: _canvasSize.height,
              child: StatefulBuilder(
                builder: (context, setState) => Stack(
                  children: [
                    CollageOverlayView(
                      centerX: centerX,
                      centerY: centerY,
                      scale: 1,
                      rotation: 0,
                      minScale: 0.2,
                      maxScale: 3.0,
                      canvasSize: _canvasSize,
                      selected: false,
                      interactive: true,
                      onSelect: () {},
                      onTransformChanged: (x, y, _, _) => setState(() {
                        centerX = x;
                        centerY = y;
                      }),
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
          ),
        ),
      );

      final center = tester.getCenter(find.byKey(const Key('overlay_content')));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 20));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(10, 5));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final movedX = (centerX - 0.5) * _canvasSize.width;
      final movedY = (centerY - 0.5) * _canvasSize.height;
      expect(movedX, closeTo(100, 0.5));
      expect(movedY, closeTo(50, 0.5));
    },
  );

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
  testWidgets(
    'alça de girar só aparece quando selecionado, e arrastá-la gira o '
    'conteúdo',
    (tester) async {
      var lastRotation = 0.0;
      var lastScale = 1.0;
      await tester.pumpWidget(
        _harness(
          interactive: true,
          selected: false,
          onSelect: () {},
          onTransformChanged: (_, _, scale, rotation) {
            lastScale = scale;
            lastRotation = rotation;
          },
        ),
      );
      expect(find.byIcon(Icons.rotate_right_rounded), findsNothing);

      await tester.pumpWidget(
        _harness(
          interactive: true,
          selected: true,
          onSelect: () {},
          onTransformChanged: (_, _, scale, rotation) {
            lastScale = scale;
            lastRotation = rotation;
          },
        ),
      );
      final handle = find.byIcon(Icons.rotate_right_rounded);
      expect(handle, findsOneWidget);

      // A alça fica no canto superior direito; puxá-la para baixo roda o
      // conteúdo no sentido horário em volta do centro.
      await tester.dragFrom(tester.getCenter(handle), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(lastRotation, greaterThan(0));
      // Girar é só girar: a escala não pode andar junto, senão a alça faria
      // duas coisas ao mesmo tempo.
      expect(lastScale, 1.0);
    },
  );
}
