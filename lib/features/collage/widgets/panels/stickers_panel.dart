import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/services/imported_asset_store.dart';
import '../../../../core/services/sticker_folder_store.dart';
import '../../models/sticker_catalog.dart';
import '../asset_thumbs.dart';
import '../folder_tab.dart';

/// Painel da aba "Stickers": a fileira de pastas (as embutidas, as criadas
/// pela pessoa e o botão de criar) e, embaixo, a arte da pasta aberta —
/// primeiro os stickers que vêm com o app, depois os importados, e no fim o
/// ladrilho de importar nas pastas que aceitam.
///
/// Todo o trabalho com arquivo fica na tela: criar, renomear e apagar pasta,
/// importar e remover sticker, e acrescentar um à montagem. São operações
/// assíncronas que mexem em listas que a tela carrega uma vez no `initState`
/// e três abas diferentes alteram.
///
/// [pendingFolderScrollId] é o id de uma pasta recém-criada que ainda precisa
/// entrar no campo de visão. Quem o consome é o `Builder` da fileira, durante
/// o build — por isso [onPendingScrollConsumed] limpa o campo com uma
/// atribuição simples na tela, sem `setState`: chamar `setState` de dentro de
/// um build lançaria exceção.
class CollageStickersPanel extends StatelessWidget {
  const CollageStickersPanel({
    super.key,
    required this.stickerFolderId,
    required this.customFolders,
    required this.importedStickers,
    required this.pendingFolderScrollId,
    required this.onPendingScrollConsumed,
    required this.onFolderSelected,
    required this.onOpenFolderMenu,
    required this.onCreateFolder,
    required this.onAddBundledSticker,
    required this.onAddImportedSticker,
    required this.onRemoveSticker,
    required this.onImportSticker,
  });

  /// Id da pasta aberta: de uma embutida ([BundledStickerFolder.id]) ou de
  /// uma criada pela pessoa ([StickerFolder.id]).
  final String stickerFolderId;

  final List<StickerFolder> customFolders;
  final List<ImportedAsset> importedStickers;
  final String? pendingFolderScrollId;
  final VoidCallback onPendingScrollConsumed;
  final ValueChanged<String> onFolderSelected;
  final ValueChanged<StickerFolder> onOpenFolderMenu;
  final VoidCallback onCreateFolder;
  final ValueChanged<(String path, String label)> onAddBundledSticker;
  final ValueChanged<ImportedAsset> onAddImportedSticker;
  final ValueChanged<ImportedAsset> onRemoveSticker;
  final void Function({String? folderId}) onImportSticker;

  @override
  Widget build(BuildContext context) {
    final bundledFolder = _openBundledFolder;
    // A pasta pode ter arte embutida, stickers importados, ou os dois.
    final bundledStickers = bundledFolder == null
        ? const <(String path, String label)>[]
        : bundledStickersFor(bundledFolder);
    final showsImports = bundledFolder == null || bundledFolder.acceptsImports;
    final imported = _stickersInOpenFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fileira de pastas e miniaturas de sticker bem menores que o
        // padrão do resto do app — este é o único lugar com tanta coisa
        // pequena lado a lado, então o tamanho das outras miniaturas
        // (seletor de fundo, trocar foto) fica como está.
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Fileira curta (embutidas + poucas dezenas de pastas no
            // máximo): manter mais itens construídos fora da tela custa
            // pouco e garante que uma pasta recém-criada já exista na árvore
            // (e portanto seja alcançável por `Scrollable.ensureVisible`,
            // ver o `Builder` abaixo) mesmo numa tela estreita de celular,
            // onde a área visível + cache padrão pode não chegar até ela.
            scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
            // +1 pelo botão de criar pasta, sempre no fim da linha.
            itemCount: _visibleBundledFolders.length + customFolders.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              if (index < _visibleBundledFolders.length) {
                final folder = _visibleBundledFolders[index];
                return FolderTab(
                  label: folder.label,
                  selected: folder.id == stickerFolderId,
                  onTap: () => onFolderSelected(folder.id),
                );
              }
              final customIndex = index - _visibleBundledFolders.length;
              if (customIndex < customFolders.length) {
                final folder = customFolders[customIndex];
                // A pasta recém-criada rola até ficar visível sozinha (ver
                // [_createStickerFolder]) — igual ao ícone de ajuste
                // selecionado em [ColorAdjustPanel], um `Builder` dá a este
                // item específico o próprio `BuildContext`, que
                // `Scrollable.ensureVisible` usa para centralizar exatamente
                // ele na fileira. Calcular a posição na mão (por
                // `maxScrollExtent`) dependia do layout já estar pronto no
                // frame seguinte; isto usa a posição real do item, então
                // funciona mesmo se o painel ainda estiver se ajustando
                // (ex.: o teclado fechando ao mesmo tempo).
                return Builder(
                  builder: (itemContext) {
                    if (pendingFolderScrollId == folder.id) {
                      onPendingScrollConsumed();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!itemContext.mounted) return;
                        Scrollable.ensureVisible(
                          itemContext,
                          alignment: 0.5,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      });
                    }
                    return FolderTab(
                      label: folder.name,
                      selected: folder.id == stickerFolderId,
                      onTap: () => onFolderSelected(folder.id),
                      onLongPress: () => onOpenFolderMenu(folder),
                    );
                  },
                );
              }
              return FolderTab(
                label: 'Nova pasta',
                selected: false,
                icon: Icons.create_new_folder_outlined,
                onTap: onCreateFolder,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 58,
          // Uma fileira só: primeiro a arte embutida da pasta, depois o que
          // foi importado para ela e, no fim, o tile de importar (nas pastas
          // que aceitam importação). Antes eram dois caminhos separados, e
          // uma pasta com as duas coisas — como "GitHub" — só mostrava uma.
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount:
                bundledStickers.length +
                imported.length +
                (showsImports ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index < bundledStickers.length) {
                final sticker = bundledStickers[index];
                // `Center`: dentro de um `ListView` horizontal, o filho
                // direto é estirado para a altura inteira da fileira,
                // ignorando a altura que o `Container` pede — sem isto a
                // miniatura saía do tamanho da fileira (58), não dos 36
                // pedidos.
                return Center(
                  child: GestureDetector(
                    onTap: () => onAddBundledSticker(sticker),
                    child: _bundledStickerThumb(
                      context,
                      sticker,
                      size: 44,
                      height: 36,
                    ),
                  ),
                );
              }
              final importedIndex = index - bundledStickers.length;
              if (importedIndex < imported.length) {
                final asset = imported[importedIndex];
                return Center(
                  child: GestureDetector(
                    onTap: () => onAddImportedSticker(asset),
                    onLongPress: () => onRemoveSticker(asset),
                    child: ImportedAssetThumb(
                      asset: asset,
                      selected: false,
                      size: 44,
                      height: 36,
                    ),
                  ),
                );
              }
              return ImportAssetTile(
                // Importar de dentro de uma pasta já põe o sticker nela; em
                // "Importados" a pasta é nula.
                onTap: () => onImportSticker(
                  folderId: bundledFolder == BundledStickerFolder.imported
                      ? null
                      : stickerFolderId,
                ),
                label: 'Importar',
                size: 44,
                height: 36,
              );
            },
          ),
        ),
      ],
    );
  }

  /// Abas embutidas que aparecem na fileira.
  ///
  /// "Novos" fica de fora enquanto está vazia: ela só existe para receber
  /// sticker solto em `assets/sticker` depois, e uma aba vazia a mais em
  /// toda instalação só empurraria o botão de criar pasta para fora da tela.
  static List<BundledStickerFolder> get _visibleBundledFolders => [
    for (final folder in BundledStickerFolder.values)
      if (folder != BundledStickerFolder.novos ||
          descobertosFor(BundledStickerFolder.novos).isNotEmpty)
        folder,
  ];

  /// Pasta embutida aberta agora, ou `null` quando a aberta é uma criada
  /// pelo usuário.
  BundledStickerFolder? get _openBundledFolder {
    for (final folder in BundledStickerFolder.values) {
      if (folder.id == stickerFolderId) return folder;
    }
    return null;
  }

  /// Stickers importados que moram na pasta aberta: os sem pasta ficam em
  /// "Importados", o resto em cada pasta criada pelo usuário.
  List<ImportedAsset> get _stickersInOpenFolder {
    final bundled = _openBundledFolder;
    if (bundled != null && !bundled.acceptsImports) return const [];
    // "Importados" é a pasta sem id (também onde caem as entradas antigas);
    // as demais guardam o próprio id em cada sticker.
    final folderId = bundled == BundledStickerFolder.imported
        ? null
        : stickerFolderId;
    return importedStickers.where((a) => a.folderId == folderId).toList();
  }

  Widget _bundledStickerThumb(
    BuildContext context,
    (String path, String label) sticker, {
    double size = 62,
    double height = 46,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: SvgPicture.asset(sticker.$1, fit: BoxFit.contain),
    );
  }
}
