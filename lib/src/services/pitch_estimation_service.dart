import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import '../models/pitch_estimate.dart';
import '../algorithms/yin_detector.dart';
import '../algorithms/mpm_detector.dart';

/// Service principal d'estimation de pitch avec post-traitement et stabilisation
class PitchEstimationService {
  final double sampleRate;
  final double minF0;
  final double maxF0;

  // Algorithmes de détection
  late final YinPitchDetector _yinDetector;
  late final MpmPitchDetector _mpmDetector;

  // Post-traitement
  final Queue<double> _frequencyHistory = Queue<double>();
  final Queue<PitchEstimate> _estimateHistory = Queue<PitchEstimate>();
  final int _historySize = 5;
  final int _medianFilterSize = 3;

  // Hystérésis pour stabilité d'affichage
  String? _lastDisplayedNote;
  final double _hysteresisThresholdCents = 5.0;

  // Anti-octave
  double? _lastValidF0;
  final double _octaveToleranceRatio = 0.1; // 10% de tolérance

  // Seuil de silence (RMS)
  final double _silenceThreshold = 0.001;

  PitchEstimationService({
    required this.sampleRate,
    this.minF0 = 70.0,
    this.maxF0 = 1000.0,
  }) {
    _yinDetector = YinPitchDetector(
      sampleRate: sampleRate,
      minF0: minF0,
      maxF0: maxF0,
    );

    _mpmDetector = MpmPitchDetector(
      sampleRate: sampleRate,
      minF0: minF0,
      maxF0: maxF0,
    );
  }

  /// Estime le pitch d'un frame audio avec post-traitement complet
  PitchEstimate estimatePitch(Float64List audioFrame) {
    // 1. Détection de silence
    if (_isSilence(audioFrame)) {
      _clearHistory();
      return PitchEstimate.silence();
    }

    // 2. Estimation avec les deux algorithmes
    final yinResult = _yinDetector.estimatePitch(audioFrame);
    final mpmResult = _mpmDetector.estimatePitch(audioFrame);

    // 3. Sélection du meilleur algorithme
    final bestResult = _selectBestEstimate(yinResult, mpmResult);

    if (bestResult == null) {
      return PitchEstimate.silence();
    }

    // 4. Post-traitement et stabilisation
    final stabilizedFrequency = _applyPostProcessing(bestResult.frequency);

    if (stabilizedFrequency == null) {
      return PitchEstimate.silence();
    }

    // 5. Créer l'estimation finale
    final estimate = PitchEstimate.voiced(
      f0Hz: stabilizedFrequency,
      confidence: bestResult.confidence,
      algorithm: bestResult.algorithm,
    );

    // 6. Appliquer l'hystérésis d'affichage
    final finalEstimate = _applyDisplayHysteresis(estimate);

    // 7. Sauvegarder dans l'historique
    _updateHistory(finalEstimate);

    return finalEstimate;
  }

  /// Détecte le silence basé sur RMS
  bool _isSilence(Float64List frame) {
    double sumSquares = 0.0;
    for (int i = 0; i < frame.length; i++) {
      sumSquares += frame[i] * frame[i];
    }

    final rms = math.sqrt(sumSquares / frame.length);
    return rms < _silenceThreshold;
  }

  /// Sélectionne le meilleur résultat entre YIN et MPM
  ({double frequency, double confidence, String algorithm})?
      _selectBestEstimate(
    ({double frequency, double confidence})? yinResult,
    ({double frequency, double confidence})? mpmResult,
  ) {
    // Si un seul algorithme a un résultat
    if (yinResult == null && mpmResult == null) return null;
    if (yinResult == null) {
      return (
        frequency: mpmResult!.frequency,
        confidence: mpmResult.confidence,
        algorithm: 'MPM'
      );
    }
    if (mpmResult == null) {
      return (
        frequency: yinResult.frequency,
        confidence: yinResult.confidence,
        algorithm: 'YIN'
      );
    }

    // Les deux ont un résultat : choisir selon confiance et cohérence
    final yinConf = yinResult.confidence;
    final mpmConf = mpmResult.confidence;

    // Si les fréquences sont similaires (< 5%), prendre la plus confiante
    final freqRatio = yinResult.frequency / mpmResult.frequency;
    if (freqRatio > 0.95 && freqRatio < 1.05) {
      if (yinConf > mpmConf) {
        return (
          frequency: yinResult.frequency,
          confidence: yinConf,
          algorithm: 'YIN'
        );
      } else {
        return (
          frequency: mpmResult.frequency,
          confidence: mpmConf,
          algorithm: 'MPM'
        );
      }
    }

    // Fréquences différentes : prendre celle avec la meilleure confiance
    if (yinConf > mpmConf * 1.1) {
      // Bonus de 10% pour YIN (généralement plus stable)
      return (
        frequency: yinResult.frequency,
        confidence: yinConf,
        algorithm: 'YIN'
      );
    } else {
      return (
        frequency: mpmResult.frequency,
        confidence: mpmConf,
        algorithm: 'MPM'
      );
    }
  }

  /// Applique le post-traitement : filtre médian, anti-octave, outliers
  double? _applyPostProcessing(double frequency) {
    // 1. Ajouter à l'historique des fréquences
    _frequencyHistory.add(frequency);
    if (_frequencyHistory.length > _historySize) {
      _frequencyHistory.removeFirst();
    }

    // 2. Filtre médian si on a assez d'historique
    if (_frequencyHistory.length >= _medianFilterSize) {
      final medianFreq = _calculateMedian(List.from(_frequencyHistory));

      // 3. Protection anti-octave
      final protectedFreq = _applyAntiOctaveProtection(medianFreq);

      // 4. Détection d'outliers (z-score simple)
      if (_isOutlier(protectedFreq)) {
        return _lastValidF0; // Conserver la dernière fréquence valide
      }

      _lastValidF0 = protectedFreq;
      return protectedFreq;
    }

    // Pas assez d'historique, utiliser la fréquence brute avec protection anti-octave
    final protectedFreq = _applyAntiOctaveProtection(frequency);
    _lastValidF0 = protectedFreq;
    return protectedFreq;
  }

  /// Calcule la médiane d'une liste
  double _calculateMedian(List<double> values) {
    values.sort();
    final middle = values.length ~/ 2;

    if (values.length % 2 == 0) {
      return (values[middle - 1] + values[middle]) / 2;
    } else {
      return values[middle];
    }
  }

  /// Protection contre les sauts d'octave
  double _applyAntiOctaveProtection(double frequency) {
    if (_lastValidF0 == null) return frequency;

    final ratio = frequency / _lastValidF0!;

    // Vérifier les ratios d'octave (2x, 0.5x)
    if (_isNearRatio(ratio, 2.0, _octaveToleranceRatio)) {
      // Saut d'octave vers le haut détecté
      return _lastValidF0! * 2.0; // Correction progressive
    } else if (_isNearRatio(ratio, 0.5, _octaveToleranceRatio)) {
      // Saut d'octave vers le bas détecté
      return _lastValidF0! * 0.5; // Correction progressive
    }

    return frequency;
  }

  /// Vérifie si un ratio est proche d'une valeur cible
  bool _isNearRatio(double ratio, double target, double tolerance) {
    return (ratio - target).abs() / target < tolerance;
  }

  /// Détecte les outliers avec z-score simple
  bool _isOutlier(double frequency) {
    if (_frequencyHistory.length < 3) return false;

    final values = List<double>.from(_frequencyHistory);
    final mean = values.reduce((a, b) => a + b) / values.length;

    double variance = 0.0;
    for (final val in values) {
      variance += (val - mean) * (val - mean);
    }
    variance /= values.length;

    final stdDev = math.sqrt(variance);

    if (stdDev < 1.0) return false; // Éviter division par zéro

    final zScore = (frequency - mean).abs() / stdDev;

    return zScore > 2.0; // Seuil z-score
  }

  /// Applique l'hystérésis d'affichage pour éviter le flicker
  PitchEstimate _applyDisplayHysteresis(PitchEstimate estimate) {
    if (!estimate.isVoiced || estimate.note == null) {
      _lastDisplayedNote = null;
      return estimate;
    }

    // Première détection ou note différente
    if (_lastDisplayedNote == null || _lastDisplayedNote != estimate.note) {
      // Vérifier si le changement est significatif (> seuil en cents)
      if (_lastDisplayedNote != null) {
        // Calculer l'écart entre l'ancienne et la nouvelle note
        // Si < seuil, garder l'ancienne note

        // Pour simplifier, on accepte le changement si l'écart est > 5 cents
        // (implémentation complète nécessiterait calcul de distance entre notes)
        if (estimate.cents!.abs() < _hysteresisThresholdCents) {
          // Créer une copie avec l'ancienne note mais la nouvelle fréquence
          return PitchEstimate.voiced(
            f0Hz: estimate.f0Hz!,
            confidence: estimate.confidence,
            algorithm: estimate.algorithm,
          );
        }
      }

      _lastDisplayedNote = estimate.note;
    }

    return estimate;
  }

  /// Met à jour l'historique des estimations
  void _updateHistory(PitchEstimate estimate) {
    _estimateHistory.add(estimate);
    if (_estimateHistory.length > _historySize) {
      _estimateHistory.removeFirst();
    }
  }

  /// Efface l'historique (silence détecté)
  void _clearHistory() {
    _frequencyHistory.clear();
    _estimateHistory.clear();
    _lastDisplayedNote = null;
    _lastValidF0 = null;
  }

  /// Statistiques de performance
  Map<String, dynamic> getPerformanceStats() {
    if (_estimateHistory.isEmpty) return {};

    final voicedEstimates = _estimateHistory.where((e) => e.isVoiced).toList();

    if (voicedEstimates.isEmpty) return {};

    final frequencies = voicedEstimates.map((e) => e.f0Hz!).toList();
    final confidences = voicedEstimates.map((e) => e.confidence).toList();

    return {
      'totalEstimates': _estimateHistory.length,
      'voicedEstimates': voicedEstimates.length,
      'avgFrequency': frequencies.reduce((a, b) => a + b) / frequencies.length,
      'avgConfidence': confidences.reduce((a, b) => a + b) / confidences.length,
      'frequencyStdDev': _calculateStdDev(frequencies),
      'lastNote': _lastDisplayedNote,
    };
  }

  double _calculateStdDev(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    double variance = 0.0;
    for (final val in values) {
      variance += (val - mean) * (val - mean);
    }
    return math.sqrt(variance / values.length);
  }

  /// Réinitialise le service
  void reset() {
    _clearHistory();
  }
}