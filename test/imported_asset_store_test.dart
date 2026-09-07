import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_to_gif/services/imported_asset_store.dart';

/// Mesma forma de `ImportedAssetStore._encode` — reconstruída aqui só para
/// popular o `SharedPreferences` mockado direto, sem passar por
/// `ImportedAssetStore.import()` (que abriria o seletor de arquivos de
/// verdade, indisponível neste ambiente de teste).
String _encode({
  required String id,
  required String label,
  required String filePath,
  required bool isVector,
  required double aspect,
}) => jsonEncode({
  'id': id,
  'label': label,
  'filePath': filePath,
  'isVector': isVector,
  'aspect': aspect,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('imported_asset_store_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('loadAll ignora entradas cujo arquivo copiado não existe mais', () async {
    final existingFile = File('${tempDir.path}/existe.png');
    await existingFile.writeAsBytes([0]);

    SharedPreferences.setMockInitialValues({
      'importedStickers': [
        _encode(id: 'a', label: 'A', filePath: existingFile.path, isVector: false, aspect: 1.0),
        _encode(
          id: 'b',
          label: 'B',
          filePath: '${tempDir.path}/nao_existe.png',
          isVector: false,
          aspect: 1.0,
        ),
      ],
    });

    const store = ImportedAssetStore(ImportedAssetKind.sticker);
    final assets = await store.loadAll();

    expect(assets.length, 1);
    expect(assets.single.id, 'a');
  });

  test('remove apaga o arquivo copiado e o metadado persistido', () async {
    final file = File('${tempDir.path}/sticker.png');
    await file.writeAsBytes([0]);

    SharedPreferences.setMockInitialValues({
      'importedStickers': [
        _encode(id: 'a', label: 'A', filePath: file.path, isVector: false, aspect: 1.0),
      ],
    });

    const store = ImportedAssetStore(ImportedAssetKind.sticker);
    await store.remove('a');

    expect(await file.exists(), isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('sticker e imagem de fundo usam chaves de preferências separadas', () async {
    final stickerFile = File('${tempDir.path}/s.png');
    await stickerFile.writeAsBytes([0]);

    SharedPreferences.setMockInitialValues({
      'importedStickers': [
        _encode(id: 's1', label: 'Sticker', filePath: stickerFile.path, isVector: false, aspect: 1.0),
      ],
    });

    const stickerStore = ImportedAssetStore(ImportedAssetKind.sticker);
    const backgroundStore = ImportedAssetStore(ImportedAssetKind.backgroundImage);

    expect(await stickerStore.loadAll(), hasLength(1));
    // A imagem de fundo lê a chave `importedBackgroundImages`, nunca
    // preenchida aqui — não deve enxergar a entrada do sticker.
    expect(await backgroundStore.loadAll(), isEmpty);
  });
}
