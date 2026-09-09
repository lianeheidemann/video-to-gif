import 'package:flutter/material.dart';

/// Folha "Como deixar o GIF mais leve": o que pesa num GIF e o que mexer
/// para reduzir. Mora na home (junto do ícone de interrogação), e não na
/// tela de edição, para a barra de lá ficar só com o que age sobre o GIF.
class GifWeightHelpSheet extends StatelessWidget {
  const GifWeightHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget item(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'O que deixa um GIF pesado',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            item(
              '1. Duração — efeito direto',
              'Cada segundo adiciona novos quadros. Cortar um trecho é uma das formas mais eficientes de reduzir o tamanho.',
            ),
            item(
              '2. Resolução — efeito muito forte',
              'Quanto maior a área de cada quadro, maior tende a ser o GIF. 480 px costuma funcionar bem para compartilhamento.',
            ),
            item(
              '3. FPS — fluidez versus tamanho',
              'Mais quadros deixam o movimento mais suave, mas aumentam o arquivo. 12 FPS é um bom ponto de partida.',
            ),
            item(
              '4. Janela de recorte',
              'Segure as bolinhas dos cantos da moldura na própria prévia para redimensionar. Formatos fixos preservam a proporção; Personalizado libera largura e altura.',
            ),
            item(
              '5. Cores e suavização',
              'Mais cores e dither preservam gradientes e detalhes, mas podem reduzir a eficiência da compressão.',
            ),
            item(
              'Por que medir novamente?',
              'A estimativa inicial é aproximada. Ao medir, o app usa o FFmpeg em uma pequena amostra do próprio vídeo para calibrar o cálculo.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Abre a folha — mesmo formato dos outros sheets do app.
void showGifWeightHelpSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const GifWeightHelpSheet(),
  );
}
