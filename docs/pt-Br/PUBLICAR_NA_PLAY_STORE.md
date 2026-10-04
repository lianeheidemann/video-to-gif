# Publicar o app na Google Play Store

Guia completo, do zero até o app no ar. Escrito para quem nunca publicou nada
na Play Store.

> **Aviso de prazo:** as regras da Play Store mudam algumas vezes por ano.
> Este guia está atualizado para **agosto de 2026**. Sempre confira a página
> oficial correspondente antes de cada envio — os links estão no fim.

---

## Visão geral: quanto tempo isso leva de verdade

| Etapa | Tempo | Custo |
|---|---|---|
| Preparar o ambiente e compilar | 1 a 3 horas | grátis |
| Criar a conta de desenvolvedor | 15 min + **1 a 3 dias** de verificação | **US$ 25**, uma vez na vida |
| Preencher a ficha da loja (textos e imagens) | 2 a 4 horas | grátis |
| **Teste fechado obrigatório (12 pessoas, 14 dias)** | **no mínimo 14 dias** | grátis |
| Revisão da produção | 1 a 7 dias | grátis |

**Do zero ao app publicado: de 3 a 5 semanas na prática.** O gargalo é o teste
fechado, que não tem como pular nem acelerar. Comece por ele o quanto antes.

---

## Etapa 0 — O que você precisa ter em mãos

- Um computador com **Windows, macOS ou Linux** (Android Studio roda nos três).
- Uma **conta Google** que será dona do app para sempre. Use uma conta que
  você não vá perder — trocar depois é burocrático.
- **US$ 25** num cartão internacional.
- **Documento de identidade** (RG ou CNH) e um comprovante de endereço: o
  Google verifica a identidade de todo desenvolvedor pessoa física.
- **12 pessoas** dispostas a instalar seu app e abrir durante 14 dias.
  Comece a convidar já — é o item mais difícil de conseguir.

---

## Etapa 1 — Preparar o computador

1. Instale o **Flutter** (versão 3.44 ou mais nova):
   <https://docs.flutter.dev/get-started/install>
2. Instale o **Android Studio** — ele traz o Android SDK, o NDK e as
   ferramentas de build.
3. No Android Studio, em *SDK Manager → SDK Platforms*, marque **Android 16
   (API 36)**. Em *SDK Tools*, marque **NDK (Side by side)** e
   **Android SDK Command-line Tools**.
4. Confira se está tudo certo:

   ```bash
   flutter doctor
   ```

   Resolva tudo que aparecer com ✗ antes de seguir. O item
   *"Android license status unknown"* se resolve com
   `flutter doctor --android-licenses`.

---

## Etapa 2 — Rodar o projeto pela primeira vez

```bash
git clone https://github.com/lianeheidemann/gitbat-app.git
cd gitbat-app

flutter pub get
flutter test   # os testes do estimador de peso devem passar
flutter run    # com o celular conectado e a depuração USB ligada
```

> O `gradlew` e o `android/local.properties` não são versionados (convenção do
> Flutter) — a própria ferramenta os cria no primeiro build, apontando para o
> SDK instalado na sua máquina.

Se der erro de NDK, abra `android/app/build.gradle.kts` e ajuste
`ndkVersion` para a versão que você instalou (o erro diz qual é).

---

## Etapa 3 — Definir a identidade do app

Três coisas precisam ser decididas **antes** do primeiro envio, porque não
podem mais mudar depois:

### 3.1 O `applicationId`

É o endereço permanente do app na loja. Neste projeto está como
`br.com.lianeheidemann.videotogif`, em `android/app/build.gradle.kts` →
`applicationId`.

Ele continua com o nome da época em que o app se chamava "Video to GIF"
**de propósito**: trocar cria outro app, que não instala por cima do atual e
perde a ficha da loja. O nome GitBat aparece só no que o usuário vê (3.2) e
no pacote do código Kotlin (`namespace = "br.com.lianeheidemann.gitbat"` e a
pasta `android/app/src/main/kotlin/br/com/lianeheidemann/gitbat/`), que
podem mudar à vontade.

### 3.2 O nome visível

**GitBat**. Está em `android/app/src/main/AndroidManifest.xml`, no atributo
`android:label`. Na loja o nome pode ter no máximo **30 caracteres**.

### 3.3 O ícone

**O ícone é vetorial no Android 7+**, então o launcher pode renderizá-lo
nítido em diferentes densidades. No Android 8+, também usa uma camada
adaptativa e mantém a marca dentro da área segura dos recortes:

```
android/app/src/main/res/mipmap-anydpi-v24/ic_launcher.xml  (vetorial, Android 7+)
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml  (adaptativo, Android 8+)
android/app/src/main/res/drawable/ic_launcher_foreground.xml  (camada vetorial)
android/app/src/main/res/drawable/ic_launcher_monochrome.xml  (tema monocromático)
assets/icon/icon-v3/gitbat-mark.svg  (mestre vetorial, 1024×1024)
```

As versões anteriores do ícone continuam guardadas em `assets/icon/icon-v1/`
e `assets/icon/icon-v2/`. A logo do topo do README (sem fundo) é
`assets/readme/gitbat-logo.png`.

Para trocar a arte, edite `assets/icon/icon-v3/gitbat-mark.svg`. O script
`tool/gerar_icones.py` gera os recursos vetoriais do launcher e os PNGs de
fallback e da ficha da loja:

```bash
pip install Pillow
python3 tool/gerar_icones.py
```

Assim, Android 7+ usa o desenho vetorial em qualquer densidade; as variantes
adaptativas e monocromáticas são geradas separadamente para os recursos do
Android 8+ e Android 13+.

---

## Etapa 4 — Criar a chave de assinatura

Todo APK/AAB precisa ser assinado. **Esta chave é para sempre**: se você
perder, não consegue mais publicar atualizações do mesmo app — teria que
começar um app novo, do zero, sem os usuários.

> ⚠️ **Gere a chave na sua própria máquina.** Nunca crie o keystore de
> produção num ambiente descartável — container, CI, máquina de nuvem, sessão
> de agente. Ou você perde a chave quando o ambiente é destruído, ou precisa
> transferi-la por um caminho inseguro. Esta é a única parte do processo que
> não dá para terceirizar nem automatizar.

> Se a chave já foi criada com outro nome (ex.: `chave-upload-videotogif.jks`,
> da época do "Video to GIF"), continue usando ela: nos comandos abaixo, troque
> só o nome do arquivo.

O `keytool` vem junto com o Java. Se você não tiver Java instalado, ele está
dentro do Android Studio, em `<pasta-do-android-studio>/jbr/bin/keytool`.
O Android Studio também faz isso pela interface, em
*Build → Generate Signed App Bundle → Create new…*.

**Modo interativo** (pergunta a senha e os dados um por um):

```bash
keytool -genkeypair -v \
  -keystore ~/chave-upload-gitbat.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

**Modo direto** (sem perguntas — troque o nome e a senha):

```bash
keytool -genkeypair -v \
  -keystore ~/chave-upload-gitbat.jks \
  -storepass SUA_SENHA_FORTE -keypass SUA_SENHA_FORTE \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Seu Nome, O=, L=Sua Cidade, ST=UF, C=BR"
```

Os dados do `-dname` não aparecem para ninguém na loja: o certificado é
autoassinado e serve só para provar que as versões vieram da mesma pessoa.
O que importa de verdade é o arquivo e a senha.

Confira se deu certo:

```bash
keytool -list -v -keystore ~/chave-upload-gitbat.jks
```

Deve aparecer `Alias name: upload`, a validade (uns 27 anos, com
`-validity 10000`) e as impressões digitais SHA1 e SHA256.

> A validade de 10.000 dias não é exagero: a Play Store exige um certificado
> válido até pelo menos 22 de outubro de 2033.

Agora crie o arquivo `android/key.properties` (copie de
`android/key.properties.example`):

```properties
storePassword=a-senha-que-voce-escolheu
keyPassword=a-mesma-senha
keyAlias=upload
storeFile=/caminho/completo/para/chave-upload-gitbat.jks
```

> ⚠️ **Nunca** coloque o `.jks` nem o `key.properties` no Git. O `.gitignore`
> deste projeto já bloqueia os dois. Guarde uma cópia do `.jks` e das senhas
> em um gerenciador de senhas **e** num backup separado (pendrive, Drive
> privado). Isso é o item mais crítico de todo o processo.

**Play App Signing:** o Google guarda a chave final de distribuição por você.
A sua chave `.jks` é a *chave de upload* — se ela vazar ou for perdida, dá
para pedir a troca ao suporte, desde que o Play App Signing esteja ativo (é o
padrão para apps novos). Mesmo assim, trate como se não houvesse segunda
chance.

---

## Etapa 5 — Gerar o pacote para a loja

A Play Store **não aceita mais APK** para apps novos. O formato é o **AAB**
(Android App Bundle):

```bash
flutter build appbundle --release
```

O arquivo sai em:

```
build/app/outputs/bundle/release/app-release.aab
```

Antes de enviar, teste o build de release no seu celular — o modo release usa
o R8 (que remove código não usado) e é onde bugs de ProGuard aparecem:

```bash
flutter build apk --release
flutter install --release
```

Se o app abrir e converter um GIF sem travar, o AAB também vai funcionar.

> Se o app funcionar em debug mas travar em release ao converter, quase
> sempre é o R8 removendo classes do FFmpeg. As regras que evitam isso já
> estão em `android/app/proguard-rules.pro`.

---

## Etapa 5b — Deixar o GitHub compilar por você (opcional, mas recomendado)

Se a sua máquina não estiver com o ambiente Android pronto — ou se você quiser
mandar o app para os testadores sem passar arquivo por WhatsApp — o
repositório já tem um workflow que compila e publica tudo num Release do
GitHub: `.github/workflows/release.yml`.

### Como disparar

```bash
git tag v1.0.0
git push origin v1.0.0
```

Ou, sem mexer em tag: aba **Actions → Release → Run workflow**, digitando a
versão.

Em poucos minutos aparece um Release com:

| Arquivo | Para que serve |
|---|---|
| `...-arm64-v8a.apk` | instalar em celular moderno (o que você manda para os testadores) |
| `...-armeabi-v7a.apk` | aparelhos antigos, 32 bits |
| `...-universal.apk` | funciona em qualquer aparelho, porém maior |
| `....aab` | **o arquivo que vai para a Play Console** (só sai se a assinatura estiver configurada) |

### Configurar a assinatura (para o AAB sair publicável)

Sem os segredos abaixo, o workflow ainda funciona, mas assina com a chave de
depuração: os APKs instalam e rodam para teste, e o `.aab` não é gerado,
porque não teria serventia.

Para habilitar a assinatura de verdade, transforme o seu keystore em texto:

```bash
base64 -w0 ~/chave-upload-gitbat.jks > chave-base64.txt
# no macOS, sem a opção -w0:
# base64 -i ~/chave-upload-gitbat.jks -o chave-base64.txt
```

Em **Settings → Secrets and variables → Actions → New repository secret**,
crie quatro segredos:

| Nome | Conteúdo |
|---|---|
| `KEYSTORE_BASE64` | todo o conteúdo de `chave-base64.txt` |
| `KEYSTORE_PASSWORD` | a senha do keystore |
| `KEY_PASSWORD` | a senha da chave (a mesma, se você usou uma só) |
| `KEY_ALIAS` | `upload` |

Depois **apague o `chave-base64.txt`** da sua máquina — ele é o keystore
inteiro em texto.

> ⚠️ Isto coloca uma cópia da sua chave de assinatura no GitHub. Segredos do
> Actions são criptografados e não aparecem nos logs, e o workflow apaga o
> arquivo do runner ao final. Ainda assim, quem tiver acesso de administrador
> ao repositório pode extrair a chave modificando um workflow — mantenha o
> repositório privado e a lista de colaboradores curta. Se preferir não correr
> esse risco, não configure os segredos: gere o `.aab` na sua máquina e use o
> Release só para distribuir APKs de teste.

### O versionCode

O workflow usa o número da execução do Actions como `versionCode`, que cresce
sozinho a cada rodada. Isso resolve o erro mais chato de envio ("versionCode
já existe") sem você precisar lembrar de nada. O `versionName` sai da tag:
`v1.0.0` vira `1.0.0`.

---

## Etapa 6 — Criar a conta na Google Play Console

1. Acesse <https://play.google.com/console/signup>.
2. Escolha **conta pessoal** (mais simples; a conta de empresa exige um
   número D-U-N-S e leva semanas).
3. Pague os **US$ 25** (pagamento único, vale para todos os apps que você
   publicar na vida).
4. **Verificação de identidade:** envie foto do documento e o endereço. Leva
   de 1 a 3 dias. O endereço que você informar aparece publicamente na ficha
   do app — se não quiser expor o endereço residencial, considere usar um
   endereço comercial ou caixa postal.

---

## Etapa 7 — Criar o app e preencher as fichas

Na Play Console: **Criar app**. Depois disso, o painel mostra uma lista de
tarefas obrigatórias. Vale a pena preencher tudo antes de subir o AAB.

### 7.1 Ficha da loja (o que o usuário vê)

Os textos já estão escritos, dentro dos limites de caracteres e prontos para
copiar e colar: **[`loja/FICHA_DA_LOJA.md`](../loja/FICHA_DA_LOJA.md)**.

As duas imagens obrigatórias também já estão geradas:

| Item | Especificação | Arquivo |
|---|---|---|
| Nome do app | até 30 caracteres | em `loja/FICHA_DA_LOJA.md` |
| Descrição curta | até 80 caracteres | em `loja/FICHA_DA_LOJA.md` |
| Descrição completa | até 4000 caracteres | em `loja/FICHA_DA_LOJA.md` |
| Ícone | PNG 512×512, 32 bits, até 1 MB | ✅ `loja/icone_512.png` |
| Gráfico de destaque | PNG/JPG 1024×500 | ✅ `loja/grafico_destaque_1024x500.png` |
| Capturas de tela | **mínimo 2**, até 8 · lado menor ≥ 320 px, maior ≤ 3840 px | ⬜ você precisa tirar |

As capturas são a única parte que depende de você, porque exigem o app
rodando num aparelho. O roteiro sugerido (quais telas capturar, em que ordem)
e os comandos do `adb` para limpar a barra de status estão no mesmo arquivo.

### 7.2 Segurança dos dados

Este formulário é obrigatório e o Google confere. Para **este** app, como ele
não tem permissão de internet e não coleta nada, as respostas são:

- *Seu app coleta ou compartilha algum dos tipos de dados do usuário?* → **Não**
- *Todos os dados do usuário são criptografados em trânsito?* → não se aplica
- *Você fornece um jeito de o usuário pedir a exclusão dos dados?* → não se aplica

Se um dia você adicionar anúncios, analytics ou qualquer SDK de terceiros,
**esta resposta muda** e precisa ser atualizada.

### 7.3 Política de privacidade

É **obrigatória**, mesmo para apps que não coletam nada. Você precisa de uma
URL pública. O jeito mais rápido e grátis:

1. Use o modelo em [`POLITICA_DE_PRIVACIDADE.md`](POLITICA_DE_PRIVACIDADE.md).
2. Publique como uma página do GitHub Pages (você já usa isso no projeto
   `protocolo-soap`) ou num Gist público.
3. Cole a URL na Play Console.

### 7.4 Classificação de conteúdo

Responda ao questionário da IARC. Para um conversor de vídeo sem conteúdo
próprio, a classificação sai como **Livre / 3+**. Responda "não" a tudo sobre
violência, sexo, drogas e apostas; marque que não há interação entre usuários
e que não há compartilhamento de localização.

### 7.5 As outras declarações

- **Público-alvo:** escolha faixas etárias de 13 anos para cima. Marcar
  "crianças" ativa a política *Famílias*, que é bem mais rígida — evite.
- **Anúncios:** *Não, meu app não contém anúncios.*
- **Acesso ao app:** *Todas as funções estão disponíveis sem restrição* (não
  há login).
- **App de notícias / COVID / finanças / saúde:** não.
- **Permissões sensíveis:** este app não pede nenhuma. É por isso que o
  `AndroidManifest.xml` remove `READ_MEDIA_VIDEO` — usamos o seletor de
  arquivos do sistema, que não exige permissão. Se você trocar por uma
  galeria interna, vai precisar preencher a declaração de *Permissões de
  fotos e vídeos* e gravar um vídeo demonstrando o uso.

---

## Etapa 8 — O teste fechado obrigatório (a parte mais lenta)

**Se a sua conta pessoal foi criada depois de 13/11/2023**, você não pode
publicar direto em produção. Precisa antes:

- rodar um **teste fechado** com **no mínimo 12 testadores**;
- que eles fiquem **inscritos por 14 dias seguidos**;
- e que **realmente usem** o app nesse período — desde 2026 o Google recusa
  pedidos quando os testadores só instalaram e nunca abriram.

### Como fazer

1. Na Play Console: **Teste → Teste fechado → Criar faixa**.
2. Crie uma **lista de e-mails** com os 12+ endereços Gmail dos testadores
   (precisa ser o e-mail da conta Google do aparelho de cada um).
3. Envie o AAB para essa faixa.
4. Compartilhe o **link de aceitação** que a Console gera. Cada pessoa precisa
   abrir o link, aceitar o convite e **instalar pela Play Store**.
5. Peça para abrirem o app **quase todo dia** durante as duas semanas. Peça
   que convertam um GIF de vez em quando — é isso que conta como uso.

### Dicas práticas

- Convide **15 pessoas**, não 12: sempre alguém não instala.
- Se alguém sair no meio, o contador de 14 dias **não** reinicia; só não deixe
  o total ficar abaixo de 12 por muito tempo.
- Aproveite o período de verdade: peça retorno, corrija travamentos. Envios com
  problemas de estabilidade também são recusados.
- Contas de **empresa** (com CNPJ e D-U-N-S) são isentas dessa exigência.

---

## Etapa 9 — Pedir acesso à produção e publicar

Passados os 14 dias com os 12 testadores ativos, aparece o botão **"Solicitar
acesso à produção"**. Você preenche um formulário curto contando:

- o que aprendeu no teste fechado;
- que mudanças fez a partir do retorno dos testadores;
- como pretende divulgar o app.

Escreva com sinceridade e detalhe — respostas genéricas são recusadas. A
análise leva de 1 a 7 dias.

Aprovado, é só: **Produção → Criar nova versão → enviar o AAB → Revisar →
Iniciar lançamento**. A revisão final leva mais alguns dias na primeira vez.

---

## Etapa 10 — Depois de publicado

### Toda atualização precisa de um `versionCode` novo

No `pubspec.yaml`:

```yaml
version: 1.0.1+2
#       ^^^^^  ^
#       nome   versionCode — SEMPRE maior que o anterior
```

O número depois do `+` é o que a Play Store usa para saber que é uma versão
nova. Se você esquecer de aumentar, o envio é recusado.

### Acompanhe o painel

- **Vitals**: taxa de travamentos e de ANR (app travado). Passando de 1,09% de
  travamentos por usuário, o Google reduz a visibilidade do app na loja.
- **Avaliações**: responda; conta pontos no ranqueamento.

### Fique de olho no `targetSdk`

O Google exige que o app mire numa versão recente do Android:

| Prazo | Exigência |
|---|---|
| **31/08/2026** | apps novos e atualizações precisam mirar **API 36** (Android 16) |
| 01/11/2026 | limite da prorrogação, se você pedir extensão |

Este projeto já está com `targetSdk = 36`. Uma vez por ano, mais ou menos,
você vai precisar subir esse número e reenviar.

---

## Armadilhas que pegam quase todo mundo

1. **Perder o keystore.** Faça backup hoje, não depois.
2. **Não começar o teste fechado cedo.** São 14 dias parados; comece na
   primeira semana.
3. **Subir um AAB de debug.** Sempre `flutter build appbundle --release`.
4. **Esquecer o `versionCode`.** Aumente a cada envio.
5. **Política de privacidade quebrada.** A URL precisa estar acessível
   publicamente e continuar no ar depois da aprovação.
6. **Screenshots com barra de status suja** (bateria em 3%, notificações). Use
   o modo demonstração: `adb shell settings put global sysui_demo_allowed 1`.
7. **App pesado demais.** O FFmpeg adiciona bibliotecas nativas para cada
   arquitetura, então o pacote completo é grande. Isso não é problema na
   loja: o AAB é dividido por ABI no servidor do Google e cada usuário baixa
   só a arquitetura do próprio aparelho. Já para distribuir APK por fora
   (teste, link direto), use os arquivos por arquitetura que o workflow de
   release gera, não o universal.
8. **Ignorar a licença do FFmpeg.** Veja [`LICENCAS.md`](LICENCAS.md) — é
   rápido, mas precisa ser feito.

---

## Checklist final antes de enviar

Já resolvido no repositório:

- [x] Ícone próprio em todas as densidades + ícone adaptativo
- [x] Gráfico de destaque 1024×500 e ícone 512×512 da loja
- [x] Textos da ficha escritos e dentro dos limites de caracteres
- [x] Aviso de licença do FFmpeg dentro do app (*Sobre → Ver licenças*)
- [x] Modelo de política de privacidade pronto para publicar
- [x] `targetSdk = 36`, exigido a partir de 31/08/2026
- [x] `flutter analyze` limpo e testes passando (CI roda a cada push)

Depende de você:

- [ ] Keystore criado **e com backup em dois lugares**
- [ ] `flutter build appbundle --release` gerando o `.aab`
- [ ] APK de release testado num celular de verdade
- [ ] `versionCode` maior que o do envio anterior
- [ ] 2 a 8 capturas de tela do app rodando
- [ ] Política de privacidade publicada numa URL pública
- [ ] Formulário de Segurança dos Dados respondido
- [ ] Classificação de conteúdo concluída
- [ ] 12+ testadores convidados no teste fechado

---

## Links oficiais

- [Play Console](https://play.google.com/console)
- [Criar conta de desenvolvedor](https://play.google.com/console/signup)
- [Exigência de API de destino](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Exigência de teste fechado (12 testadores)](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Formulário de Segurança dos Dados](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Especificações de imagens da ficha](https://support.google.com/googleplay/android-developer/answer/9866151)
- [Assinatura de apps Flutter](https://docs.flutter.dev/deployment/android)
