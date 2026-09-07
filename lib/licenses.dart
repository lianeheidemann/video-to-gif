import 'package:flutter/foundation.dart';

/// Registra o aviso de licença do FFmpeg na tela de licenças do app.
///
/// A LGPL exige três coisas de quem distribui um binário fechado ligado a
/// uma biblioteca LGPL: dizer que a usa, dizer sob qual licença, e apontar
/// onde obter o código-fonte dela. Como o FFmpeg entra aqui como biblioteca
/// dinâmica (.so dentro do APK), o requisito de "permitir a substituição da
/// biblioteca" já está atendido pela própria forma de empacotamento.
///
/// Chame [registerThirdPartyLicenses] no `main()`. O texto aparece em
/// *Sobre → Licenças*, que é onde a revisão da Play Store procura.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['FFmpeg'],
      'Este aplicativo usa o FFmpeg (https://ffmpeg.org), licenciado sob a '
      'GNU Lesser General Public License (LGPL) versão 2.1 ou posterior.\n\n'
      'O FFmpeg é usado nesta build SEM nenhum componente sob licença GPL '
      '(x264, x265, xvid e vid.stab não estão incluídos). A build inclui '
      'libwebp, dav1d, libvpx e libtheora — todas bibliotecas com licença '
      'permissiva/LGPL, sem nenhum componente GPL.\n\n'
      'O código-fonte do FFmpeg está disponível em '
      'https://github.com/FFmpeg/FFmpeg e o texto completo da LGPL em '
      'https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html\n\n'
      'As bibliotecas do FFmpeg são distribuídas neste aplicativo como '
      'bibliotecas compartilhadas (.so), sem modificações.',
    );

    yield const LicenseEntryWithLineBreaks(
      ['ffmpeg-kit-flutter-new'],
      'Empacotamento do FFmpeg para Flutter (variante "_video"), '
      'licenciado sob a GNU Lesser General Public License (LGPL) versão '
      '3.0.\n\n'
      'Código-fonte: https://github.com/sk3llo/ffmpeg_kit_flutter\n'
      'Texto da licença: https://www.gnu.org/licenses/lgpl-3.0.html',
    );

    yield const LicenseEntryWithLineBreaks(
      ['libwebp'],
      'Biblioteca de codificação WebP usada pelo FFmpeg para gerar o WebP '
      'animado, desenvolvida pelo Google e licenciada sob uma licença '
      'permissiva estilo BSD (não é GPL nem LGPL).\n\n'
      'Código-fonte: https://chromium.googlesource.com/webm/libwebp',
    );
  });
}
