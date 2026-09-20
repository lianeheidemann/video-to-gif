import 'package:flutter/material.dart';

import 'licenses.dart';
import 'models/collage_text.dart';
import 'preview_background_controller.dart';
import 'services/bundled_font_store.dart';
import 'services/bundled_frame_store.dart';
import 'services/bundled_sticker_store.dart';
import 'theme.dart';
import 'theme_controller.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Exigência da LGPL do FFmpeg: o aviso precisa estar acessível no app.
  registerThirdPartyLicenses();
  await loadThemeMode();
  await loadPreviewCheckerboardPreference();
  // Registra as fontes de `assets/fonts` antes da primeira tela, para a
  // lista de fontes do texto já nascer completa.
  final fonts = await const BundledFontStore().loadAll();
  bundledCollageFonts = [
    (null, 'Padrão'),
    for (final font in fonts) (font.family, font.label),
  ];
  bundledStickerAssets = await loadBundledStickerAssets();
  bundledImageFrames = await loadBundledImageFrames();
  runApp(const VideoToGifApp());
}

/// Widget raiz do app: configura o MaterialApp com os temas claro/escuro
/// e define a HomePage como tela inicial.
class VideoToGifApp extends StatelessWidget {
  const VideoToGifApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Video to GIF',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode,
          home: const HomePage(),
        );
      },
    );
  }
}
