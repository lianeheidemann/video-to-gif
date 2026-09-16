import 'package:flutter/material.dart';

import 'licenses.dart';
import 'theme.dart';
import 'theme_controller.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Exigência da LGPL do FFmpeg: o aviso precisa estar acessível no app.
  registerThirdPartyLicenses();
  await loadThemeMode();
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
