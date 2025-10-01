import 'dart:math' as math;
import 'dart:typed_data';

/// Analyse la cohérence harmonique via corrélations retardées (faible coût)
class HarmonicAnalyzer {
  /// Calcule un score [0..1] de cohérence harmonique.
  /// Idée: pour f0 => période tau = sr/f0; mesurer similarité s(t) ~ s(t - k*tau)
  /// pour k ∈ {1,2,3} et normaliser.
  double support(Float64List frame, double sampleRate, double f0Hz) {
    if (f0Hz <= 0) return 0.0;
    final tau = (sampleRate / f0Hz);
    if (tau < 2) return 0.0;

    final taus = <int>{
      tau.round(),
      (tau / 2).round(), // harmonique 2*f0
      (tau / 3).round(), // harmonique 3*f0
    }.where((t) => t >= 2).toList();

    if (taus.isEmpty) return 0.0;

    final n = frame.length;
    final mean = _mean(frame);
    final std = _std(frame, mean);
    if (std == 0 || std.isNaN || !std.isFinite) return 0.0;

    double acc = 0.0;
    int cnt = 0;
    for (final t in taus) {
      final maxIdx = n - t;
      if (maxIdx <= 2) continue;
      double num = 0.0;
      double den1 = 0.0;
      double den2 = 0.0;
      for (int i = 0; i < maxIdx; i++) {
        final a = frame[i] - mean;
        final b = frame[i + t] - mean;
        num += a * b;
        den1 += a * a;
        den2 += b * b;
      }
      final den = math.sqrt((den1 * den2).abs());
      if (den > 0) {
        final r = (num / den).clamp(-1.0, 1.0);
        acc += r.abs();
        cnt++;
      }
    }
    if (cnt == 0) return 0.0;
    return (acc / cnt).clamp(0.0, 1.0);
  }

  double _mean(Float64List x) {
    double s = 0.0;
    for (final v in x) s += v;
    return s / x.length;
  }

  double _std(Float64List x, double m) {
    double s2 = 0.0;
    for (final v in x) {
      final d = v - m;
      s2 += d * d;
    }
    return math.sqrt(s2 / x.length);
  }
}
