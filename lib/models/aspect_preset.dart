/// Proporções oferecidas em toda tela de recorte do app (vídeo, foto e
/// montagem) — a mesma lista em todo lugar, para o usuário encontrar as
/// mesmas opções não importa qual recorte esteja usando.
class AspectPreset {
  const AspectPreset(this.label, this.ratio, {this.hint = ''});

  final String label;
  final double? ratio; // null = manter a proporção original
  final String hint;

  static const presets = <AspectPreset>[
    AspectPreset('Original', null),
    AspectPreset('1:1', 1.0, hint: 'Quadrado'),
    AspectPreset('4:5', 4 / 5, hint: 'Retrato'),
    AspectPreset('5:4', 5 / 4),
    AspectPreset('2:3', 2 / 3),
    AspectPreset('3:2', 3 / 2, hint: 'Foto'),
    AspectPreset('3:4', 3 / 4),
    AspectPreset('4:3', 4 / 3, hint: 'Clássico'),
    AspectPreset('9:16', 9 / 16, hint: 'Stories'),
    AspectPreset('16:9', 16 / 9, hint: 'Paisagem'),
    AspectPreset('2:1', 2.0),
    AspectPreset('1:2', 0.5),
  ];
}
