#!/usr/bin/env python3
"""Gera o ícone do GitBat em todas as densidades Android e na ficha da loja.

Rode a partir da raiz do projeto:
    pip install Pillow
    python3 tool/gerar_icones.py

O mestre transparente de 1024x1024 fica em
``assets/icon/icon-v3/gitbat-mark.webp``. A partir dele, o script compõe o
fundo e gera os ícones legados, adaptativos, de abertura e da Play Store.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parent.parent
ICONE_FONTE = RAIZ / 'assets/icon/icon-v3/gitbat-mark.webp'

AZUL_NOITE = (17, 25, 41)  # fundo do ícone, #111929
AZUL_MARINHO = (12, 72, 168)
AZUL_GELO = (176, 221, 252)
CIANO = (34, 216, 238)
BRANCO = (255, 255, 255)

DENSIDADES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}


def icone_transparente(tamanho):
    """Redimensiona o mestre RGBA sem distorcer nem preencher transparência."""
    with Image.open(ICONE_FONTE) as fonte:
        imagem = fonte.convert('RGBA')
    imagem.thumbnail((tamanho, tamanho), Image.Resampling.LANCZOS)
    tela = Image.new('RGBA', (tamanho, tamanho), (0, 0, 0, 0))
    tela.alpha_composite(imagem, ((tamanho - imagem.width) // 2,
                                  (tamanho - imagem.height) // 2))
    return tela


def icone_completo(tamanho):
    """Ícone quadrado com fundo, para launcher legado e ficha da loja."""
    tela = Image.new('RGBA', (tamanho, tamanho), (*AZUL_NOITE, 255))
    tela.alpha_composite(icone_transparente(tamanho))
    return tela


def icone_adaptativo_frente(tamanho):
    """Camada da frente. Android pode recortá-la em círculo, quadrado ou gota."""
    camada = Image.new('RGBA', (tamanho, tamanho), (0, 0, 0, 0))
    # O ícone fica em 2/3 da tela; mantém a marca dentro da área segura.
    lado = round(tamanho * 2 / 3)
    arte = icone_transparente(lado)
    camada.alpha_composite(arte, ((tamanho - lado) // 2,
                                  (tamanho - lado) // 2))
    return camada


def icone_abertura():
    """Ícone de abertura do Android 12+, em canvas transparente de 960 px."""
    tamanho = 960
    camada = Image.new('RGBA', (tamanho, tamanho), (0, 0, 0, 0))
    lado = tamanho // 2
    camada.alpha_composite(icone_completo(lado), ((tamanho - lado) // 2,) * 2)
    return camada


def fonte(tamanho, negrito=True):
    nome = 'DejaVuSans-Bold.ttf' if negrito else 'DejaVuSans.ttf'
    return ImageFont.truetype(f'/usr/share/fonts/truetype/dejavu/{nome}', tamanho)


def grafico_destaque():
    """Banner 1024x500 da ficha da Play Store."""
    largura, altura = 1024, 500
    imagem = Image.new('RGB', (largura, altura))
    pixels = imagem.load()
    for y in range(altura):
        for x in range(largura):
            t = (x / (largura - 1) + y / (altura - 1)) / 2
            pixels[x, y] = tuple(round(AZUL_NOITE[c] +
                (AZUL_MARINHO[c] - AZUL_NOITE[c]) * t) for c in range(3))

    imagem.paste(icone_completo(300).convert('RGB'), (70, 100))
    desenho = ImageDraw.Draw(imagem)
    desenho.text((410, 165), 'GitBat', font=fonte(64), fill=BRANCO)
    desenho.text((412, 250), 'Saiba o peso antes de converter',
                 font=fonte(30, negrito=False), fill=AZUL_GELO)
    desenho.text((412, 296), 'Corte · proporção · velocidade · FPS',
                 font=fonte(26, negrito=False), fill=CIANO)
    return imagem


def main():
    res = RAIZ / 'android/app/src/main/res'
    loja = RAIZ / 'loja'
    loja.mkdir(exist_ok=True)

    icone_completo(512).convert('RGB').save(loja / 'icone_512.png')
    for densidade, px in DENSIDADES.items():
        pasta = res / f'mipmap-{densidade}'
        pasta.mkdir(parents=True, exist_ok=True)
        icone_completo(px).save(pasta / 'ic_launcher.png')
        icone_adaptativo_frente(round(px * 2.25)).save(
            pasta / 'ic_launcher_foreground.png')

    pasta_splash = res / 'drawable-nodpi'
    pasta_splash.mkdir(parents=True, exist_ok=True)
    icone_abertura().save(pasta_splash / 'splash_icon.png')
    grafico_destaque().save(loja / 'grafico_destaque_1024x500.png')


if __name__ == '__main__':
    main()
