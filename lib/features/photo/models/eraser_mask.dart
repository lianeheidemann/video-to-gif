import 'dart:math' as math;
import 'dart:ui'
    show
        BlendMode,
        Canvas,
        Color,
        Offset,
        Paint,
        PaintingStyle,
        Path,
        Rect,
        StrokeCap,
        StrokeJoin;

/// Qual ferramenta da aba "Borracha" está ativa.
enum EraserTool {
  brush('Pincel'),
  unbrush('Apagar seleção'),
  lasso('Laço'),
  rectangle('Retângulo');

  const EraserTool(this.label);

  final String label;

  /// As duas que desenham área fechada — o gesto delas é o mesmo (arrastar e
  /// soltar fecha a forma), só muda o contorno resultante.
  bool get isArea => this == EraserTool.lasso || this == EraserTool.rectangle;

  /// `true` quando a ferramenta tira da seleção em vez de somar.
  bool get subtracts => this == EraserTool.unbrush;
}

/// Em que resolução a janela de contexto é processada. O custo do inpainting
/// cresce com o quadrado do lado, então cada degrau aqui é ~2x o anterior.
///
/// Importante: o teto se aplica à **janela em volta da máscara**, não à foto
/// inteira. Apagar algo pequeno (marca d'água, uma placa, alguém ao longe)
/// costuma caber abaixo do teto e sai em resolução nativa, sem redução
/// nenhuma.
enum EraserQuality {
  fast('Rápida', 512),
  normal('Normal', 768),
  high('Alta', 1024);

  const EraserQuality(this.label, this.maxWorkingSide);

  final String label;

  /// Maior lado, em pixels, da janela entregue ao algoritmo.
  final int maxWorkingSide;
}

/// Um traço da seleção, em **pixels da foto original**.
///
/// Guardar geometria (e não um bitmap) é o que permite rasterizar a mesma
/// seleção na escala da prévia e na escala de trabalho do algoritmo sem
/// nenhuma perda — e o que deixa a máscara sobreviver a um zoom.
class EraserStroke {
  const EraserStroke({
    required this.points,
    this.radius = 0,
    this.subtract = false,
    this.closed = false,
  });

  /// O caminho por onde o dedo passou (pincel) ou o contorno da área (laço,
  /// retângulo). Um retângulo entra aqui como seus quatro cantos.
  final List<Offset> points;

  /// Metade da espessura do pincel. Ignorado quando [closed].
  final double radius;

  /// `true` tira da seleção em vez de somar.
  final bool subtract;

  /// `true` preenche a área fechada pelos pontos; `false` traça a linha com
  /// [radius] de espessura e pontas arredondadas.
  final bool closed;

  /// Caixa que envolve este traço, já com a espessura do pincel somada.
  Rect? get bounds {
    if (points.isEmpty) return null;
    var left = points.first.dx;
    var top = points.first.dy;
    var right = left;
    var bottom = top;
    for (final p in points) {
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
    final grow = closed ? 0.0 : radius;
    return Rect.fromLTRB(left - grow, top - grow, right + grow, bottom + grow);
  }
}

/// A seleção inteira: uma lista **ordenada** de traços, porque somar e tirar
/// só faz sentido na ordem em que a pessoa desenhou.
class EraserMask {
  const EraserMask({this.strokes = const []});

  final List<EraserStroke> strokes;

  static const empty = EraserMask();

  /// Vazia de verdade: sem traços, ou só com traços que tiram (que sozinhos
  /// não marcam nada).
  bool get isEmpty => !strokes.any((s) => !s.subtract && s.points.isNotEmpty);

  EraserMask add(EraserStroke stroke) =>
      EraserMask(strokes: [...strokes, stroke]);

  /// Remove o último traço — o desfazer de dentro da própria seleção, antes
  /// de apagar de verdade.
  EraserMask removeLast() => strokes.isEmpty
      ? this
      : EraserMask(strokes: strokes.sublist(0, strokes.length - 1));

  /// Caixa que envolve tudo o que **soma** à seleção, cortada aos limites da
  /// foto. `null` quando não há nada marcado.
  ///
  /// Só os traços aditivos contam: um traço que tira nunca aumenta a área a
  /// preencher, então incluí-lo só faria a janela de contexto crescer à toa.
  Rect? boundsIn(int photoWidth, int photoHeight) {
    Rect? result;
    for (final stroke in strokes) {
      if (stroke.subtract) continue;
      final bounds = stroke.bounds;
      if (bounds == null) continue;
      result = result == null ? bounds : result.expandToInclude(bounds);
    }
    if (result == null) return null;

    final clipped = result.intersect(
      Rect.fromLTWH(0, 0, photoWidth.toDouble(), photoHeight.toDouble()),
    );
    return clipped.isEmpty ? null : clipped;
  }
}

/// Desenha [mask] no canvas, em coordenadas de pixel da foto.
///
/// Quem chama aplica a escala antes (`canvas.scale(...)`), de modo que a
/// espessura do pincel acompanhe sozinha. As cores e os modos de mistura
/// ficam por conta do chamador porque os dois usos querem coisas diferentes:
/// a prévia pinta um véu translúcido e tira com [BlendMode.clear]; a
/// rasterização pinta branco e tira com preto opaco.
///
/// Esta função é a **única** que sabe traduzir traços em pixels — a prévia e
/// o que o algoritmo recebe saem exatamente daqui, então nunca divergem.
void paintEraserMask(
  Canvas canvas,
  EraserMask mask, {
  required Color addColor,
  required Color subtractColor,
  BlendMode addBlendMode = BlendMode.srcOver,
  BlendMode subtractBlendMode = BlendMode.srcOver,
}) {
  for (final stroke in mask.strokes) {
    if (stroke.points.isEmpty) continue;

    final paint = Paint()
      ..color = stroke.subtract ? subtractColor : addColor
      ..blendMode = stroke.subtract ? subtractBlendMode : addBlendMode
      ..isAntiAlias = true;

    if (stroke.closed) {
      canvas.drawPath(
        Path()..addPolygon(stroke.points, true),
        paint..style = PaintingStyle.fill,
      );
      continue;
    }

    if (stroke.points.length == 1) {
      // Um toque sem arrasto ainda tem que marcar um ponto redondo.
      canvas.drawCircle(
        stroke.points.first,
        stroke.radius,
        paint..style = PaintingStyle.fill,
      );
      continue;
    }

    canvas.drawPath(
      Path()..addPolygon(stroke.points, false),
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.radius * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

/// A janela de contexto em volta da máscara: a caixa do buraco mais uma
/// margem generosa, cortada aos limites da foto.
///
/// A margem é de onde o algoritmo tira textura. Curta demais e não há o que
/// copiar; larga demais e a janela fica grande, obrigando a uma redução maior
/// (e a um resultado mais macio) sem ganho nenhum.
Rect eraserContextWindow(Rect holeBounds, int photoWidth, int photoHeight) {
  final margin = math.max(
    0.6 * math.max(holeBounds.width, holeBounds.height),
    64.0,
  );
  final expanded = holeBounds.inflate(margin);
  final photo = Rect.fromLTWH(
    0,
    0,
    photoWidth.toDouble(),
    photoHeight.toDouble(),
  );
  return Rect.fromLTRB(
    expanded.left.clamp(0.0, photo.right).floorToDouble(),
    expanded.top.clamp(0.0, photo.bottom).floorToDouble(),
    expanded.right.clamp(0.0, photo.right).ceilToDouble(),
    expanded.bottom.clamp(0.0, photo.bottom).ceilToDouble(),
  );
}

/// Por quanto a janela é reduzida antes de entrar no algoritmo. Nunca passa
/// de 1: ampliar a janela só custaria tempo, jamais inventaria detalhe.
double eraserWorkingScale(Rect window, EraserQuality quality) {
  final longest = math.max(window.width, window.height);
  if (longest <= 0) return 1;
  return math.min(1, quality.maxWorkingSide / longest);
}
