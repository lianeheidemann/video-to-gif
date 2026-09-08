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
    this.marginRatio = 0.03,
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

  /// Margem proporcional ao menor lado do canvas, entre células e ao redor
  /// da montagem — ver [CollageLayout.cellRectsFor].
  final double marginRatio;

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
    double? marginRatio,
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
      marginRatio: marginRatio ?? this.marginRatio,
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
