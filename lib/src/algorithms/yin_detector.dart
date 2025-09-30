import 'dart:math' as math;
import 'dart:typed_data';

/// Implémentation de l'algorithme YIN pour détection de pitch
/// Référence: "YIN, a fundamental frequency estimator for speech and music" (2002)
class YinPitchDetector {
  final double sampleRate;
  final double minF0;
  final double maxF0;
  final double troughThreshold;

  late final int _minPeriod;
  late final int _maxPeriod;
  late final Float64List _yinBuffer;

  YinPitchDetector({
    required this.sampleRate,
    this.minF0 = 70.0,
    this.maxF0 = 1000.0,
    this.troughThreshold = 0.15,
  }) {
    _minPeriod = (sampleRate / maxF0).floor();
    _maxPeriod = (sampleRate / minF0).ceil();
    _yinBuffer = Float64List(_maxPeriod + 1);
  }

  /// Estime la fréquence fondamentale d'un frame audio
  /// Retourne [frequency, confidence] ou null si pas de pitch détecté
  ({double frequency, double confidence})? estimatePitch(
      Float64List audioFrame) {
    final frameSize = audioFrame.length;

    // Étape 1: Calcul de la différence (autocorrélation)
    _calculateDifference(audioFrame, frameSize);

    // Étape 2: Normalisation cumulative moyenne
    _cumulativeMeanNormalizedDifference(frameSize);

    // Étape 3: Recherche du minimum absolu
    final tauEstimate = _getAbsoluteThresholdTau();

    if (tauEstimate == -1) return null;

    // Étape 4: Interpolation parabolique pour affiner
    final preciseEstimate = _parabolicInterpolation(tauEstimate);

    // Calcul de la fréquence et confiance
    final frequency = sampleRate / preciseEstimate;
    final confidence = 1.0 - _yinBuffer[tauEstimate];

    // Validation de la gamme
    if (frequency < minF0 || frequency > maxF0) return null;
    if (confidence < 0.75) return null; // Seuil de confiance minimum

    return (frequency: frequency, confidence: confidence);
  }

  /// Étape 1: Calcul de la fonction de différence d(τ)
  void _calculateDifference(Float64List buffer, int frameSize) {
    _yinBuffer[0] = 1.0;

    for (int tau = 1; tau <= _maxPeriod && tau < frameSize; tau++) {
      double sum = 0.0;

      for (int i = 0; i < frameSize - tau; i++) {
        final delta = buffer[i] - buffer[i + tau];
        sum += delta * delta;
      }

      _yinBuffer[tau] = sum;
    }
  }

  /// Étape 2: Normalisation cumulative moyenne d'(τ)
  void _cumulativeMeanNormalizedDifference(int frameSize) {
    double runningSum = 0.0;

    _yinBuffer[0] = 1.0;

    for (int tau = 1; tau <= _maxPeriod && tau < frameSize; tau++) {
      runningSum += _yinBuffer[tau];

      if (runningSum == 0) {
        _yinBuffer[tau] = 1.0;
      } else {
        _yinBuffer[tau] *= tau / runningSum;
      }
    }
  }

  /// Étape 3: Recherche du premier minimum sous le seuil
  int _getAbsoluteThresholdTau() {
    // Commencer la recherche après la période minimum
    for (int tau = _minPeriod; tau <= _maxPeriod; tau++) {
      if (tau >= _yinBuffer.length) break;

      if (_yinBuffer[tau] < troughThreshold) {
        // Vérifier que c'est un minimum local
        while (tau + 1 < _yinBuffer.length &&
            tau + 1 <= _maxPeriod &&
            _yinBuffer[tau + 1] < _yinBuffer[tau]) {
          tau++;
        }
        return tau;
      }
    }

    // Si pas de minimum sous le seuil, prendre le minimum absolu
    double minValue = double.infinity;
    int minTau = -1;

    for (int tau = _minPeriod;
        tau <= _maxPeriod && tau < _yinBuffer.length;
        tau++) {
      if (_yinBuffer[tau] < minValue) {
        minValue = _yinBuffer[tau];
        minTau = tau;
      }
    }

    return minTau;
  }

  /// Étape 4: Interpolation parabolique pour affiner l'estimation
  double _parabolicInterpolation(int tauEstimate) {
    if (tauEstimate == 0 ||
        tauEstimate >= _yinBuffer.length - 1 ||
        tauEstimate >= _maxPeriod) {
      return tauEstimate.toDouble();
    }

    final double s0 = _yinBuffer[tauEstimate - 1];
    final double s1 = _yinBuffer[tauEstimate];
    final double s2 = _yinBuffer[tauEstimate + 1];

    // Interpolation parabolique
    final double a = (s2 + s0 - 2 * s1) / 2;
    final double b = (s2 - s0) / 2;

    if (a.abs() < 1e-10) return tauEstimate.toDouble();

    final double xVertex = -b / (2 * a);

    // Limiter la correction à [-1, 1]
    final double correction = math.max(-1.0, math.min(1.0, xVertex));

    return tauEstimate + correction;
  }

  /// Obtient des informations de debug sur le buffer YIN
  Map<String, dynamic> getDebugInfo() {
    return {
      'sampleRate': sampleRate,
      'minF0': minF0,
      'maxF0': maxF0,
      'minPeriod': _minPeriod,
      'maxPeriod': _maxPeriod,
      'troughThreshold': troughThreshold,
      'bufferSize': _yinBuffer.length,
    };
  }
}