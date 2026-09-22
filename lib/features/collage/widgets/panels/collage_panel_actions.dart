import 'package:flutter/foundation.dart';

import '../../models/collage_settings.dart';

/// As três ações que toda aba da montagem precisa devolver para a tela:
/// aplicar novas configurações, marcar um ponto de desfazer e avisar o
/// usuário.
///
/// Existe para não repetir os mesmos três parâmetros em sete construtores. A
/// tela monta uma instância e passa para todas as abas.
class CollagePanelActions {
  const CollagePanelActions({
    required this.update,
    required this.pushUndoCheckpoint,
    required this.message,
  });

  /// Aplica novas configurações. `pushUndo: false` nas mudanças contínuas
  /// (arrastar, sliders) já precedidas por [pushUndoCheckpoint] no início do
  /// gesto, para não empilhar um estado por quadro.
  final void Function(CollageSettings settings, {bool pushUndo}) update;

  /// Marca o estado atual como ponto de retorno, sem mudar nada.
  final VoidCallback pushUndoCheckpoint;

  /// Mostra um aviso curto na tela.
  final ValueChanged<String> message;
}
