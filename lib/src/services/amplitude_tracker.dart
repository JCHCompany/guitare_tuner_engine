import 'dart:math' as math;

/// Suit le niveau RMS récent pour fournir un seuil de silence adaptatif
/// et un facteur d'amplitude [0..1] pour pondérer la confiance.
class AmplitudeTracker {
  final int historySize;
  final double minThreshold;
  final double ratioOfRecentMax; // ex: 0.15 => 15% du max récent

  final List<double> _rmsHistory = <double>[];
  double _recentMax = 0.0;

  AmplitudeTracker({
    this.historySize = 24, // ~0.5–1.0 s selon hop
    this.minThreshold = 0.0001, // plancher anti-bruit
    this.ratioOfRecentMax = 0.10,
  });

  void add(double rms) {
    _rmsHistory.add(rms);
    if (_rmsHistory.length > historySize) {
      _rmsHistory.removeAt(0);
    }
    _recentMax = _rmsHistory.fold<double>(0.0, (m, v) => math.max(m, v));
  }

  double get dynamicSilenceThreshold {
    if (_recentMax <= 0.0) return minThreshold;
    return math.max(minThreshold, _recentMax * ratioOfRecentMax);
  }

  double get recentMax => _recentMax;

  /// Facteur d’amplitude [0..1] pour pondérer la confiance
  double amplitudeFactor(double rms) {
    if (_recentMax <= 0) return 0;
    final val = rms / _recentMax;
    if (val.isNaN || !val.isFinite) return 0.0;
    return val.clamp(0.0, 1.0);
  }
}
