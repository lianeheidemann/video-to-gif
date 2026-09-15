import 'dart:ui' show Color, ColorFilter;

import 'color_adjustments.dart';
import 'crop_rect.dart';
import 'default_colors.dart';

/// Filtro de cor aplicado ao SVG inteiro — via `ColorFiltered` na prévia e
/// via `<feColorMatrix>` (nativo do SVG, sem rasterizar) na exportação.
enum SvgFilterType {
  none('Nenhum'),
  grayscale('Preto e branco'),
  invert('Inverter');

  const SvgFilterType(this.label);

  final String label;
}

/// Configurações da tela "Editar SVG": tudo imutável, num objeto só, para o
/// mesmo padrão de desfazer/refazer de `FrameSettings` (pilhas do próprio
/// objeto, ver `SvgEditPage._updateSettings`/`_pushUndoCheckpoint`).
///
/// Não existe um campo separado de "tamanho do canvas": digitar uma
/// largura/altura na aba "Recorte" edita o mesmo [crop], recentralizando —
/// exatamente como o recorte de vídeo já funciona em `EditorPage`. Esticar a
/// arte não é uma opção; encolher/ampliar a janela é.
class SvgEditSettings {
  const SvgEditSettings({
    this.crop,
    this.rotationQuarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.transparentBackground = true,
    this.backgroundColor = defaultBackgroundColor,
    this.filterType = SvgFilterType.none,
    this.opacity = 1.0,
  });

  /// `null` = o SVG inteiro, no tamanho nativo (`SvgInfo.width`/`height`).
  /// Em espaço de exibição — o mesmo que `CropOverlay`/`CroppedView` usam,
  /// não o `viewBox` nativo do XML (a conversão entre os dois espaços é
  /// feita só na exportação, em `svg_xml_editor.dart`).
  final CropRect? crop;

  /// 0 a 3, cada unidade = 90° no sentido horário.
  final int rotationQuarterTurns;

  final bool flipHorizontal;
  final bool flipVertical;

  /// Ligado (padrão), a área fora da arte sai transparente no SVG salvo.
  /// Desligado, ela usa [backgroundColor] — mesma semântica de
  /// `FrameSettings.transparentBackground`.
  final bool transparentBackground;
  final Color backgroundColor;

  final SvgFilterType filterType;

  /// 0 a 1.
  final double opacity;

  /// Filtro equivalente ao [filterType] para a prévia (widget), com os
  /// mesmos coeficientes usados na exportação (`svg_xml_editor.dart`'s
  /// `applyFilterSvg`) — preto e branco reaproveita
  /// `buildAdjustmentColorFilter` (saturação -1, os mesmos pesos de
  /// luminância que o `<feColorMatrix type="saturate">` do SVG usa);
  /// inverter é a matriz clássica de inversão, sem equivalente em
  /// `ColorAdjustments`.
  ColorFilter? get previewColorFilter => switch (filterType) {
    SvgFilterType.none => null,
    SvgFilterType.grayscale => buildAdjustmentColorFilter(
      brightness: 0,
      contrast: 0,
      saturation: -1,
    ),
    SvgFilterType.invert => const ColorFilter.matrix([
      -1, 0, 0, 0, 255, //
      0, -1, 0, 0, 255, //
      0, 0, -1, 0, 255, //
      0, 0, 0, 1, 0, //
    ]),
  };

  /// Cria uma cópia substituindo apenas os campos informados.
  /// [clearCrop] remove o recorte mesmo que [crop] não seja passado.
  SvgEditSettings copyWith({
    CropRect? crop,
    bool clearCrop = false,
    int? rotationQuarterTurns,
    bool? flipHorizontal,
    bool? flipVertical,
    bool? transparentBackground,
    Color? backgroundColor,
    SvgFilterType? filterType,
    double? opacity,
  }) {
    return SvgEditSettings(
      crop: clearCrop ? null : (crop ?? this.crop),
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      transparentBackground:
          transparentBackground ?? this.transparentBackground,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      filterType: filterType ?? this.filterType,
      opacity: opacity ?? this.opacity,
    );
  }
}
