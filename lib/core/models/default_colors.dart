/// As cores que já vêm escolhidas em "Fundo" e em "Moldura"/"Borda" nas três
/// telas de edição — "Editar GIF", "Colocar moldura" e "Montagem".
///
/// Ficam aqui, e não repetidas em cada modelo, porque o ponto delas é
/// justamente ser a mesma cor nas três telas: mudar de ideia sobre o padrão
/// é mexer num lugar só.
///
/// Nenhuma das duas liga nada sozinha. O fundo continua vindo transparente
/// por padrão (`FrameSettings.transparentBackground` e
/// `CollageBackgroundMode.transparent`) e a borda continua vindo com
/// espessura zero — estas cores são as que aparecem quando você liga o fundo
/// ou dá espessura à moldura.
library;

import 'dart:ui' show Color;

/// Lilás claro. É a mesma cor semente do tema (`theme.dart`) e uma das
/// amostras fixas da paleta, então o fundo já sai combinando com o app.
const defaultBackgroundColor = Color(0xFFC9A8FF);

/// Roxo médio: escuro o bastante para a moldura se separar do fundo lilás
/// sem virar preto.
const defaultFrameColor = Color(0xFF8370B0);

/// Roxo escuro, para o texto da montagem — mesmo espírito das duas acima,
/// só que aqui não há "ligar/desligar": todo texto novo já nasce com esta
/// cor (ver [CollageTextItem]).
const defaultTextColor = Color(0xFF544181);
