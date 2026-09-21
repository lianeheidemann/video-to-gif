import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/models/conversion_settings.dart';
import 'package:video_to_gif/core/ui/crop/cropped_view.dart';

// A prévia da aba "Frame" tem que mostrar exatamente a janela de recorte
// escolhida em "Ajustar" — o mesmo retângulo que o FFmpeg usa no filtro
// `crop`. O vídeo real não inicializa no ambiente de teste, então quem é
// testado aqui é a geometria, com um filho comum no lugar do player.
const _key = ValueKey('conteudo');

Future<void> _pump(WidgetTester tester, CropRect? crop) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: CroppedView(
              sourceWidth: 640,
              sourceHeight: 360,
              crop: crop,
              child: const ColoredBox(key: _key, color: Colors.red),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a janela recortada assume a proporção do recorte', (
    tester,
  ) async {
    // 320x180 do vídeo é 16:9; numa largura de 320 dá 180 de altura.
    await _pump(tester, const CropRect(x: 160, y: 90, width: 320, height: 180));

    expect(tester.getSize(find.byType(CroppedView)), const Size(320, 180));
  });

  testWidgets('um recorte quadrado fica quadrado, não esticado', (
    tester,
  ) async {
    await _pump(tester, const CropRect(x: 20, y: 0, width: 360, height: 360));

    expect(tester.getSize(find.byType(CroppedView)), const Size(320, 320));
  });

  testWidgets('o conteúdo é desenhado no tamanho da fonte e deslocado', (
    tester,
  ) async {
    await _pump(tester, const CropRect(x: 160, y: 90, width: 320, height: 180));

    // O filho continua ocupando o vídeo inteiro (640x360 na escala interna);
    // quem escolhe o pedaço visível é o deslocamento + o clipe.
    expect(tester.getSize(find.byKey(_key)), const Size(640, 360));

    // Com o recorte começando em (160, 90) e a escala de 320/320 = 1, o
    // canto superior esquerdo do filho fica 160x90 acima/à esquerda da
    // janela visível.
    final content = tester.getTopLeft(find.byKey(_key));
    final window = tester.getTopLeft(find.byType(CroppedView));
    expect(content.dx - window.dx, closeTo(-160, 0.01));
    expect(content.dy - window.dy, closeTo(-90, 0.01));
  });

  testWidgets('sem recorte, mostra a fonte inteira', (tester) async {
    await _pump(tester, null);

    expect(tester.getSize(find.byType(CroppedView)), const Size(320, 180));
    expect(tester.getSize(find.byKey(_key)), const Size(320, 180));
  });
}
