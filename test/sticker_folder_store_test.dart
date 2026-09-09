import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_to_gif/services/sticker_folder_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const store = StickerFolderStore();

  test('criar guarda a pasta e ela volta em loadAll', () async {
    final created = await store.create('Xícaras');

    final folders = await store.loadAll();
    expect(folders, hasLength(1));
    expect(folders.single.id, created.id);
    expect(folders.single.name, 'Xícaras');
    // O prefixo é o que garante que uma pasta criada nunca colida com os ids
    // das embutidas ("reactions", "imported", …).
    expect(created.id.startsWith('f_'), isTrue);
  });

  test('nome vazio ou só com espaços cai no rótulo padrão', () async {
    await store.create('   ');
    final folders = await store.loadAll();
    expect(folders.single.name, 'Nova pasta');
  });

  test('renomear troca só o nome da pasta pedida', () async {
    final first = await store.create('Uma');
    final second = await store.create('Outra');

    await store.rename(first.id, '  Renomeada  ');

    final folders = await store.loadAll();
    expect(folders.map((f) => f.name), ['Renomeada', 'Outra']);
    expect(folders.map((f) => f.id), [first.id, second.id]);
  });

  test('renomear para vazio não muda nada', () async {
    final folder = await store.create('Uma');
    await store.rename(folder.id, '  ');
    final folders = await store.loadAll();
    expect(folders.single.name, 'Uma');
  });

  test('apagar tira só aquela pasta', () async {
    final first = await store.create('Uma');
    await store.create('Outra');

    await store.remove(first.id);

    final folders = await store.loadAll();
    expect(folders.map((f) => f.name), ['Outra']);
  });

  test('entrada estragada é ignorada em vez de derrubar a lista', () async {
    final folder = await store.create('Boa');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('stickerFolders')!;
    await prefs.setStringList('stickerFolders', ['{isso não é json', ...raw]);

    final folders = await store.loadAll();
    expect(folders.map((f) => f.id), [folder.id]);
  });
}
