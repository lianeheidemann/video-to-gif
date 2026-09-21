import 'dart:ui' show Color;

import 'package:xml/xml.dart';

import '../../../core/models/color_adjustments.dart';
import '../../../core/models/crop_rect.dart';
import '../models/svg_edit_settings.dart';
import '../models/svg_info.dart';

/// Erro amigável para qualquer passo de leitura/reescrita do SVG que não dá
/// pra completar — arquivo malformado, sem `viewBox`/tamanho válido, ou que o
/// `package:xml` rejeita mesmo tendo passado pelo `flutter_svg` na hora de
/// escolher o arquivo (são dois parsers independentes).
class SvgEditException implements Exception {
  const SvgEditException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Geometria resolvida da raiz `<svg>`: o `viewBox` (sempre presente depois
/// de [readSvgGeometry], sintetizado se faltava) e o tamanho de exibição
/// (`attrWidth`/`attrHeight`, vindos de [SvgInfo] — já resolvidos pelo
/// `flutter_svg`, nunca reparseados de `width`/`height`/`%` na mão aqui).
///
/// [scaleX]/[scaleY] convertem do espaço de exibição (o que `CropOverlay`/
/// `CroppedView` usam, igual a [SvgInfo.width]/[height]) para o espaço nativo
/// do `viewBox` — os dois só coincidem 1:1 quando `width`/`height` batem
/// exatamente com o `viewBox`, o que não é garantido (SVGs de ícone comuns
/// têm `viewBox="0 0 24 24"` com `width="512"`, por exemplo).
class SvgGeometry {
  const SvgGeometry({
    required this.viewBoxX,
    required this.viewBoxY,
    required this.viewBoxWidth,
    required this.viewBoxHeight,
    required this.attrWidth,
    required this.attrHeight,
  });

  final double viewBoxX;
  final double viewBoxY;
  final double viewBoxWidth;
  final double attrHeight;
  final double attrWidth;
  final double viewBoxHeight;

  double get scaleX => attrWidth == 0 ? 1 : viewBoxWidth / attrWidth;
  double get scaleY => attrHeight == 0 ? 1 : viewBoxHeight / attrHeight;
}

/// Atributo marcador usado nos elementos que este editor cria (`<g>` de
/// conteúdo, `<defs>` de filtro, `<rect>` de fundo) — para reconhecer e
/// reaproveitar/substituir o que ele mesmo já criou dentro de uma única
/// passada de [renderEditedSvg], em vez de duplicar a cada chamada.
const _marker = 'data-svgedit';

/// Lê (e normaliza) a geometria da raiz `<svg>` de [root]: se não houver
/// `viewBox`, sintetiza um a partir de [info] (ou 300x150, o padrão da
/// especificação, se nem isso existir) e já escreve esse `viewBox` de volta
/// — todo o resto deste arquivo assume que `viewBox` está presente e válido
/// depois desta chamada.
SvgGeometry readSvgGeometry(XmlElement root, SvgInfo info) {
  final attrWidth = info.width;
  final attrHeight = info.height;
  if (attrWidth <= 0 ||
      attrHeight <= 0 ||
      !attrWidth.isFinite ||
      !attrHeight.isFinite) {
    throw const SvgEditException('Este SVG não tem um tamanho válido.');
  }

  var vbX = 0.0, vbY = 0.0, vbW = attrWidth, vbH = attrHeight;
  final viewBoxAttr = root.getAttribute('viewBox');
  if (viewBoxAttr != null) {
    final parts = viewBoxAttr
        .trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (parts.length == 4 && parts.every((p) => p != null)) {
      vbX = parts[0]!;
      vbY = parts[1]!;
      vbW = parts[2]!;
      vbH = parts[3]!;
    }
  }
  if (vbW <= 0 || vbH <= 0) {
    vbX = 0;
    vbY = 0;
    vbW = attrWidth;
    vbH = attrHeight;
  }

  root.setAttribute(
    'viewBox',
    '${_num(vbX)} ${_num(vbY)} ${_num(vbW)} ${_num(vbH)}',
  );
  return SvgGeometry(
    viewBoxX: vbX,
    viewBoxY: vbY,
    viewBoxWidth: vbW,
    viewBoxHeight: vbH,
    attrWidth: attrWidth,
    attrHeight: attrHeight,
  );
}

/// Garante que todo filho visual de [root] (tudo exceto `<defs>`/`<title>`/
/// `<desc>`/`<metadata>`/`<style>`, que não são desenhados diretamente) está
/// dentro de um único `<g>` marcado, criando-o na primeira chamada e
/// reaproveitando nas seguintes (idempotente dentro de uma mesma passada de
/// [renderEditedSvg] — rotacionar, espelhar, aplicar filtro e opacidade
/// escrevem todos nesse mesmo grupo). Se a raiz já tiver um `transform`
/// próprio (incomum, mas válido), ele é movido para dentro do grupo em vez
/// de descartado.
XmlElement ensureContentGroup(XmlElement root) {
  for (final child in root.childElements) {
    if (child.name.local == 'g' && child.getAttribute(_marker) == '1') {
      return child;
    }
  }

  const excluded = {'defs', 'title', 'desc', 'metadata', 'style'};
  final moved = <XmlNode>[];
  root.children.removeWhere((node) {
    if (node is XmlElement && !excluded.contains(node.name.local)) {
      moved.add(node);
      return true;
    }
    return false;
  });

  final group = XmlElement.tag('g');
  group.setAttribute(_marker, '1');
  final rootTransform = root.getAttribute('transform');
  if (rootTransform != null && rootTransform.trim().isNotEmpty) {
    group.setAttribute('transform', rootTransform);
    root.removeAttribute('transform');
  }
  group.children.addAll(moved);
  root.children.add(group);
  return group;
}

/// Reescreve o `viewBox` de [root] para a sub-região [cropDisplayRect] (em
/// espaço de exibição, o mesmo que `CropOverlay` usa), convertida pra espaço
/// nativo via [geometry]. Quando `width`/`height` já existiam como
/// atributos, também são ajustados para o tamanho do recorte (na mesma
/// unidade de exibição) — sem isso, a proporção declarada por `width`/
/// `height` ficaria descasada da proporção do novo `viewBox`, e o SVG
/// abriria com barras vazias (`preserveAspectRatio` padrão) em vez de
/// mostrar só a janela recortada. O conteúdo em si nunca é esticado — só a
/// janela visível encolhe/cresce (ver decisão em `svg_edit_settings.dart`).
void cropSvg(XmlElement root, SvgGeometry geometry, CropRect cropDisplayRect) {
  final newX = geometry.viewBoxX + cropDisplayRect.x * geometry.scaleX;
  final newY = geometry.viewBoxY + cropDisplayRect.y * geometry.scaleY;
  final newW = cropDisplayRect.width * geometry.scaleX;
  final newH = cropDisplayRect.height * geometry.scaleY;
  root.setAttribute(
    'viewBox',
    '${_num(newX)} ${_num(newY)} ${_num(newW)} ${_num(newH)}',
  );
  if (root.getAttribute('width') != null &&
      root.getAttribute('height') != null) {
    root.setAttribute('width', _num(cropDisplayRect.width.toDouble()));
    root.setAttribute('height', _num(cropDisplayRect.height.toDouble()));
  }
}

/// Envolve o grupo de conteúdo num `rotate(graus, cx, cy)` em torno do
/// centro do `viewBox` *atual* de [root] (ou seja, já considerando um
/// recorte aplicado antes, se houver — cada passo lê a geometria corrente em
/// vez de uma copiada do início). Para 90°/270°, troca `width`/`height` (se
/// existirem como atributos literais) e os termos w/h do `viewBox`,
/// recentralizando no mesmo ponto.
void rotateSvg(XmlElement root, int quarterTurns) {
  final turns = quarterTurns % 4;
  if (turns == 0) return;

  final group = ensureContentGroup(root);
  final (vbX, vbY, vbW, vbH) = _currentViewBox(root);
  final cx = vbX + vbW / 2;
  final cy = vbY + vbH / 2;
  _composeTransform(group, 'rotate(${turns * 90} ${_num(cx)} ${_num(cy)})');

  if (turns == 1 || turns == 3) {
    final width = root.getAttribute('width');
    final height = root.getAttribute('height');
    if (width != null && height != null) {
      root.setAttribute('width', height);
      root.setAttribute('height', width);
    }
    final newVbW = vbH, newVbH = vbW;
    root.setAttribute(
      'viewBox',
      '${_num(cx - newVbW / 2)} ${_num(cy - newVbH / 2)} ${_num(newVbW)} ${_num(newVbH)}',
    );
  }
}

/// Envolve o grupo de conteúdo num espelhamento em torno do centro do
/// `viewBox` atual — mesma ideia de [rotateSvg], composto no mesmo
/// `transform` do grupo (a ordem de composição garante que espelhar depois
/// de girar espelha o resultado já girado, não o original).
void flipSvg(
  XmlElement root, {
  required bool horizontal,
  required bool vertical,
}) {
  if (!horizontal && !vertical) return;
  final group = ensureContentGroup(root);
  final (vbX, vbY, vbW, vbH) = _currentViewBox(root);
  final cx = vbX + vbW / 2;
  final cy = vbY + vbH / 2;
  final sx = horizontal ? -1 : 1;
  final sy = vertical ? -1 : 1;
  final tx = horizontal ? _num(2 * cx) : '0';
  final ty = vertical ? _num(2 * cy) : '0';
  _composeTransform(group, 'translate($tx,$ty) scale($sx,$sy)');
}

/// Insere (ou remove, com `color: null`) um `<rect>` cobrindo o `viewBox`
/// atual como primeiro filho de [root] — mesma semântica de
/// `FrameSettings.transparentBackground`: ligado (`color: null`), a área
/// fora da arte sai transparente; desligado, usa [color].
void applyBackgroundSvg(XmlElement root, Color? color) {
  root.children.removeWhere(
    (node) => node is XmlElement && node.getAttribute('$_marker-bg') == '1',
  );
  if (color == null) return;

  final (vbX, vbY, vbW, vbH) = _currentViewBox(root);
  final rect = XmlElement.tag('rect')
    ..setAttribute('x', _num(vbX))
    ..setAttribute('y', _num(vbY))
    ..setAttribute('width', _num(vbW))
    ..setAttribute('height', _num(vbH))
    ..setAttribute('fill', _colorToHex(color))
    ..setAttribute('$_marker-bg', '1');
  if (color.a < 1) {
    rect.setAttribute('fill-opacity', _num(color.a));
  }
  root.children.insert(0, rect);
}

/// Injeta (ou remove, quando não há nada ativo) um `<filter>` em `<defs>` e
/// referencia via `filter="url(#...)"` no grupo de conteúdo — combinando o
/// preset [type] com o ajuste fino [adjustments] (brilho/exposição/
/// contraste/realces/sombras/saturação/matiz/temperatura — a aba "Cor"), que
/// podem estar ativos ao mesmo tempo. Preto e branco usa `type="saturate"`
/// (o mesmo peso de luminância Rec. 709 de `color_adjustments.dart`, só que
/// nativo do SVG); inverter usa a matriz clássica de inversão, sem
/// equivalente primitivo; o ajuste fino usa a mesma matriz 4x5 de
/// `ColorAdjustments.matrix4x5`, convertida para a escala 0-1 do SVG (ver
/// [_svgColorMatrixValues]) — nenhuma fórmula é duplicada, as duas telas
/// (prévia em `SvgEditPage`, exportação aqui) usam a mesma conta.
///
/// Quando os dois estão ativos, o ajuste fino entra primeiro (mesma ordem
/// de composição da prévia em `SvgEditPage._croppedDecoratedPreview`),
/// encadeado via `in`/`result` para o preset atuar sobre o resultado já
/// ajustado, não sobre a arte original.
void applyFilterSvg(
  XmlElement root,
  SvgFilterType type, {
  ColorAdjustments adjustments = ColorAdjustments.neutral,
}) {
  final group = ensureContentGroup(root);
  group.removeAttribute('filter');
  root.children.removeWhere(
    (node) => node is XmlElement && node.getAttribute('$_marker-defs') == '1',
  );

  final matrices = <XmlElement>[];
  if (adjustments.hasAdjustments) {
    matrices.add(
      XmlElement.tag('feColorMatrix')
        ..setAttribute('type', 'matrix')
        ..setAttribute('values', _svgColorMatrixValues(adjustments.matrix4x5)),
    );
  }
  switch (type) {
    case SvgFilterType.grayscale:
      matrices.add(
        XmlElement.tag('feColorMatrix')
          ..setAttribute('type', 'saturate')
          ..setAttribute('values', '0'),
      );
    case SvgFilterType.invert:
      matrices.add(
        XmlElement.tag('feColorMatrix')
          ..setAttribute('type', 'matrix')
          ..setAttribute(
            'values',
            '-1 0 0 0 1  0 -1 0 0 1  0 0 -1 0 1  0 0 0 1 0',
          ),
      );
    case SvgFilterType.none:
      break;
  }
  if (matrices.isEmpty) return;

  for (var i = 1; i < matrices.length; i++) {
    matrices[i - 1].setAttribute('result', 'svgedit-step$i');
    matrices[i].setAttribute('in', 'svgedit-step$i');
  }

  final filter = XmlElement.tag('filter')..setAttribute('id', 'svgedit-filter');
  filter.children.addAll(matrices);
  final defs = XmlElement.tag('defs')
    ..setAttribute('$_marker-defs', '1')
    ..children.add(filter);
  root.children.insert(0, defs);
  group.setAttribute('filter', 'url(#svgedit-filter)');
}

/// Converte a matriz 4x5 de [ColorAdjustments.matrix4x5] (deslocamentos na
/// escala 0-255, convenção do `ColorFilter.matrix` do Flutter) para o
/// formato nativo de `<feColorMatrix type="matrix">` do SVG (mesma matriz,
/// só os 3 deslocamentos de cor — não o de alfa — na escala 0-1).
String _svgColorMatrixValues(List<double> matrix4x5) {
  final values = List<double>.from(matrix4x5);
  for (final i in [4, 9, 14]) {
    values[i] = values[i] / 255;
  }
  return values.map(_num).join(' ');
}

/// Define (ou remove, com `opacity: 1`) `opacity` no grupo de conteúdo.
void applyOpacitySvg(XmlElement root, double opacity) {
  final group = ensureContentGroup(root);
  final clamped = opacity.clamp(0.0, 1.0);
  if (clamped >= 1) {
    group.removeAttribute('opacity');
  } else {
    group.setAttribute('opacity', _num(clamped));
  }
}

/// Aplica [settings] inteiro sobre [originalSource] (sempre a partir do XML
/// original — nunca reedita um documento já editado numa chamada anterior,
/// pra desfazer/refazer nunca acumular grupos/transforms obsoletos) e
/// devolve o SVG resultante como texto. Ordem fixa: recorte → girar →
/// espelhar → fundo → filtro (ajuste fino + preset, nessa ordem — ver
/// [applyFilterSvg]) → opacidade.
String renderEditedSvg(
  String originalSource,
  SvgInfo info,
  SvgEditSettings settings,
) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(originalSource);
  } on SvgEditException {
    rethrow;
  } catch (_) {
    throw const SvgEditException(
      'Não foi possível interpretar este SVG (arquivo malformado ou com '
      'codificação não suportada).',
    );
  }

  try {
    final root = doc.rootElement;
    if (root.name.local != 'svg') {
      throw const SvgEditException('Este arquivo não é um SVG válido.');
    }

    final geometry = readSvgGeometry(root, info);
    final crop = settings.crop;
    if (crop != null) {
      cropSvg(root, geometry, crop);
    }
    rotateSvg(root, settings.rotationQuarterTurns);
    flipSvg(
      root,
      horizontal: settings.flipHorizontal,
      vertical: settings.flipVertical,
    );
    // Cada passo só mexe no documento quando tem algo a fazer — como este
    // método sempre reparte do XML original (nunca reedita um já editado),
    // um ajuste neutro (fundo transparente, sem filtro, opacidade 1) nunca
    // tem nada pra desfazer, e pular a chamada evita empacotar o conteúdo
    // num `<g>` à toa quando nada mudou.
    if (!settings.transparentBackground) {
      applyBackgroundSvg(root, settings.backgroundColor);
    }
    if (settings.filterType != SvgFilterType.none ||
        settings.adjustments.hasAdjustments) {
      applyFilterSvg(
        root,
        settings.filterType,
        adjustments: settings.adjustments,
      );
    }
    if (settings.opacity < 1) {
      applyOpacitySvg(root, settings.opacity);
    }

    return doc.toXmlString();
  } on SvgEditException {
    rethrow;
  } catch (_) {
    throw const SvgEditException('Não foi possível gerar o SVG editado.');
  }
}

(double, double, double, double) _currentViewBox(XmlElement root) {
  final raw = root.getAttribute('viewBox');
  if (raw == null) {
    throw const SvgEditException('Este SVG não tem um viewBox válido.');
  }
  final parts = raw.trim().split(RegExp(r'[\s,]+')).map(double.parse).toList();
  if (parts.length != 4) {
    throw const SvgEditException('Este SVG não tem um viewBox válido.');
  }
  return (parts[0], parts[1], parts[2], parts[3]);
}

/// Acrescenta [fragment] à ESQUERDA do `transform` já existente em [group]
/// (se houver) — na lista de transforms do SVG, o da esquerda é aplicado por
/// último, então prepender garante que cada novo passo do pipeline atua
/// sobre o resultado do passo anterior, não o contrário.
void _composeTransform(XmlElement group, String fragment) {
  final existing = group.getAttribute('transform');
  group.setAttribute(
    'transform',
    existing == null || existing.trim().isEmpty
        ? fragment
        : '$fragment $existing',
  );
}

String _colorToHex(Color color) {
  String two(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${two((color.r * 255).round())}${two((color.g * 255).round())}${two((color.b * 255).round())}';
}

/// Formata um número para atributo XML: inteiro sem `.0` quando exato, senão
/// até 4 casas decimais sem zeros à direita — evita tanto `12.0` feio quanto
/// arrastar erro de ponto flutuante (`12.000000000000002`) pro arquivo salvo.
String _num(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var text = value.toStringAsFixed(4);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}
