#!/usr/bin/env python3
"""Mantém a lista `assets:` do pubspec.yaml em dia com as pastas do projeto.

O Flutter não aceita curinga em `assets:`, e a declaração de uma pasta não é
recursiva: `- assets/sticker/` empacota os arquivos soltos ali, mas ignora
`assets/sticker/github/` se a subpasta não estiver declarada também. Ou seja,
criar uma subpasta nova e soltar arquivos nela não bastava — o conteúdo ficava
de fora do APK sem aviso nenhum.

Este script varre as pastas de conteúdo do app e reescreve o bloco `assets:`
com uma entrada por pasta que tenha arquivo. Roda sozinho no CI, que falha se
o pubspec estiver desatualizado.

Uso:
    python3 tool/sincronizar_assets.py            # reescreve o pubspec
    python3 tool/sincronizar_assets.py --conferir # só confere, não escreve
"""

from __future__ import annotations

import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
PUBSPEC = RAIZ / 'pubspec.yaml'

# Pastas cujo conteúdo o app carrega em tempo de execução. O resto de
# `assets/` (telas para a loja, arte do README) não entra no APK de propósito.
PASTAS_DE_CONTEUDO = ['assets/background', 'assets/fonts', 'assets/frame',
                      'assets/sticker']

# Arquivos avulsos que continuam declarados um a um.
AVULSOS = ['assets/icon/icon-v4.png']

IGNORADOS = {'.ds_store', 'thumbs.db'}


def pastas_com_arquivo() -> list[str]:
    """Toda pasta de conteúdo, e subpasta dela, que tenha ao menos um arquivo."""
    encontradas: set[str] = set()
    for raiz in PASTAS_DE_CONTEUDO:
        base = RAIZ / raiz
        if not base.is_dir():
            continue
        for pasta in [base, *(p for p in base.rglob('*') if p.is_dir())]:
            tem_arquivo = any(
                f.is_file() and f.name.lower() not in IGNORADOS
                for f in pasta.iterdir()
            )
            if tem_arquivo:
                encontradas.add(f'{pasta.relative_to(RAIZ).as_posix()}/')
    return sorted(encontradas)


def bloco_esperado() -> list[str]:
    return [f'    - {caminho}' for caminho in AVULSOS + pastas_com_arquivo()]


def reescrever(conferir: bool) -> int:
    linhas = PUBSPEC.read_text(encoding='utf-8').split('\n')

    try:
        inicio = next(i for i, l in enumerate(linhas) if l.rstrip() == '  assets:')
    except StopIteration:
        print('ERRO: não achei o bloco "  assets:" no pubspec.yaml', file=sys.stderr)
        return 2

    fim = inicio + 1
    while fim < len(linhas) and linhas[fim].startswith('    - '):
        fim += 1

    atual = linhas[inicio + 1:fim]
    esperado = bloco_esperado()

    if atual == esperado:
        print('pubspec.yaml já está em dia '
              f'({len(esperado)} entradas em assets:).')
        return 0

    if conferir:
        print('pubspec.yaml está desatualizado. Rode:\n'
              '    python3 tool/sincronizar_assets.py\n', file=sys.stderr)
        for linha in sorted(set(esperado) - set(atual)):
            print(f'  faltando: {linha.strip()}', file=sys.stderr)
        for linha in sorted(set(atual) - set(esperado)):
            print(f'  sobrando: {linha.strip()}', file=sys.stderr)
        return 1

    PUBSPEC.write_text(
        '\n'.join(linhas[:inicio + 1] + esperado + linhas[fim:]),
        encoding='utf-8',
    )
    print(f'pubspec.yaml atualizado ({len(esperado)} entradas em assets:).')
    return 0


if __name__ == '__main__':
    sys.exit(reescrever(conferir='--conferir' in sys.argv))
