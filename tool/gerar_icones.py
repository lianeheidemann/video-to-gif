#!/usr/bin/env python3
"""Gera os recursos vetoriais do launcher e as imagens da ficha da Play Store.

Rode a partir da raiz do projeto:
    pip install Pillow
    python3 tool/gerar_icones.py

A arte vetorial 1024×1024 é a fonte única do ícone. O Android usa VectorDrawable
em diferentes densidades e recortes; o script também atualiza PNGs de fallback.
"""

from pathlib import Path
import re
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parent.parent
ICONE_FONTE = RAIZ / 'assets/icon/icon-v3/gitbat-mark.svg'
AZUL_NOITE = '#111929'
AZUL_MARINHO = '#0C48A8'
AZUL_GELO = '#B0DDFC'
CIANO = '#22D8EE'
BRANCO = '#FFFFFF'
COR_MARCA = '#E8F2FF'


def dados_do_svg():
    raiz = ET.parse(ICONE_FONTE).getroot()
    caminho = raiz.find('{http://www.w3.org/2000/svg}path')
    if caminho is None or not caminho.get('d'):
        raise ValueError(f'Não encontrei o path da marca em {ICONE_FONTE}')
    return caminho.get('d')


def vetor(width_dp, height_dp, path_data, fill, background=None, safe=False):
    partes = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
        f'    android:width="{width_dp}dp" android:height="{height_dp}dp"',
        '    android:viewportWidth="1024" android:viewportHeight="1024">',
    ]
    if background:
        partes.append(
            f'    <path android:fillColor="{background}" android:pathData="M0,0h1024v1024H0z" />'
        )
    if safe:
        partes.extend([
            '    <group android:scaleX="0.56" android:scaleY="0.56"',
            '        android:translateX="225.28" android:translateY="225.28">',
            f'        <path android:fillColor="{fill}" android:fillType="evenOdd" android:pathData="{path_data}" />',
            '    </group>',
        ])
    else:
        partes.append(
            f'    <path android:fillColor="{fill}" android:fillType="evenOdd" android:pathData="{path_data}" />'
        )
    partes.append('</vector>')
    return '\n'.join(partes) + '\n'


def adaptive_icon():
    return '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
'''


def splash_vector(path_data):
    # Mantém o mesmo enquadramento seguro do splash anterior: marca e fundo
    # ocupam o quadrado central de 50% do canvas transparente.
    return f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="288dp" android:height="288dp"
    android:viewportWidth="1024" android:viewportHeight="1024">
    <group android:scaleX="0.5" android:scaleY="0.5"
        android:translateX="256" android:translateY="256">
        <path android:fillColor="{AZUL_NOITE}" android:pathData="M0,0h1024v1024H0z" />
        <path android:fillColor="{COR_MARCA}" android:fillType="evenOdd" android:pathData="{path_data}" />
    </group>
</vector>
'''


def poligono(path_data):
    tokens = re.findall(r'[MLZ]|-?(?:\d+(?:\.\d*)?|\.\d+)', path_data)
    loops = []
    current = []
    command = None
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token in ('M', 'L'):
            command = token
            i += 1
            continue
        if token == 'Z':
            if current:
                loops.append(current)
            current = []
            command = None
            i += 1
            continue
        if command not in ('M', 'L'):
            raise ValueError(f'Coordenada SVG inesperada: {token}')
        x = float(tokens[i]); y = float(tokens[i + 1]); i += 2
        current.append((x, y))
        # SVG treats coordinate pairs following M as implicit L commands.
        command = 'L'
    if current:
        loops.append(current)
    return loops


def icone_completo(tamanho, loops):
    # Renderiza em 4x para bordas suaves mesmo nos PNGs de fallback.
    escala = 4
    mask = Image.new('1', (tamanho * escala, tamanho * escala), 0)
    desenho = ImageDraw.Draw(mask)
    for loop in loops:
        desenho.polygon([(round(x * tamanho / 1024 * escala),
                          round(y * tamanho / 1024 * escala)) for x, y in loop],
                        fill=1)
    mask = mask.resize((tamanho, tamanho), Image.Resampling.LANCZOS)
    imagem = Image.new('RGBA', (tamanho, tamanho), (*bytes.fromhex(AZUL_NOITE[1:]), 255))
    marca = Image.new('RGBA', (tamanho, tamanho), (*bytes.fromhex(COR_MARCA[1:]), 0))
    marca.putalpha(mask.convert('L'))
    imagem.alpha_composite(marca)
    return imagem


def fonte(tamanho, negrito=True):
    nome = 'DejaVuSans-Bold.ttf' if negrito else 'DejaVuSans.ttf'
    return ImageFont.truetype(f'/usr/share/fonts/truetype/dejavu/{nome}', tamanho)


def grafico_destaque(loops):
    largura, altura = 1024, 500
    imagem = Image.new('RGB', (largura, altura))
    pixels = imagem.load()
    inicio = tuple(bytes.fromhex(AZUL_NOITE[1:]))
    fim = tuple(bytes.fromhex(AZUL_MARINHO[1:]))
    for y in range(altura):
        for x in range(largura):
            t = (x / (largura - 1) + y / (altura - 1)) / 2
            pixels[x, y] = tuple(round(inicio[c] + (fim[c] - inicio[c]) * t) for c in range(3))
    imagem.paste(icone_completo(300, loops).convert('RGB'), (70, 100))
    desenho = ImageDraw.Draw(imagem)
    desenho.text((410, 165), 'GitBat', font=fonte(64), fill=BRANCO)
    desenho.text((412, 250), 'Saiba o peso antes de converter',
                 font=fonte(30, negrito=False), fill=AZUL_GELO)
    desenho.text((412, 296), 'Corte · proporção · velocidade · FPS',
                 font=fonte(26, negrito=False), fill=CIANO)
    return imagem


def main():
    path_data = dados_do_svg()
    loops = poligono(path_data)
    res = RAIZ / 'android/app/src/main/res'
    (res / 'mipmap-anydpi-v24').mkdir(parents=True, exist_ok=True)
    (res / 'mipmap-anydpi-v26').mkdir(parents=True, exist_ok=True)
    (res / 'drawable').mkdir(parents=True, exist_ok=True)
    (res / 'drawable-anydpi-v31').mkdir(parents=True, exist_ok=True)
    (res / 'mipmap-anydpi-v24/ic_launcher.xml').write_text(
        vetor(48, 48, path_data, COR_MARCA, background=AZUL_NOITE))
    (res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text(adaptive_icon())
    (res / 'drawable/ic_launcher_foreground.xml').write_text(
        vetor(108, 108, path_data, COR_MARCA, safe=True))
    (res / 'drawable/ic_launcher_monochrome.xml').write_text(
        vetor(108, 108, path_data, '#FFFFFFFF', safe=True))
    (res / 'drawable-anydpi-v31/splash_icon.xml').write_text(
        splash_vector(path_data))

    loja = RAIZ / 'loja'
    loja.mkdir(exist_ok=True)
    icone_completo(512, loops).convert('RGB').save(loja / 'icone_512.png')
    grafico_destaque(loops).save(loja / 'grafico_destaque_1024x500.png')
    # Mantém os PNGs de densidade como fallback para qualquer ferramenta que
    # não consuma o VectorDrawable anydpi.
    for densidade, tamanho in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96,
                               'xxhdpi': 144, 'xxxhdpi': 192}.items():
        pasta = res / f'mipmap-{densidade}'
        pasta.mkdir(parents=True, exist_ok=True)
        icone_completo(tamanho, loops).save(pasta / 'ic_launcher.png')


if __name__ == '__main__':
    main()
