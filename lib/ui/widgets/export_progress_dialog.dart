import 'package:flutter/material.dart';

/// Estado do pop-up de exportação: quanto já foi feito e se o cancelamento
/// já foi pedido. Os dois num objeto só para o diálogo ouvir um
/// `ValueListenable` apenas — ele vive numa rota própria, então não é
/// reconstruído pelo `setState` da tela que o abriu.
class ExportProgress {
  const ExportProgress({this.value = 0, this.cancelling = false});

  final double value;
  final bool cancelling;
}

/// Pop-up de "exportando" da montagem: anel de progresso com o percentual,
/// o formato de saída e o tamanho em pixels, mais o botão de cancelar. Fica
/// na tela até a exportação terminar (ou ser cancelada) — por isso não fecha
/// no toque fora nem no botão voltar, quem o fecha é quem o abriu.
///
/// Mesmo desenho da tela de conversão de vídeo ([ConvertingPage]), mas sem a
/// linha de "peso previsto": a montagem não passa pela calibragem de tamanho
/// que dá esse número no vídeo.
class ExportProgressDialog extends StatelessWidget {
  const ExportProgressDialog({
    super.key,
    required this.progress,
    required this.formatLabel,
    required this.width,
    required this.height,
    this.onCancel,
  });

  /// Progresso e estado de cancelamento. Enquanto o progresso for ~0 o anel
  /// gira indeterminado, para não parecer travado antes do primeiro quadro
  /// sair.
  final ValueListenable<ExportProgress> progress;

  final String formatLabel;
  final int width;
  final int height;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: ValueListenableBuilder<ExportProgress>(
            valueListenable: progress,
            builder: (context, state, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: state.value > 0.01 ? state.value : null,
                          strokeWidth: 8,
                        ),
                      ),
                      Text(
                        '${(state.value * 100).clamp(0, 100).round()}%',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  state.cancelling
                      ? 'Cancelando…'
                      : 'Exportando em $formatLabel',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '$width×$height px',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onCancel != null) ...[
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: state.cancelling ? null : onCancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
