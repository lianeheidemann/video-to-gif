import 'dart:io';

import 'package:flutter/material.dart';

/// Nome de arquivo padrão gerado pelo app para uma exportação, ex.:
/// `video_to_gif_2026-09-16_1732` — sem extensão, que cada tela acrescenta
/// de acordo com o formato de saída.
String defaultFileName(String prefix, [DateTime? when]) {
  final now = when ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${now.year}-${two(now.month)}-${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}';
  return '${prefix}_$stamp';
}

/// Remove caracteres inválidos para nome de arquivo (`/ \ : * ? " < > |`) e
/// espaços redundantes. Cai em [fallback] se o resultado ficar vazio.
String sanitizeFileName(String input, {required String fallback}) {
  final cleaned = input
      .replaceAll(RegExp(r'[/\\:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

/// Renomeia [source] — o arquivo temporário gerado pela conversão — para o
/// nome escolhido pelo usuário (ou [fallbackName], se deixado em branco ou
/// só com caracteres inválidos), mantendo [extension]. Necessário porque
/// `Gal`/`share_plus` usam o nome do próprio arquivo de origem: não existe
/// parâmetro separado de "nome de exibição" para a galeria/compartilhamento.
Future<File> renameForSaving(
  File source, {
  required String chosenName,
  required String extension,
  required String fallbackName,
}) async {
  final safeName = sanitizeFileName(chosenName, fallback: fallbackName);
  final target = '${source.parent.path}/$safeName.$extension';
  if (target == source.path) return source;
  return source.rename(target);
}

/// Campo de texto compacto para o usuário nomear o arquivo antes de salvar —
/// sempre pré-preenchido com um nome gerado pelo app (via [controller]), mas
/// totalmente editável, exibido logo acima do botão de salvar/compartilhar.
class SaveNameField extends StatelessWidget {
  const SaveNameField({super.key, required this.controller, this.enabled = true});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Nome do arquivo',
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// Diálogo "antes de salvar": usado pelas telas que exportam direto do
/// editor (sem uma tela de resultado dedicada, como [SaveNameField] tem em
/// `ResultPage`) — pergunta o nome do arquivo, pré-preenchido com
/// [defaultName], antes de gerar/salvar. Devolve o nome escolhido, ou `null`
/// se o usuário cancelar.
Future<String?> askSaveName(
  BuildContext context, {
  required String defaultName,
  String title = 'Nome do arquivo',
}) {
  final controller = TextEditingController(text: defaultName);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SaveNameField(controller: controller),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Salvar'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
