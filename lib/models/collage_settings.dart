import 'dart:ui' show Color;

import 'collage_background.dart';
import 'collage_cell.dart';
import 'collage_layout.dart';
import 'collage_sticker.dart';
import 'collage_text.dart';
import 'photo_info.dart';

/// Todas as configurações de uma montagem: como as fotos estão organizadas
/// ([layout]/[cells]), margem, proporção do canvas, borda/arredondamento
/// externos, fundo e as sobreposições (stickers/texto).
class CollageSettings {
  const CollageSettings({
    required this.layout,
    this.cells = const [],
    this.outerMarginRatio = 0.03,
    this.innerMarginRatio = 0.03,
    this.aspectRatio = 1.0,
    this.cornerRatio = 0.0,
    this.borderThicknessAtReference = 0.0,
    this.borderColor = const Color(0xFFFFFFFF),
    this.background = const CollageBackground(),
    this.stickers = const [],
    this.texts = const [],
  });

  final CollageLayout layout;
  final List<CollageCellSettings> cells;

  /// Margem proporcional ao menor lado do canvas, da borda da montagem até
  /// as fotos — ver [CollageLayout.cellRectsFor]. Independente de
  /// [innerMarginRatio]: dá para ter uma sem a outra.
  final double outerMarginRatio;

  /// Margem proporcional ao menor lado do canvas, só entre as fotos (o
  /// "gutter" da grade) — ver [CollageLayout.cellRectsFor].
  final double innerMarginRatio;

  /// Proporção largura/altura de todo o canvas da montagem.
  final double aspectRatio;

  /// Arredondamento do canto de toda a montagem (não de cada célula — ver
  /// [CollageCellSettings.cornerRatio] para isso), como razão do menor lado
  /// do canvas.
  final double cornerRatio;

  /// Espessura da borda externa da montagem, em pixels numa largura de
  /// referência de 480px — mesma unidade de [FrameSettings.thicknessAtReference].
  final double borderThicknessAtReference;
  final Color borderColor;

  final CollageBackground background;
  final List<CollageSticker> stickers;
  final List<CollageTextItem> texts;

  static const minMarginRatio = 0.0;
  static const maxMarginRatio = 0.12;
  static const maxCornerRatio = 0.5;
  static const referenceWidth = 480.0;
  static const maxBorderThickness = 24.0;
  static const minPhotos = 2;

  /// Presets de proporção comuns em redes sociais e impressão, além do
  /// slider livre.
  static const aspectPresets = <(String label, double ratio)>[
    ('1:1', 1.0),
    ('4:5', 4 / 5),
    ('5:4', 5 / 4),
    ('2:3', 2 / 3),
    ('3:2', 3 / 2),
    ('3:4', 3 / 4),
    ('4:3', 4 / 3),
    ('9:16', 9 / 16),
    ('16:9', 16 / 9),
    ('2:1', 2.0),
    ('1:2', 0.5),
  ];

  double borderThicknessFor(double canvasWidth) {
    if (canvasWidth <= 0) return borderThicknessAtReference;
    return borderThicknessAtReference * (canvasWidth / referenceWidth);
  }

  double cornerRadiusFor(double shorterSide) {
    if (shorterSide <= 0) return 0;
    return shorterSide * cornerRatio.clamp(0.0, maxCornerRatio);
  }

  CollageSettings copyWith({
    CollageLayout? layout,
    List<CollageCellSettings>? cells,
    double? outerMarginRatio,
    double? innerMarginRatio,
    double? aspectRatio,
    double? cornerRatio,
    double? borderThicknessAtReference,
    Color? borderColor,
    CollageBackground? background,
    List<CollageSticker>? stickers,
    List<CollageTextItem>? texts,
  }) {
    return CollageSettings(
      layout: layout ?? this.layout,
      cells: cells ?? this.cells,
      outerMarginRatio: outerMarginRatio ?? this.outerMarginRatio,
      innerMarginRatio: innerMarginRatio ?? this.innerMarginRatio,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      cornerRatio: cornerRatio ?? this.cornerRatio,
      borderThicknessAtReference:
          borderThicknessAtReference ?? this.borderThicknessAtReference,
      borderColor: borderColor ?? this.borderColor,
      background: background ?? this.background,
      stickers: stickers ?? this.stickers,
      texts: texts ?? this.texts,
    );
  }

  /// Substitui a célula em [index] inteira.
  CollageSettings replacingCell(int index, CollageCellSettings cell) {
    final updated = [...cells];
    updated[index] = cell;
    return copyWith(cells: updated);
  }

  /// Troca as duas células por completo (foto, enquadramento, rotação/
  /// espelhamento e ajustes de cor) — só a posição/tamanho na grade
  /// permanece de cada uma, como se as fotos tivessem trocado de lugar.
  CollageSettings swappingCells(int a, int b) {
    if (a == b) return this;
    final updated = [...cells];
    final tmp = updated[a];
    updated[a] = updated[b];
    updated[b] = tmp;
    return copyWith(cells: updated);
  }

  /// Aplica [update] a todas as células de uma vez — usado pelos controles
  /// de borda em lote ("todas as fotos"), quando não faz sentido mais uma
  /// foto divergir da outra.
  CollageSettings updatingAllCells(
    CollageCellSettings Function(CollageCellSettings cell) update,
  ) => copyWith(cells: [for (final c in cells) update(c)]);

  /// Célula que representa o estilo em vigor para as fotos — borda,
  /// arredondamento e fundo, os três eixos que as abas "Borda e cantos" e
  /// "Fundo" aplicam em lote. É a primeira célula com foto (uma célula vazia
  /// pode nunca ter passado por esses controles); sem nenhuma foto ainda,
  /// vale o padrão.
  CollageCellSettings get cellStyleTemplate {
    for (final cell in cells) {
      if (cell.hasPhoto) return cell;
    }
    return const CollageCellSettings();
  }

  /// [cell] com o estilo compartilhado das outras fotos ([cellStyleTemplate])
  /// por cima — enquadramento, recorte e ajustes de cor da própria célula
  /// ficam como estão. Usado ao criar células novas e ao pôr uma foto numa
  /// célula vazia: a foto que chega depois já entra com a mesma borda, o
  /// mesmo canto e o mesmo fundo das que já estavam lá.
  CollageCellSettings withSharedCellStyle(CollageCellSettings cell) {
    final template = cellStyleTemplate;
    return cell.copyWith(
      cornerRatio: template.cornerRatio,
      borderThicknessAtReference: template.borderThicknessAtReference,
      borderColor: template.borderColor,
      background: template.background,
    );
  }

  /// Adiciona um sticker acima de todas as sobreposições existentes.
  CollageSettings addingSticker(CollageSticker sticker) =>
      copyWith(stickers: [...stickers, sticker]);

  CollageSettings replacingSticker(String id, CollageSticker sticker) =>
      copyWith(stickers: [for (final s in stickers) s.id == id ? sticker : s]);

  CollageSettings removingSticker(String id) =>
      copyWith(stickers: stickers.where((s) => s.id != id).toList());

  /// Adiciona um texto acima de todas as sobreposições existentes.
  CollageSettings addingText(CollageTextItem item) =>
      copyWith(texts: [...texts, item]);

  CollageSettings replacingText(String id, CollageTextItem item) =>
      copyWith(texts: [for (final t in texts) t.id == id ? item : t]);

  CollageSettings removingText(String id) =>
      copyWith(texts: texts.where((t) => t.id != id).toList());

  /// Próximo `zIndex` livre entre stickers e textos, para uma nova
  /// sobreposição sempre nascer por cima de tudo.
  int get nextZIndex {
    var max = 0;
    for (final s in stickers) {
      if (s.zIndex > max) max = s.zIndex;
    }
    for (final t in texts) {
      if (t.zIndex > max) max = t.zIndex;
    }
    return max + 1;
  }

  /// Monta uma [CollageSettings] inicial para [layout], criando uma célula
  /// por foto em [photos] (na ordem em que foram escolhidas). Quando há
  /// menos fotos que células, as células restantes ficam vazias
  /// ([CollageCellSettings.photoPath] nulo); quando há mais fotos que
  /// células, o excedente é ignorado — a tela decide se pede outro layout
  /// ou descarta o excedente.
  factory CollageSettings.forLayout(
    CollageLayout layout,
    List<PhotoInfo> photos,
  ) {
    final cellCount = layout.cellCount;
    final cells = List<CollageCellSettings>.generate(cellCount, (i) {
      if (i >= photos.length) return const CollageCellSettings();
      final photo = photos[i];
      return CollageCellSettings(
        photoPath: photo.path,
        photoWidth: photo.width,
        photoHeight: photo.height,
      );
    });
    return CollageSettings(layout: layout, cells: cells);
  }
}
