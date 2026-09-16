import 'package:flutter/material.dart';

import '../models/conversion_settings.dart';
import '../models/photo_info.dart';
import '../models/video_info.dart';
import 'collage_page.dart';
import 'editor_page.dart';
import 'home_page.dart';
import 'photo_frame_page.dart';

/// Os 3 editores que ficam vivos em memória enquanto o app está rodando —
/// "Converter formato" fica de fora de propósito: não guarda projeto em
/// andamento, continua sendo empilhado com `Navigator.push` normalmente.
enum ProjectSlot { video, photo, collage }

enum _ResumeChoice { resume, restart }

/// Casca do app: mantém a Home e os 3 editores (vídeo/foto/montagem) sempre
/// montados dentro de um [IndexedStack], em vez de empilhados com
/// `Navigator.push`/`pop`. Isso evita que o `State` de cada editor (cortes,
/// camadas da montagem, ajustes...) seja destruído quando o usuário volta
/// para a Home — o próprio `State` do Dart passa a ser "o projeto salvo em
/// memória", que só some quando o processo do app morre (fechar o app de
/// verdade), nunca só por navegar para outra tela.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Acha o [AppShellState] mais próximo na árvore — funciona a partir de
  /// qualquer tela filha (Home ou um dos 3 editores), já que todas elas são
  /// descendentes do [IndexedStack] montado em [AppShellState.build].
  static AppShellState of(BuildContext context) {
    final state = context.findAncestorStateOfType<AppShellState>();
    assert(state != null, 'AppShell.of() chamado fora da árvore do AppShell');
    return state!;
  }

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  static const _labels = {
    ProjectSlot.video: 'vídeo',
    ProjectSlot.photo: 'foto',
    ProjectSlot.collage: 'montagem',
  };

  /// 0 = Home; 1/2/3 = vídeo/foto/montagem, na mesma ordem dos filhos do
  /// [IndexedStack] em [build].
  int _visibleIndex = 0;

  Widget? _videoEditor;
  Widget? _photoEditor;
  Widget? _collageEditor;

  bool hasProject(ProjectSlot slot) => switch (slot) {
    ProjectSlot.video => _videoEditor != null,
    ProjectSlot.photo => _photoEditor != null,
    ProjectSlot.collage => _collageEditor != null,
  };

  Future<void> openVideoEditor({
    required VideoInfo video,
    required ConversionSettings settings,
  }) async {
    if (_videoEditor != null) {
      final choice = await _askResumeOrNew(ProjectSlot.video);
      if (!mounted || choice == null) return;
      if (choice == _ResumeChoice.resume) {
        setState(() => _visibleIndex = 1);
        return;
      }
    }
    setState(() {
      _videoEditor = KeyedSubtree(
        key: UniqueKey(),
        child: EditorPage(video: video, initialSettings: settings),
      );
      _visibleIndex = 1;
    });
  }

  Future<void> openPhotoEditor(PhotoInfo photo) async {
    if (_photoEditor != null) {
      final choice = await _askResumeOrNew(ProjectSlot.photo);
      if (!mounted || choice == null) return;
      if (choice == _ResumeChoice.resume) {
        setState(() => _visibleIndex = 2);
        return;
      }
    }
    setState(() {
      _photoEditor = KeyedSubtree(
        key: UniqueKey(),
        child: PhotoFramePage(photo: photo),
      );
      _visibleIndex = 2;
    });
  }

  Future<void> openCollage(List<PhotoInfo> photos) async {
    if (_collageEditor != null) {
      final choice = await _askResumeOrNew(ProjectSlot.collage);
      if (!mounted || choice == null) return;
      if (choice == _ResumeChoice.resume) {
        setState(() => _visibleIndex = 3);
        return;
      }
    }
    setState(() {
      _collageEditor = KeyedSubtree(
        key: UniqueKey(),
        child: CollagePage(photos: photos),
      );
      _visibleIndex = 3;
    });
  }

  /// Volta para a Home sem descartar nenhum projeto em andamento — os
  /// editores continuam montados (só saem de cena), prontos para retomar.
  void goHome() {
    if (_visibleIndex != 0) setState(() => _visibleIndex = 0);
  }

  Future<_ResumeChoice?> _askResumeOrNew(ProjectSlot slot) {
    final label = _labels[slot]!;
    return showDialog<_ResumeChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Projeto em andamento'),
        content: Text(
          'Você já tem um projeto de $label em andamento. Quer continuar '
          'de onde parou ou começar um novo? O projeto atual será perdido '
          'se você começar um novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ResumeChoice.restart),
            child: const Text('Novo projeto'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ResumeChoice.resume),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _visibleIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) goHome();
      },
      child: IndexedStack(
        index: _visibleIndex,
        // `HomePage()` não é `const` de propósito: precisa reconstruir toda
        // vez que este `AppShellState` reconstrói (ex.: depois de
        // `openVideoEditor`), para os selos de "projeto em andamento"
        // (ver `hasProject`) refletirem o estado atual — um `const` faria o
        // Flutter reaproveitar a mesma instância e pular o rebuild.
        children: [
          HomePage(),
          _videoEditor ?? const SizedBox.shrink(),
          _photoEditor ?? const SizedBox.shrink(),
          _collageEditor ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}
