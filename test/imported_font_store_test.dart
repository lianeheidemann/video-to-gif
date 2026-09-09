import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_to_gif/services/imported_font_store.dart';

/// Mesma forma de `ImportedFontStore._encode` — reconstruída aqui para
/// popular o `SharedPreferences` mockado direto, sem passar por
/// `import()`, que abriria o seletor de arquivos de verdade.
String _encode({
  required String id,
  required String family,
  required String label,
  required String filePath,
}) => jsonEncode({
  'id': id,
  'family': family,
  'label': label,
  'filePath': filePath,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('imported_font_store_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('loadAll ignora entradas cujo arquivo não existe mais', () async {
    SharedPreferences.setMockInitialValues({
      'importedFonts': [
        _encode(
          id: 'a',
          family: 'ImportedFont1',
          label: 'Sumiu',
          filePath: '${tempDir.path}/nao_existe.ttf',
        ),
      ],
    });

    const store = ImportedFontStore();
    expect(await store.loadAll(), isEmpty);
  });

  test('arquivo que não é fonte fica de fora, sem derrubar a lista', () async {
    // Bytes que o engine não aceita como fonte: a entrada some da lista em
    // vez de virar uma opção quebrada (ou uma exceção na abertura da tela).
    final fake = File('${tempDir.path}/nao_e_fonte.ttf');
    await fake.writeAsBytes([1, 2, 3, 4]);

    SharedPreferences.setMockInitialValues({
      'importedFonts': [
        _encode(
          id: 'a',
          family: 'ImportedFont1',
          label: 'Quebrada',
          filePath: fake.path,
        ),
      ],
    });

    const store = ImportedFontStore();
    expect(await store.loadAll(), isEmpty);
  });

  test('remove apaga o arquivo e a entrada guardada', () async {
    final file = File('${tempDir.path}/fonte.ttf');
    await file.writeAsBytes([1, 2, 3, 4]);

    SharedPreferences.setMockInitialValues({
      'importedFonts': [
        _encode(
          id: 'a',
          family: 'ImportedFont1',
          label: 'Fonte',
          filePath: file.path,
        ),
        _encode(
          id: 'b',
          family: 'ImportedFont2',
          label: 'Outra',
          filePath: '${tempDir.path}/outra.ttf',
        ),
      ],
    });

    const store = ImportedFontStore();
    await store.remove('a');

    expect(await file.exists(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('importedFonts')!;
    expect(raw, hasLength(1));
    expect(raw.single.contains('ImportedFont2'), isTrue);
  });

  test('entrada estragada é ignorada em vez de derrubar a lista', () async {
    SharedPreferences.setMockInitialValues({
      'importedFonts': ['nao é json'],
    });

    const store = ImportedFontStore();
    expect(await store.loadAll(), isEmpty);
  });
}
