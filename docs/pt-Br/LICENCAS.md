# Licenças — o que você precisa saber antes de publicar

Este app usa o **FFmpeg**, que é software livre. Isso é ótimo (você não paga
nada e pode publicar um app de código fechado), mas vem com algumas obrigações
pequenas e obrigatórias. Ignorá-las é o tipo de coisa que gera pedido de
remoção do app.

## O ponto central: LGPL sim, GPL não

O FFmpeg pode ser compilado de dois jeitos:

| Variante | Licença | Pode usar em app de código fechado? |
|---|---|---|
| **LGPL** (padrão) | LGPL 2.1+ | ✅ Sim |
| **GPL** (com x264, x265, xvid, vid.stab) | GPL 2+ | ❌ Não — obrigaria você a abrir todo o código do app |

Este projeto usa o pacote **`ffmpeg_kit_flutter_new_video`**, que é uma
variante **LGPL** e **não contém nenhum componente GPL**. Isso é proposital.

Em relação ao pacote `ffmpeg_kit_flutter_new_min` usado antes de existir a
exportação em WebP, a variante `_video` acrescenta o `libwebp` (necessário
para o WebP animado), além de `dav1d`, `libvpx` e `libtheora` — todas
bibliotecas LGPL ou de licença permissiva, nenhuma delas GPL. O próprio
`libwebp` é uma biblioteca do Google com licença permissiva estilo BSD (não
é GPL nem LGPL), então empacotá-lo dentro do `_video` também não introduz
componente GPL nenhum.

> ⚠️ **Nunca troque para os pacotes terminados em `_gpl`** (nem para o
> `ffmpeg_kit_flutter_new` "cheio", que é GPL) sem abrir o código do app sob
> GPL. Para converter em GIF você não precisa de nada disso: o codificador
> de GIF e os filtros `palettegen`/`paletteuse` fazem parte do núcleo do
> FFmpeg, que é LGPL. O mesmo vale para o WebP: o codificador baseado em
> `libwebp` da variante `_video` é LGPL/BSD, não GPL.

Se um dia você quiser exportar **MP4 com H.264**, aí sim vai esbarrar nisso —
e a saída é usar o codificador de hardware do Android (MediaCodec), não o
x264.

## O que a LGPL exige de você

1. **Dizer que usa FFmpeg e sob qual licença.**
   Já está feito: `lib/licenses.dart` registra o aviso, que aparece em
   *Sobre → Ver licenças* dentro do app.

2. **Apontar onde obter o código-fonte do FFmpeg.**
   Também está no mesmo aviso, com o link do repositório oficial.

3. **Permitir que a biblioteca seja substituída.**
   Atendido automaticamente: o FFmpeg entra no APK como biblioteca dinâmica
   (`.so`), não compilado dentro do seu código.

4. **Não modificar o FFmpeg** — ou, se modificar, publicar as modificações.
   Você não está modificando nada.

Ou seja: o trabalho já está feito no código. Só **não remova** a chamada de
`registerThirdPartyLicenses()` no `main.dart` nem o botão *Sobre* da tela
inicial.

## Onde a Play Store olha isso

O Google não verifica licença de código automaticamente, mas:

- a política de **Propriedade intelectual** permite que os autores denunciem
  apps que violam a licença;
- reclamações do tipo costumam vir de quem acompanha projetos de código
  aberto, e o FFmpeg tem histórico de cobrar isso publicamente
  (a "hall of shame" do projeto);
- a consequência é a remoção do app e, em caso de reincidência, o
  encerramento da conta de desenvolvedor.

O custo de estar em conformidade é uma tela de licenças. Vale a pena.

## As outras dependências

Todas com licenças permissivas, sem obrigações além do aviso automático que o
Flutter já gera em *Ver licenças*:

| Pacote | Licença |
|---|---|
| `flutter` e pacotes oficiais (`video_player`, `path_provider`, `share_plus`) | BSD-3-Clause |
| `file_picker` | MIT |
| `gal` | MIT |
| `shared_preferences` | BSD-3-Clause |
| `flutter_svg` | MIT |
| `ffmpeg_kit_flutter_new_video` | LGPL-3.0 |
| FFmpeg (binário) | LGPL-2.1-or-later |
| `libwebp` (embutido no binário do FFmpeg) | Estilo BSD (Google) |
