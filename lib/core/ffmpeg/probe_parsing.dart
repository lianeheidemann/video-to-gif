import 'package:ffmpeg_kit_flutter_new_video/stream_information.dart';

/// Leitura dos campos que o FFprobe devolve como texto solto — duração, fps
/// e rotação —, separada da chamada ao FFprobe em si para poder ser lida e
/// testada sem tocar em arquivo nenhum.

double? durationFrom(StreamInformation stream) {
  final raw = stream.getAllProperties()?['duration'];
  return raw == null ? null : double.tryParse(raw.toString());
}

/// O FFprobe devolve taxa de quadros como fração ("30000/1001").
double frameRateOf(StreamInformation stream) {
  final props = stream.getAllProperties() ?? const {};
  for (final key in ['avg_frame_rate', 'r_frame_rate']) {
    final raw = props[key]?.toString();
    if (raw == null || raw.isEmpty) continue;
    final parts = raw.split('/');
    if (parts.length == 2) {
      final num = double.tryParse(parts[0]) ?? 0;
      final den = double.tryParse(parts[1]) ?? 0;
      if (num > 0 && den > 0) return num / den;
    } else {
      final value = double.tryParse(raw);
      if (value != null && value > 0) return value;
    }
  }
  return 30;
}

/// A rotação pode vir em `tags.rotate` (arquivos antigos) ou em
/// `side_data_list` como matriz de exibição (arquivos modernos de celular).
int rotationOf(StreamInformation stream) {
  final props = stream.getAllProperties() ?? const {};

  final tags = props['tags'];
  if (tags is Map) {
    final rotate = tags['rotate'];
    final parsed = int.tryParse('$rotate');
    if (parsed != null) return normalizeRotation(parsed);
  }

  final sideData = props['side_data_list'];
  if (sideData is List) {
    for (final entry in sideData) {
      if (entry is Map && entry['rotation'] != null) {
        final parsed = double.tryParse('${entry['rotation']}');
        if (parsed != null) return normalizeRotation(parsed.round());
      }
    }
  }
  return 0;
}

int normalizeRotation(int degrees) {
  final normalized = ((degrees % 360) + 360) % 360;
  return normalized;
}

// ------------------------------------------------------------------
// Montagem dos filtros
// ------------------------------------------------------------------

/// Cadeia de filtros de vídeo, na única ordem que dá o resultado certo:
///
///  1. `crop`   — em pixels do vídeo original, então tem que vir primeiro;
///  2. `setpts` — muda a velocidade reescrevendo os tempos dos quadros;
///  3. `fps`    — reamostra para a taxa final (depois da velocidade, senão
///                o cálculo de quadros sai errado);
///  4. `scale`  — redimensiona por último, sobre menos pixels possível.
