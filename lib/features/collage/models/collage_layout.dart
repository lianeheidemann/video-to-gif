import 'dart:ui' show Rect, Size;

/// Como as células de uma montagem estão organizadas: modelos prontos (linha,
/// coluna, grades fixas) ou uma grade livre com número de linhas/colunas
/// escolhido pelo usuário.
enum CollageLayoutKind {
  row('Linha'),
  column('Coluna'),
  grid2x2('Grade 2x2'),
  grid2x3('Grade 2x3'),
  grid3x3('Grade 3x3'),
  freeGrid('Grade livre');

  const CollageLayoutKind(this.label);

  final String label;
}

/// Organização das fotos dentro da montagem: quantas células existem e como
/// elas se distribuem em linhas/colunas. [columns]/[rows] só têm significado
/// para [CollageLayoutKind.row] (usa [columns] como quantidade de fotos),
/// [CollageLayoutKind.column] (usa [rows]) e [CollageLayoutKind.freeGrid]
/// (usa os dois) — as grades fixas (2x2/2x3/3x3) já têm sua contagem
/// implícita no próprio nome.
class CollageLayout {
  const CollageLayout({required this.kind, this.columns = 1, this.rows = 1});

  final CollageLayoutKind kind;
  final int columns;
  final int rows;

  /// Quantas colunas a grade realmente tem, resolvendo os nomes fixos.
  int get _effectiveColumns => switch (kind) {
    CollageLayoutKind.row => columns < 1 ? 1 : columns,
    CollageLayoutKind.column => 1,
    CollageLayoutKind.grid2x2 => 2,
    CollageLayoutKind.grid2x3 => 2,
    CollageLayoutKind.grid3x3 => 3,
    CollageLayoutKind.freeGrid => columns < 1 ? 1 : columns,
  };

  /// Quantas linhas a grade realmente tem, resolvendo os nomes fixos.
  int get _effectiveRows => switch (kind) {
    CollageLayoutKind.row => 1,
    CollageLayoutKind.column => rows < 1 ? 1 : rows,
    CollageLayoutKind.grid2x2 => 2,
    CollageLayoutKind.grid2x3 => 3,
    CollageLayoutKind.grid3x3 => 3,
    CollageLayoutKind.freeGrid => rows < 1 ? 1 : rows,
  };

  /// Número de fotos que esta organização comporta.
  int get cellCount => _effectiveColumns * _effectiveRows;

  /// Retângulos de cada célula dentro de um canvas de [canvasSize], já
  /// aplicando [outerMarginRatio] (da borda da montagem até as fotos) e
  /// [innerMarginRatio] (só entre as fotos) — ambos proporcionais ao menor
  /// lado do canvas, mesmo espírito de [FrameSettings.cornerRatio], e
  /// independentes entre si. Única fonte de geometria: usada pela prévia ao
  /// vivo e pela exportação, para as duas nunca ficarem fora de sincronia.
  List<Rect> cellRectsFor(
    Size canvasSize, {
    required double outerMarginRatio,
    required double innerMarginRatio,
  }) {
    final cols = _effectiveColumns;
    final rowsN = _effectiveRows;
    final outerMargin = canvasSize.shortestSide * outerMarginRatio;
    final innerMargin = canvasSize.shortestSide * innerMarginRatio;

    final availableWidth =
        (canvasSize.width - outerMargin * 2 - innerMargin * (cols - 1)).clamp(
          0.0,
          canvasSize.width,
        );
    final availableHeight =
        (canvasSize.height - outerMargin * 2 - innerMargin * (rowsN - 1)).clamp(
          0.0,
          canvasSize.height,
        );
    final cellWidth = availableWidth / cols;
    final cellHeight = availableHeight / rowsN;

    final rects = <Rect>[];
    for (var r = 0; r < rowsN; r++) {
      for (var c = 0; c < cols; c++) {
        final left = outerMargin + c * (cellWidth + innerMargin);
        final top = outerMargin + r * (cellHeight + innerMargin);
        rects.add(Rect.fromLTWH(left, top, cellWidth, cellHeight));
      }
    }
    return rects;
  }

  CollageLayout copyWith({CollageLayoutKind? kind, int? columns, int? rows}) =>
      CollageLayout(
        kind: kind ?? this.kind,
        columns: columns ?? this.columns,
        rows: rows ?? this.rows,
      );

  /// [count] fotos lado a lado, uma única linha.
  factory CollageLayout.row(int count) =>
      CollageLayout(kind: CollageLayoutKind.row, columns: count, rows: 1);

  /// [count] fotos empilhadas, uma única coluna.
  factory CollageLayout.column(int count) =>
      CollageLayout(kind: CollageLayoutKind.column, columns: 1, rows: count);

  /// Grade livre de [columns] colunas por [rows] linhas.
  factory CollageLayout.grid(int columns, int rows) => CollageLayout(
    kind: CollageLayoutKind.freeGrid,
    columns: columns,
    rows: rows,
  );

  static const minFreeGridSpan = 1;
  static const maxFreeGridSpan = 4;

  /// Faixa de contagem de fotos para os layouts [CollageLayoutKind.row]/
  /// [CollageLayoutKind.column] — mesmos limites já usados como padrão ao
  /// trocar para um desses dois layouts.
  static const minRowColumnCount = 2;
  static const maxRowColumnCount = 8;
}
