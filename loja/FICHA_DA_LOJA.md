# Ficha da loja — textos prontos para colar

Todos os textos abaixo já respeitam os limites da Play Console. Copie e cole
direto nos campos correspondentes.

---

## Nome do app (limite: 30 caracteres)

```
Video to GIF
```

## Descrição curta (limite: 80 caracteres)

```
Converta vídeos em GIF e saiba o peso do arquivo antes de converter.
```

## Descrição completa (limite: 4000 caracteres)

```
Transforme qualquer vídeo em GIF direto no seu celular, sem enviar nada para a internet.

SAIBA O PESO ANTES DE CONVERTER
Cansada de esperar a conversão terminar só para descobrir que o arquivo ficou grande demais? O app mostra o peso previsto enquanto você mexe nos controles. Toque em "Medir" e ele converte trechos de menos de um segundo para calibrar a previsão com o seu vídeo — a partir daí o número fica preciso.

CABE ONDE VOCÊ PRECISA
O app avisa se o GIF cabe no WhatsApp, no X/Twitter ou no Discord. Se não couber, um toque ajusta as configurações automaticamente para caber, reduzindo primeiro o que menos afeta a qualidade percebida.

O QUE VOCÊ CONTROLA
• Corte o começo e o fim do vídeo
• Escolha o formato da janela: 1:1, 4:5, 9:16, 16:9, 4:3, 3:2 ou o original
• Ajuste a posição do recorte
• Acelere até 4x ou deixe em câmera lenta até 0,25x
• Escolha a resolução, de 160 px a 1080 px de largura
• Defina os quadros por segundo, de 5 a 30
• Ajuste fino de paleta, número de cores e suavização

QUALIDADE DE VERDADE
A conversão usa paleta otimizada em duas passagens: em vez das cores genéricas do formato GIF, o app calcula as cores que o seu vídeo realmente usa. É a diferença entre um GIF vivo e um GIF "lavado".

ENTENDA O QUE ESTÁ FAZENDO
Uma tela de ajuda explica, em português claro, o que cada controle faz com o peso do arquivo e em que ordem vale a pena mexer neles.

PRIVACIDADE DE VERDADE
Tudo acontece no seu aparelho. O app não tem permissão de acesso à internet, não coleta nenhum dado e não pede acesso à sua galeria: você escolhe o vídeo pelo seletor do próprio Android, e o app enxerga apenas aquele arquivo.

FORMATOS ACEITOS
MP4, MOV, AVI, MKV, WEBM, 3GP e outros formatos comuns de vídeo.

Sem anúncios. Sem cadastro. Sem cobrança.
```

---

## Imagens

| Arquivo | Onde usar |
|---|---|
| `icone_512.png` | Ícone do app na ficha da loja (512×512) |
| `grafico_destaque_1024x500.png` | Gráfico de destaque (1024×500) |

Para regerar as duas, rode a partir da raiz do projeto:

```bash
pip install Pillow
python3 tool/gerar_icones.py
```

O mesmo script também atualiza o ícone do launcher em
`android/app/src/main/res/mipmap-*/`.

### Capturas de tela (você precisa gerar)

A Play Store exige **no mínimo 2** e aceita até 8. Lado menor ≥ 320 px, lado
maior ≤ 3840 px. Sugestão de roteiro, nesta ordem:

1. Tela inicial com o botão "Escolher vídeo"
2. Editor mostrando o painel de peso com o selo verde de "Leve"
3. Editor com os chips de destino (WhatsApp / X / Discord)
4. Seção de formato da janela com o recorte 9:16 aplicado
5. Tela de ajuda "O que deixa um GIF pesado"
6. Resultado com o GIF pronto e a comparação previsto × real

Com o app rodando no celular conectado:

```bash
# limpa a barra de status para a captura ficar apresentável
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1000
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false

adb exec-out screencap -p > loja/captura1.png

# devolve a barra de status ao normal
adb shell am broadcast -a com.android.systemui.demo -e command exit
```

---

## Respostas dos formulários obrigatórios

Guardadas aqui para você não precisar decidir de novo a cada envio. Elas valem
para o app **como ele está neste repositório** — mudam se você adicionar
anúncios, analytics ou qualquer envio para servidor.

| Formulário | Resposta |
|---|---|
| Segurança dos dados — coleta ou compartilha dados? | **Não** |
| Anúncios | Não contém anúncios |
| Acesso ao app | Todas as funções disponíveis sem restrição |
| Público-alvo | 13 anos ou mais (não marcar "crianças") |
| Classificação de conteúdo | Questionário IARC — "não" em tudo; resultado esperado: Livre / 3+ |
| App de notícias | Não |
| Recursos financeiros / saúde / governo | Não |
| Permissões sensíveis | Nenhuma solicitada |
| Política de privacidade | URL pública com o conteúdo de `docs/POLITICA_DE_PRIVACIDADE.md` |

## Categorização

- **Categoria:** Ferramentas (ou Fotografia — as duas cabem; Ferramentas tem
  menos concorrência direta de editores de foto)
- **Tags sugeridas:** GIF, conversor de vídeo, editor de vídeo, compressão
