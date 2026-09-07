#!/usr/bin/env python3
"""Gera o ícone do app e as imagens da ficha da Play Store.

Rode a partir da raiz do projeto:

    pip install Pillow
    python3 tool/gerar_icones.py

Produz:
  assets/icone.png                                    1024x1024, mestre
  android/app/src/main/res/mipmap-*/ic_launcher.png   ícone legado
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png
  loja/icone_512.png                                  ícone da ficha da loja
  loja/grafico_destaque_1024x500.png                  gráfico de destaque

O ícone é redimensionado a partir de ``assets/icon/icon-v4.png``. O desenho
vetorial antigo continua sendo usado somente no gráfico de destaque.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parent.parent
ICONE_FONTE = RAIZ / 'assets/icon/icon-v4.png'

# Paleta: mesma semente de cor usada no tema do app (lib/theme.dart).
ROXO_CLARO = (155, 111, 224)
ROXO_ESCURO = (91, 51, 168)
ROXO_SOLIDO = (124, 83, 201)
BRANCO = (255, 255, 255)

SS = 4  # fator de supersampling

DENSIDADES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}


def gradiente(largura, altura, inicio, fim):
    """Gradiente diagonal, do canto superior esquerdo ao inferior direito."""
    base = Image.new('RGB', (largura, altura))
    pixels = base.load()
    for y in range(altura):
        for x in range(largura):
            t = (x / max(largura - 1, 1) + y / max(altura - 1, 1)) / 2
            pixels[x, y] = tuple(
                round(inicio[c] + (fim[c] - inicio[c]) * t) for c in range(3)
            )
    return base


def desenhar_marca(desenho, s, centro_x, centro_y, cor_triangulo):
    """Três quadros empilhados com um botão de play no da frente.

    A pilha representa os quadros do GIF; o play, o vídeo de origem. Só
    formas cheias e contrastadas, para continuar legível a 48 px.
    """
    fw, fh = 0.62 * s, 0.52 * s
    raio = 0.085 * s
    passo = 0.055 * s

    # Centraliza o grupo levando em conta o deslocamento das camadas de trás.
    x0 = centro_x - fw / 2 - passo
    y0 = centro_y - fh / 2 + passo

    camadas = [
        (2, 110),  # quadro do fundo, mais apagado
        (1, 180),
        (0, 255),  # quadro da frente, opaco
    ]

    for indice, alfa in camadas:
        dx = passo * indice
        dy = -passo * indice
        desenho.rounded_rectangle(
            [x0 + dx, y0 + dy, x0 + dx + fw, y0 + dy + fh],
            radius=raio,
            fill=BRANCO + (alfa,),
        )

    # Botão de play dentro do quadro da frente.
    lado = 0.20 * s
    cx = x0 + fw / 2
    cy = y0 + fh / 2
    altura_tri = lado * 0.95
    desenho.polygon(
        [
            (cx - lado * 0.38, cy - altura_tri),
            (cx - lado * 0.38, cy + altura_tri),
            (cx + lado * 0.85, cy),
        ],
        fill=cor_triangulo + (255,),
    )


def icone_completo(tamanho):
    """Ícone quadrado com fundo, para o launcher legado e para a loja."""
    with Image.open(ICONE_FONTE) as fonte:
        return fonte.convert('RGBA').resize((tamanho, tamanho), Image.LANCZOS)


def icone_adaptativo_frente(tamanho):
    """Camada da frente do ícone adaptativo (fundo transparente).

    O Android pode recortar o ícone em círculo, quadrado ou gota. Só os 66%
    centrais são garantidos, então a marca fica menor aqui do que no ícone
    legado.
    """
    camada = Image.new('RGBA', (tamanho, tamanho), (0, 0, 0, 0))
    # O centro de 66% é a área segura do ícone adaptativo. Assim o launcher
    # pode aplicar máscaras diferentes sem cortar elementos da nova arte.
    lado = round(tamanho * 2 / 3)
    with Image.open(ICONE_FONTE) as fonte:
        icone = fonte.convert('RGBA').resize((lado, lado), Image.LANCZOS)
    margem = (tamanho - lado) // 2
    camada.alpha_composite(icone, (margem, margem))
    return camada


def fonte(tamanho, negrito=True):
    nome = 'DejaVuSans-Bold.ttf' if negrito else 'DejaVuSans.ttf'
    return ImageFont.truetype(f'/usr/share/fonts/truetype/dejavu/{nome}', tamanho)


def grafico_destaque():
    """Banner 1024x500 exigido pela ficha da Play Store."""
    largura, altura = 1024, 500
    imagem = gradiente(largura, altura, ROXO_CLARO, ROXO_ESCURO).convert('RGBA')

    marca = Image.new('RGBA', (300 * SS, 300 * SS), (0, 0, 0, 0))
    desenhar_marca(
        ImageDraw.Draw(marca), 300 * SS, 150 * SS, 150 * SS, ROXO_ESCURO
    )
    marca = marca.resize((300, 300), Image.LANCZOS)
    imagem.alpha_composite(marca, (70, 100))

    desenho = ImageDraw.Draw(imagem)
    desenho.text((410, 165), 'Video to GIF', font=fonte(64), fill=BRANCO)
    desenho.text(
        (412, 250),
        'Saiba o peso antes de converter',
        font=fonte(30, negrito=False),
        fill=(235, 225, 250),
    )
    desenho.text(
        (412, 296),
        'Corte · proporção · velocidade · FPS',
        font=fonte(26, negrito=False),
        fill=(212, 196, 240),
    )

    return imagem.convert('RGB')


def main():
    (RAIZ / 'assets').mkdir(exist_ok=True)
    (RAIZ / 'loja').mkdir(exist_ok=True)
    res = RAIZ / 'android/app/src/main/res'

    mestre = icone_completo(1024)
    mestre.save(RAIZ / 'assets/icone.png')
    print('assets/icone.png')

    icone_completo(512).convert('RGB').save(RAIZ / 'loja/icone_512.png')
    print('loja/icone_512.png')

    for densidade, px in DENSIDADES.items():
        pasta = res / f'mipmap-{densidade}'
        pasta.mkdir(parents=True, exist_ok=True)
        icone_completo(px).save(pasta / 'ic_launcher.png')
        # A camada adaptativa é desenhada num canvas 2,25x maior que o ícone
        # final, conforme a especificação de ícones adaptativos do Android.
        icone_adaptativo_frente(round(px * 2.25)).save(
            pasta / 'ic_launcher_foreground.png'
        )
        print(f'mipmap-{densidade}/  ({px}px)')

    grafico_destaque().save(RAIZ / 'loja/grafico_destaque_1024x500.png')
    print('loja/grafico_destaque_1024x500.png')


if __name__ == '__main__':
    main()
