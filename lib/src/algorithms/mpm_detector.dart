import 'dart:math' as math;
import 'dart:typed_data';
import 'package:fftea/fftea.dart';

/// Implémentation de l'algorithme MPM (McLeod Pitch Method)
/// Référence: "A Smarter Way to Find Pitch" (2005)
class MpmPitchDetector {
  final double sampleRate;
  final double minF0;
  final double maxF0;
  final double clarityThreshold;

  late final int _minPeriod;
  late final int _maxPeriod;
  late final FFT _fft;
  late final int _fftSize;

  MpmPitchDetector({
    required this.sampleRate,
    this.minF0 = 70.0,
    this.maxF0 = 1000.0,
    this.clarityThreshold = 0.75,
  }) {
    _minPeriod = (sampleRate / maxF0).floor();
    _maxPeriod = (sampleRate / minF0).ceil();

    // Taille FFT : puissance de 2 supérieure à 2 * frameSize
    _fftSize = _nextPowerOfTwo(_maxPeriod * 4);
    _fft = FFT(_fftSize);
  }

  /// Estime la fréquence fondamentale avec MPM
  /// Retourne [frequency, confidence] ou null si pas de pitch détecté
  ({double frequency, double confidence})? estimatePitch(
      Float64List audioFrame) {
    final frameSize = audioFrame.length;

    // Calcul de la NSDF (Normalized Square Difference Function)
    final nsdf = _computeNSDF(audioFrame, frameSize);

    // Recherche des pics dans la NSDF
    final peaks = _findPeaks(nsdf, frameSize);

    if (peaks.isEmpty) return null;

    // Sélection du meilleur pic
    final bestPeak = _selectBestPeak(peaks, nsdf);

    if (bestPeak == null) return null;

    // Interpolation parabolique pour affiner
    final precisePeriod = _parabolicInterpolation(nsdf, bestPeak);

    // Calcul fréquence et confiance
    final frequency = sampleRate / precisePeriod;
    final confidence = nsdf[bestPeak];

    // Validation
    if (frequency < minF0 || frequency > maxF0) return null;
    if (confidence < clarityThreshold) return null;

    return (frequency: frequency, confidence: confidence);
  }

  /// Calcule la NSDF via FFT (plus efficace que calcul direct)
  Float64List _computeNSDF(Float64List frame, int frameSize) {
    // Préparer les données pour FFT
    final complexInput = Float64x2List(_fftSize);

    // Copier le frame (zero-padding automatique)
    for (int i = 0; i < frameSize; i++) {
      complexInput[i] = Float64x2(frame[i], 0.0);
    }

    // FFT du signal
    _fft.inPlaceFft(complexInput);

    // Calcul de l'autocorrélation via FFT
    // R(τ) = IFFT(|FFT(x)|²)
    for (int i = 0; i < _fftSize; i++) {
      final real = complexInput[i].x;
      final imag = complexInput[i].y;
      final magnitude2 = real * real + imag * imag;
      complexInput[i] = Float64x2(magnitude2, 0.0);
    }

    // IFFT pour obtenir l'autocorrélation
    _fft.inPlaceInverseFft(complexInput);

    // Extraire la partie réelle de l'autocorrélation
    final autocorr = Float64List(frameSize);
    for (int i = 0; i < frameSize; i++) {
      autocorr[i] = complexInput[i].x / _fftSize; // Normalisation FFT
    }

    // Calcul de la NSDF normalisée
    return _normalizeToNSDF(autocorr, frame, frameSize);
  }

  /// Normalise l'autocorrélation en NSDF
  Float64List _normalizeToNSDF(
      Float64List autocorr, Float64List frame, int frameSize) {
    final nsdf = Float64List(frameSize);

    // Calcul de m'(τ) = r'(τ) / sqrt(r'(0) * r'(τ))
    // où r'(τ) est l'autocorrélation

    final r0 = autocorr[0]; // r'(0)

    for (int tau = 0; tau < frameSize; tau++) {
      // Calcul de la somme des carrés pour la fenêtre décalée
      double sumSquares = 0.0;
      for (int i = 0; i < frameSize - tau; i++) {
        sumSquares += frame[i + tau] * frame[i + tau];
      }

      final denominator = math.sqrt(r0 * sumSquares);

      if (denominator > 1e-10) {
        nsdf[tau] = autocorr[tau] / denominator;
      } else {
        nsdf[tau] = 0.0;
      }
    }

    return nsdf;
  }

  /// Trouve les pics dans la NSDF
  List<int> _findPeaks(Float64List nsdf, int frameSize) {
    final peaks = <int>[];

    // Commencer après la période minimum
    for (int i = _minPeriod; i < math.min(frameSize - 1, _maxPeriod); i++) {
      // Vérifier si c'est un pic local
      if (nsdf[i] > nsdf[i - 1] && nsdf[i] > nsdf[i + 1] && nsdf[i] > 0.0) {
        // Seulement les pics positifs
        peaks.add(i);
      }
    }

    // Trier par amplitude décroissante
    peaks.sort((a, b) => nsdf[b].compareTo(nsdf[a]));

    return peaks;
  }

  /// Sélectionne le meilleur pic selon les critères MPM
  int? _selectBestPeak(List<int> peaks, Float64List nsdf) {
    if (peaks.isEmpty) return null;

    // Le premier pic (plus haute amplitude) est souvent le meilleur
    final firstPeak = peaks[0];

    // Vérifier que l'amplitude est suffisante
    if (nsdf[firstPeak] >= clarityThreshold) {
      return firstPeak;
    }

    // Si le premier pic n'est pas assez fort, chercher des harmoniques
    for (final peak in peaks) {
      if (nsdf[peak] >= clarityThreshold * 0.8) {
        // Vérifier que ce n'est pas une sous-harmonique du premier
        final ratio = firstPeak.toDouble() / peak.toDouble();
        if (ratio > 0.8 && ratio < 1.25) {
          return peak;
        }
      }
    }

    return null;
  }

  /// Interpolation parabolique pour affiner l'estimation de période
  double _parabolicInterpolation(Float64List nsdf, int peakIndex) {
    if (peakIndex == 0 || peakIndex >= nsdf.length - 1) {
      return peakIndex.toDouble();
    }

    final double y1 = nsdf[peakIndex - 1];
    final double y2 = nsdf[peakIndex];
    final double y3 = nsdf[peakIndex + 1];

    final double a = (y1 - 2 * y2 + y3) / 2;
    final double b = (y3 - y1) / 2;

    if (a.abs() < 1e-10) return peakIndex.toDouble();

    final double xVertex = -b / (2 * a);

    // Limiter la correction
    final double correction = math.max(-1.0, math.min(1.0, xVertex));

    return peakIndex + correction;
  }

  /// Trouve la prochaine puissance de 2
  int _nextPowerOfTwo(int n) {
    int power = 1;
    while (power < n) {
      power *= 2;
    }
    return power;
  }

  /// Informations de debug
  Map<String, dynamic> getDebugInfo() {
    return {
      'algorithm': 'MPM',
      'sampleRate': sampleRate,
      'minF0': minF0,
      'maxF0': maxF0,
      'minPeriod': _minPeriod,
      'maxPeriod': _maxPeriod,
      'clarityThreshold': clarityThreshold,
      'fftSize': _fftSize,
    };
  }
}