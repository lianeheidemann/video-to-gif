/// Uma imagem de fundo que já vem com o app, em `assets/background`.
class BundledBackground {
  const BundledBackground({required this.assetPath, required this.label});

  final String assetPath;
  final String label;
}

/// Os fundos prontos oferecidos na aba "Fundo" da montagem, antes dos que o
/// usuário importa. Valem para os dois alvos da aba, "Montagem" e "Fotos":
/// a lista alimenta o mesmo seletor nos dois casos.
class BackgroundImageLibrary {
  const BackgroundImageLibrary._();

  static const bundled = <BundledBackground>[
    BundledBackground(
      assetPath: 'assets/background/fundo_01_praia_entardecer.jpg',
      label: 'Praia',
    ),
    BundledBackground(
      assetPath: 'assets/background/fundo_02_montanhas_laranja.jpg',
      label: 'Montanhas',
    ),
    BundledBackground(
      assetPath: 'assets/background/fundo_03_coqueiros.jpg',
      label: 'Coqueiros',
    ),
    BundledBackground(
      assetPath: 'assets/background/fundo_04_nuvens_rosa.jpg',
      label: 'Nuvens',
    ),
  ];
}

/// Se [path] é um fundo pronto do app em vez de um arquivo importado.
///
/// `CollageBackground.imagePath` guarda os dois: um asset do app, como
/// `assets/background/...`, ou o caminho absoluto de um arquivo copiado para
/// a pasta de dados. Os dois nunca se confundem — arquivo importado é sempre
/// caminho absoluto, começando com `/`. Quem carrega a imagem (prévia,
/// exportação e animação) usa isto para saber de onde ler os bytes.
bool isBundledBackgroundPath(String path) => path.startsWith('assets/');
