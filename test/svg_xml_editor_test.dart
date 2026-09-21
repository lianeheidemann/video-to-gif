import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/models/crop_rect.dart';
import 'package:video_to_gif/features/svg/models/svg_edit_settings.dart';
import 'package:video_to_gif/features/svg/models/svg_info.dart';
import 'package:video_to_gif/features/svg/services/svg_xml_editor.dart';
import 'package:xml/xml.dart';

/// SVG 120x80 (retângulo, não quadrado, de propósito — pra qualquer troca de
/// largura/altura em teste de rotação ficar óbvia) com um único `<rect>`
/// filho, `viewBox` batendo 1:1 com `width`/`height`.
const _svg120x80 =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80" '
    'width="120" height="80"><rect x="10" y="10" width="20" height="20"/>'
    '</svg>';

XmlElement _parseRoot(String source) => XmlDocument.parse(source).rootElement;

void main() {
  group('readSvgGeometry', () {
    test('usa o viewBox quando presente', () {
      final root = _parseRoot(_svg120x80);
      final geometry = readSvgGeometry(
        root,
        const SvgInfo(path: '', width: 120, height: 80),
      );
      expect(geometry.viewBoxX, 0);
      expect(geometry.viewBoxY, 0);
      expect(geometry.viewBoxWidth, 120);
      expect(geometry.viewBoxHeight, 80);
      expect(geometry.scaleX, 1);
      expect(geometry.scaleY, 1);
    });

    test('sintetiza o viewBox a partir do SvgInfo quando ausente', () {
      final root = _parseRoot(
        '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>',
      );
      final geometry = readSvgGeometry(
        root,
        const SvgInfo(path: '', width: 50, height: 30),
      );
      expect(geometry.viewBoxX, 0);
      expect(geometry.viewBoxY, 0);
      expect(geometry.viewBoxWidth, 50);
      expect(geometry.viewBoxHeight, 30);
      expect(root.getAttribute('viewBox'), '0 0 50 30');
    });

    test('escala não uniforme quando viewBox e width/height divergem', () {
      // viewBox quadrado 100x100, mas exibido achatado em 200x100 — como
      // ícones que usam width/height diferentes do viewBox de propósito.
      final root = _parseRoot(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" '
        'width="200" height="100"><rect/></svg>',
      );
      final geometry = readSvgGeometry(
        root,
        const SvgInfo(path: '', width: 200, height: 100),
      );
      expect(geometry.scaleX, 0.5);
      expect(geometry.scaleY, 1.0);
    });

    test('SvgInfo com tamanho inválido lança SvgEditException', () {
      final root = _parseRoot(_svg120x80);
      expect(
        () => readSvgGeometry(
          root,
          const SvgInfo(path: '', width: 0, height: 80),
        ),
        throwsA(isA<SvgEditException>()),
      );
    });
  });

  test(
    'cropSvg converte o recorte do espaço de exibição pro viewBox nativo',
    () {
      // viewBox quadrado 0 0 100 100, exibido em 200x100 (2:1) — escala
      // diferente por eixo, pra provar que cropSvg não assume escala uniforme.
      final root = _parseRoot(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" '
        'width="200" height="100"><rect/></svg>',
      );
      final info = const SvgInfo(path: '', width: 200, height: 100);
      final geometry = readSvgGeometry(root, info);

      cropSvg(
        root,
        geometry,
        const CropRect(x: 50, y: 10, width: 100, height: 50),
      );

      // scaleX = 100/200 = 0.5, scaleY = 100/100 = 1.0
      // newX = 0 + 50*0.5 = 25, newY = 0 + 10*1.0 = 10
      // newW = 100*0.5 = 50, newH = 50*1.0 = 50
      expect(root.getAttribute('viewBox'), '25 10 50 50');
      // width/height de exibição acompanham o tamanho do recorte (em espaço
      // de exibição, a mesma unidade de largura/altura originais), pra não
      // ficar com a proporção declarada descasada do novo viewBox.
      expect(root.getAttribute('width'), '100');
      expect(root.getAttribute('height'), '50');
    },
  );

  group('rotateSvg', () {
    test('90° envolve o conteúdo, troca width/height e o viewBox', () {
      final root = _parseRoot(_svg120x80);
      rotateSvg(root, 1);

      expect(root.getAttribute('width'), '80');
      expect(root.getAttribute('height'), '120');
      expect(root.getAttribute('viewBox'), '20 -20 80 120');

      final groups = root.childElements.where((e) => e.name.local == 'g');
      expect(groups, hasLength(1));
      expect(groups.first.getAttribute('transform'), 'rotate(90 60 40)');
      expect(groups.first.findElements('rect'), hasLength(1));
    });

    test('180° gira sem trocar width/height nem o viewBox', () {
      final root = _parseRoot(_svg120x80);
      rotateSvg(root, 2);

      expect(root.getAttribute('width'), '120');
      expect(root.getAttribute('height'), '80');
      expect(root.getAttribute('viewBox'), '0 0 120 80');
      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      expect(group.getAttribute('transform'), 'rotate(180 60 40)');
    });

    test('270° troca width/height igual ao 90°', () {
      final root = _parseRoot(_svg120x80);
      rotateSvg(root, 3);

      expect(root.getAttribute('width'), '80');
      expect(root.getAttribute('height'), '120');
      expect(root.getAttribute('viewBox'), '20 -20 80 120');
      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      expect(group.getAttribute('transform'), 'rotate(270 60 40)');
    });

    test('0° (ou múltiplo de 4) não mexe em nada', () {
      final root = _parseRoot(_svg120x80);
      rotateSvg(root, 0);
      expect(root.childElements.any((e) => e.name.local == 'g'), isFalse);
      expect(root.getAttribute('viewBox'), '0 0 120 80');
    });

    test('duas rotações seguidas não aninham um segundo grupo', () {
      final root = _parseRoot(_svg120x80);
      rotateSvg(root, 1);
      rotateSvg(root, 1);
      final groups = root.childElements.where((e) => e.name.local == 'g');
      expect(groups, hasLength(1));
      // As duas rotações de 90° compõem no mesmo transform, a mais nova à
      // esquerda (aplicada por último).
      final transform = groups.first.getAttribute('transform')!;
      expect('rotate('.allMatches(transform), hasLength(2));
    });
  });

  group('flipSvg', () {
    test('horizontal espelha em torno do centro do viewBox', () {
      final root = _parseRoot(_svg120x80);
      flipSvg(root, horizontal: true, vertical: false);
      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      expect(group.getAttribute('transform'), 'translate(120,0) scale(-1,1)');
    });

    test('vertical espelha no outro eixo', () {
      final root = _parseRoot(_svg120x80);
      flipSvg(root, horizontal: false, vertical: true);
      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      expect(group.getAttribute('transform'), 'translate(0,80) scale(1,-1)');
    });

    test('nenhum dos dois não mexe em nada', () {
      final root = _parseRoot(_svg120x80);
      flipSvg(root, horizontal: false, vertical: false);
      expect(root.childElements.any((e) => e.name.local == 'g'), isFalse);
    });

    test('espelhar depois de girar compõe por cima do resultado girado', () {
      final root = _parseRoot(_svg120x80);
      rotateSvg(root, 1); // transform="rotate(90 60 40)"
      flipSvg(root, horizontal: true, vertical: false);
      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      final transform = group.getAttribute('transform')!;
      // O flip (aplicado depois) fica à esquerda — é aplicado por último.
      expect(transform, startsWith('translate(120,0) scale(-1,1)'));
      expect(transform, contains('rotate(90 60 40)'));
    });
  });

  group('applyBackgroundSvg', () {
    test('insere um rect cobrindo o viewBox como primeiro filho', () {
      final root = _parseRoot(_svg120x80);
      applyBackgroundSvg(root, const Color(0xFF112233));

      final first = root.children.whereType<XmlElement>().first;
      expect(first.name.local, 'rect');
      expect(first.getAttribute('x'), '0');
      expect(first.getAttribute('y'), '0');
      expect(first.getAttribute('width'), '120');
      expect(first.getAttribute('height'), '80');
      expect(first.getAttribute('fill'), '#112233');
      expect(first.getAttribute('fill-opacity'), isNull);
    });

    test('cor com alfa define fill-opacity', () {
      final root = _parseRoot(_svg120x80);
      applyBackgroundSvg(root, const Color(0x80112233));
      final rect = root.children.whereType<XmlElement>().first;
      expect(
        double.parse(rect.getAttribute('fill-opacity')!),
        closeTo(0.502, 0.01),
      );
    });

    test('null remove o rect inserido, sem deixar duplicata', () {
      final root = _parseRoot(_svg120x80);
      applyBackgroundSvg(root, const Color(0xFF112233));
      applyBackgroundSvg(root, null);
      expect(
        root.childElements.where((e) => e.name.local == 'rect'),
        hasLength(1), // só o <rect> original do SVG, não o de fundo
      );
    });
  });

  group('applyFilterSvg', () {
    test('preto e branco usa feColorMatrix type=saturate values=0', () {
      final root = _parseRoot(_svg120x80);
      applyFilterSvg(root, SvgFilterType.grayscale);

      final defs = root.childElements.firstWhere((e) => e.name.local == 'defs');
      final matrix = defs
          .findElements('filter')
          .first
          .findElements('feColorMatrix')
          .first;
      expect(matrix.getAttribute('type'), 'saturate');
      expect(matrix.getAttribute('values'), '0');

      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      expect(group.getAttribute('filter'), 'url(#svgedit-filter)');
    });

    test('inverter usa uma matriz explícita', () {
      final root = _parseRoot(_svg120x80);
      applyFilterSvg(root, SvgFilterType.invert);
      final defs = root.childElements.firstWhere((e) => e.name.local == 'defs');
      final matrix = defs
          .findElements('filter')
          .first
          .findElements('feColorMatrix')
          .first;
      expect(matrix.getAttribute('type'), 'matrix');
      expect(matrix.getAttribute('values'), contains('-1'));
    });

    test('nenhum remove defs e o atributo filter do grupo', () {
      final root = _parseRoot(_svg120x80);
      applyFilterSvg(root, SvgFilterType.grayscale);
      applyFilterSvg(root, SvgFilterType.none);
      expect(root.childElements.any((e) => e.name.local == 'defs'), isFalse);
      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      expect(group.getAttribute('filter'), isNull);
    });
  });

  group('applyOpacitySvg', () {
    test('define opacity no grupo de conteúdo', () {
      final root = _parseRoot(_svg120x80);
      applyOpacitySvg(root, 0.5);
      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      expect(group.getAttribute('opacity'), '0.5');
    });

    test('opacidade 1 remove o atributo em vez de escrever "1"', () {
      final root = _parseRoot(_svg120x80);
      applyOpacitySvg(root, 0.5);
      applyOpacitySvg(root, 1);
      final group = root.childElements.firstWhere((e) => e.name.local == 'g');
      expect(group.getAttribute('opacity'), isNull);
    });
  });

  group('ensureContentGroup', () {
    test('é idempotente: chamar duas vezes reaproveita o mesmo grupo', () {
      final root = _parseRoot(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect/><circle/></svg>',
      );
      final first = ensureContentGroup(root);
      final second = ensureContentGroup(root);
      expect(identical(first, second), isTrue);
      expect(
        root.childElements.where((e) => e.name.local == 'g'),
        hasLength(1),
      );
      expect(first.findElements('rect'), hasLength(1));
      expect(first.findElements('circle'), hasLength(1));
    });

    test('move um transform já existente na raiz para o grupo', () {
      final root = _parseRoot(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" '
        'transform="translate(5,5)"><rect/></svg>',
      );
      final group = ensureContentGroup(root);
      expect(group.getAttribute('transform'), 'translate(5,5)');
      expect(root.getAttribute('transform'), isNull);
    });

    test('não move <defs>/<title> pro grupo de conteúdo', () {
      final root = _parseRoot(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<title>Ícone</title><defs><rect id="a"/></defs><rect/></svg>',
      );
      final group = ensureContentGroup(root);
      expect(group.findElements('rect'), hasLength(1));
      expect(root.childElements.any((e) => e.name.local == 'title'), isTrue);
      expect(root.childElements.any((e) => e.name.local == 'defs'), isTrue);
    });

    test('raiz sem filho nenhum cria um grupo vazio sem quebrar', () {
      final root = _parseRoot(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"/>',
      );
      final group = ensureContentGroup(root);
      expect(group.children, isEmpty);
      expect(root.childElements, hasLength(1));
    });
  });

  test('renderEditedSvg preserva namespaces e atributos com prefixo', () {
    const source =
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" '
        'viewBox="0 0 10 10" width="10" height="10">'
        '<use xlink:href="#a"/></svg>';
    final result = renderEditedSvg(
      source,
      const SvgInfo(path: '', width: 10, height: 10),
      const SvgEditSettings(opacity: 0.8),
    );
    expect(result, contains('xmlns="http://www.w3.org/2000/svg"'));
    expect(result, contains('xmlns:xlink="http://www.w3.org/1999/xlink"'));
    expect(result, contains('xlink:href="#a"'));
    // Não deve lançar — round-trip válido.
    expect(() => XmlDocument.parse(result), returnsNormally);
  });

  test('renderEditedSvg encadeia recorte + girar + espelhar + fundo + '
      'filtro + opacidade sem quebrar', () {
    final result = renderEditedSvg(
      _svg120x80,
      const SvgInfo(path: '', width: 120, height: 80),
      const SvgEditSettings(
        crop: CropRect(x: 0, y: 0, width: 100, height: 60),
        rotationQuarterTurns: 1,
        flipHorizontal: true,
        transparentBackground: false,
        backgroundColor: Color(0xFF00FF00),
        filterType: SvgFilterType.grayscale,
        opacity: 0.5,
      ),
    );

    final doc = XmlDocument.parse(result);
    final root = doc.rootElement;
    expect(root.getAttribute('width'), '60'); // recortado (100x60) e girado
    expect(root.getAttribute('height'), '100');
    final group = root.childElements.firstWhere((e) => e.name.local == 'g');
    expect(group.getAttribute('transform'), contains('rotate('));
    expect(group.getAttribute('transform'), contains('scale(-1,1)'));
    expect(group.getAttribute('opacity'), '0.5');
    expect(group.getAttribute('filter'), 'url(#svgedit-filter)');
    expect(
      root.childElements
          .where((e) => e.name.local == 'rect')
          .first
          .getAttribute('fill'),
      '#00ff00',
    );
  });

  test('renderEditedSvg com crop nulo não mexe no viewBox', () {
    final result = renderEditedSvg(
      _svg120x80,
      const SvgInfo(path: '', width: 120, height: 80),
      const SvgEditSettings(),
    );
    final root = XmlDocument.parse(result).rootElement;
    expect(root.getAttribute('viewBox'), '0 0 120 80');
    expect(root.childElements.any((e) => e.name.local == 'g'), isFalse);
  });

  test('renderEditedSvg lança SvgEditException pra XML malformado', () {
    expect(
      () => renderEditedSvg(
        '<svg><rect></svg>',
        const SvgInfo(path: '', width: 10, height: 10),
        const SvgEditSettings(),
      ),
      throwsA(isA<SvgEditException>()),
    );
  });

  test('renderEditedSvg lança SvgEditException pra raiz que não é <svg>', () {
    expect(
      () => renderEditedSvg(
        '<html></html>',
        const SvgInfo(path: '', width: 10, height: 10),
        const SvgEditSettings(),
      ),
      throwsA(isA<SvgEditException>()),
    );
  });
}
