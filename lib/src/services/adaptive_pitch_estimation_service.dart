import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import '../models/pitch_estimate.dart';
import '../algorithms/yin_detector.dart';
import '../algorithms/mpm_detector.dart';
import 'amplitude_tracker.dart';
import 'harmonic_analyzer.dart';
import 'note_lock.dart';
import 'frequency_profiles.dart';

/// Version améliorée du service d'estimation avec adaptation automatique par fréquence
/// Résoud spécifiquement les problèmes de notes graves (G3, etc.) qui s'arrêtent après 1-2s
class AdaptivePitchEstimationService {
  final double sampleRate;
  final double minF0;
  final double maxF0;

  // Algorithmes de détection
  late final YinPitchDetector _yinDetector;
  late final MpmPitchDetector _mpmDetector;

  // Post-traitement
  final Queue<double> _frequencyHistory = Queue<double>();
  final Queue<PitchEstimate> _estimateHistory = Queue<PitchEstimate>();
  final int _historySize;
  final int _medianFilterSize;

  // Hystérésis pour stabilité d'affichage
  String? _lastDisplayedNote;
  final double _hysteresisThresholdCents;

  // Anti-octave
  double? _lastValidF0;
  final double _octaveToleranceRatio;

  // Seuil de silence adaptatif
  late final AmplitudeTracker _amp;

  // Analyse harmonique pour pondérer la confiance
  final HarmonicAnalyzer _harm = HarmonicAnalyzer();

  late final NoteLocker<_LiteEstimate> _locker;

  // Debounce du silence pour éviter l'arrêt trop tôt
  int _silentFrames = 0;

  // Lissage EMA pour fréquence et confiance
  final double _emaAlphaHigh;
  final double _emaAlphaLow;
  final double _emaConfidenceThreshold;
  final bool _disableEmaSmoothing;
  double? _emaF0;
  double? _emaConfidence;

  // Système adaptatif par fréquence - SOLUTION PRINCIPALE pour G3
  final bool _enableFrequencyAdaptation;
  FrequencyProfile? _currentProfile;

  // Détection d'étouffement/mute pour éviter le gel sur transitoires
  double? _lastAmplitude;
  double? _lastFrequency;
  bool _inMuteTransition = false;
  final double _muteDetectionSensitivity;

  // Préférence d'algorithme et garde anti-harmonique bande basse
  final double? _preferYinBelowHz; // favorise YIN pour basses fréquences
  final bool _antiHarmonicLowBandGuardEnabled; // garde extra en zone basse
  final double _antiHarmonicLowBandMaxHz; // borne supérieure de la zone basse

  // Stabilisation d'attaque pour réduire le sautillement initial
  DateTime? _firstDetectionTime;
  final List<double> _attackFrequencies = [];
  final int
      _attackStabilizationFrames; // Nombre de frames pour stabiliser l'attaque
  final int _attackTimeoutMs; // Durée (ms) pour considérer une nouvelle attaque

  // Optional callback to receive per-frame diagnostics
  final void Function(Map<String, dynamic>)? diagnosticsCallback;

  final bool debugDiagnostics;
  AdaptivePitchEstimationService({
    required this.sampleRate,
    this.minF0 = 70.0,
    this.maxF0 = 1000.0,
    // Paramètres de base
    int historySize = 5,
    int medianFilterSize = 3,
    double hysteresisThresholdCents = 5.0,
    double octaveToleranceRatio = 0.1,
    // AmplitudeTracker - valeurs par défaut (seront adaptées automatiquement)
    int ampHistorySize = 24,
    double ampMinThreshold = 0.001,
    // NoteLocker - valeurs par défaut (seront adaptées automatiquement)
    double lockCentsHysteresis = 4.0,
    double lockWeakerConfidenceRatio = 0.9,
    // EMA smoothing
    double emaAlphaHigh = 0.85,
    double emaAlphaLow = 0.30,
    double emaConfidenceThreshold = 0.7,
    bool disableEmaSmoothing = false,
    // Système adaptatif (SOLUTION RECOMMANDÉE)
    bool enableFrequencyAdaptation = true,
    // Nouvelle option: sensibilité anti-étouffement
    // 0.0 = désactivé, 0.5 = normal, 1.0 = très strict
    double muteDetectionSensitivity = 0.7,
    // Algorithme / Garde bas-de-gamme
    double? preferYinBelowHz = 120.0,
    bool antiHarmonicLowBandGuardEnabled = true,
    double antiHarmonicLowBandMaxHz = 120.0,
    // Attack stabilization tuning
    int attackStabilizationFrames = 4,
    int attackTimeoutMs = 200,
    void Function(Map<String, dynamic>)? diagnosticsCallback,
    bool debugDiagnostics = false,
  })  : _historySize = historySize,
        _medianFilterSize = medianFilterSize,
        _hysteresisThresholdCents = hysteresisThresholdCents,
        _octaveToleranceRatio = octaveToleranceRatio,
        _emaAlphaHigh = emaAlphaHigh,
        _emaAlphaLow = emaAlphaLow,
        _emaConfidenceThreshold = emaConfidenceThreshold,
        _disableEmaSmoothing = disableEmaSmoothing,
        _enableFrequencyAdaptation = enableFrequencyAdaptation,
        _muteDetectionSensitivity = muteDetectionSensitivity,
        _preferYinBelowHz = preferYinBelowHz,
        _antiHarmonicLowBandGuardEnabled = antiHarmonicLowBandGuardEnabled,
        _antiHarmonicLowBandMaxHz = antiHarmonicLowBandMaxHz,
        _attackStabilizationFrames = attackStabilizationFrames,
        _attackTimeoutMs = attackTimeoutMs,
        diagnosticsCallback = diagnosticsCallback,
        debugDiagnostics = debugDiagnostics {
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

    _amp = AmplitudeTracker(
      historySize: ampHistorySize,
      minThreshold: ampMinThreshold,
      ratioOfRecentMax: 0.10, // Sera adapté selon la fréquence
    );

    _locker = NoteLocker<_LiteEstimate>(
      centsHysteresis: lockCentsHysteresis,
      minConfidenceToLock: 0.75, // Sera adapté selon la fréquence
      holdMsAfterSilence: 400, // Sera adapté selon la fréquence
      weakerConfidenceRatio: lockWeakerConfidenceRatio,
    );
  }

  /// CŒUR DE LA SOLUTION : Estimation avec adaptation automatique
  PitchEstimate estimatePitch(Float64List audioFrame) {
    final now = DateTime.now();

    // 1. RMS de base
    final rms = _calculateRms(audioFrame);
    _amp.add(rms);

    // 2. Détection YIN/MPM pour obtenir une fréquence de référence
    final yinResult = _yinDetector.estimatePitch(audioFrame);
    final mpmResult = _mpmDetector.estimatePitch(audioFrame);
    final bestResult = _selectBestEstimate(yinResult, mpmResult);

    // 3. DÉTECTION D'ÉTOUFFEMENT - Solution pour éviter le gel sur transitoires
    final bool isMuteTransition =
        _detectMuteTransition(rms, bestResult?.frequency);

    // 4. ADAPTATION AUTOMATIQUE selon la fréquence détectée
    FrequencyProfile profile;
    if (isMuteTransition) {
      // Profil spécial pour gérer l'étouffement - plus strict et réactif
      profile = FrequencyProfileManager.getMuteTransitionProfile();
      _inMuteTransition = true;
    } else if (bestResult != null && _enableFrequencyAdaptation) {
      profile = FrequencyProfileManager.selectProfile(bestResult.frequency);
      _currentProfile = profile;
      _inMuteTransition = false;
    } else {
      // Mode traditionnel ou pas de détection
      profile = _currentProfile ??
          FrequencyProfileManager.createDefaultProfile(
            ampRatioOfRecentMax: 0.10,
            silentDebounceFrames: 3,
            minFloor: 0.0003,
            confHarmBase: 0.6,
            confHarmWeight: 0.4,
            confAmpBase: 0.5,
            confAmpWeight: 0.5,
            lockMinConfidenceToLock: 0.75,
            lockHoldMsAfterSilence: 400,
          );
      _inMuteTransition = false;
    }

    // Mettre à jour les valeurs pour la prochaine détection
    _lastAmplitude = rms;
    _lastFrequency = bestResult?.frequency;

    // 4. APPLICATION DES SEUILS ADAPTATIFS (solution G3)
    final adaptiveAmpRatio = profile.ampRatioOfRecentMax;
    final adaptiveSilenceThreshold = math.max(
      profile.minFloor,
      _amp.recentMax * adaptiveAmpRatio,
    );

    final bool isSilentStep = rms < adaptiveSilenceThreshold;
    _silentFrames = isSilentStep ? (_silentFrames + 1) : 0;

    // Plancher adaptatif selon la fréquence (crucial pour G3)
    final bool belowFloor = rms < profile.minFloor;
    final bool isSilent =
        belowFloor ? true : (_silentFrames >= profile.silentDebounceFrames);

    // 5. Gestion du silence avec profil adaptatif
    if (isSilent || bestResult == null) {
      final fallback = _locker.update(
        _LiteEstimate.fromSilence(now),
        isSilentNow: true,
      );
      if (fallback.locked && fallback.estimate.isVoiced) {
        final out = _toPitchEstimate(fallback.estimate, now, voiced: true);
        _updateHistory(out);
        return _applyDisplayHysteresis(out);
      }
      _clearHistory();
      return PitchEstimate.silence();
    }

    // 5.1 Protection renforcée: si on est en transition d'étouffement ET
    // que la nouvelle détection est très différente, forcer le silence
    if (isMuteTransition && _lastFrequency != null) {
      final freqRatio = bestResult.frequency / _lastFrequency!;
      final isVeryDifferent =
          freqRatio < 0.7 || freqRatio > 1.4; // Changement >30%

      if (isVeryDifferent && bestResult.confidence < 0.8) {
        // Forcer le silence plutôt que d'afficher une fausse note
        _clearHistory();
        return PitchEstimate.silence();
      }
    }

    // 6. Post-traitement des fréquences pour stabilité
    final stabilizedFrequency = _applyPostProcessing(bestResult.frequency);
    if (stabilizedFrequency == null) {
      _clearHistory();
      return PitchEstimate.silence();
    }

    // 6.1 STABILISATION D'ATTAQUE - réduction du sautillement initial
    final finalFrequency = _applyAttackStabilization(stabilizedFrequency, now);

    // 7. Pondération par harmonique + amplitude avec profil adaptatif
    final harm = finalFrequency > 0
        ? _harm.support(audioFrame, sampleRate, finalFrequency)
        : 0.0;
    final ampFactor = _amp.amplitudeFactor(rms);

    // CONFIDENCE ADAPTATIVE selon le profil (favorise les notes graves)
    final adjustedConfidence = (bestResult.confidence *
            (profile.confHarmBase + profile.confHarmWeight * harm)) *
        (profile.confAmpBase + profile.confAmpWeight * ampFactor);

    final refined = _LiteEstimate(
      f0Hz: finalFrequency,
      cents: _frequencyToCents(finalFrequency),
      confidence: adjustedConfidence.clamp(0.0, 1.0),
      isVoiced: true,
      note: _frequencyToNoteName(finalFrequency),
      algorithm: bestResult.algorithm,
    );

    // 8. Lissage EMA optionnel
    _LiteEstimate refinedSmoothed;
    if (_disableEmaSmoothing) {
      refinedSmoothed = refined;
      _emaF0 = null;
      _emaConfidence = null;
    } else {
      final alpha = (refined.confidence >= _emaConfidenceThreshold)
          ? _emaAlphaHigh
          : _emaAlphaLow;
      final smoothedF0 = (_emaF0 == null)
          ? refined.f0Hz!
          : (_emaF0! * (1 - alpha) + refined.f0Hz! * alpha);
      _emaF0 = smoothedF0;
      final smoothedConf = (_emaConfidence == null)
          ? refined.confidence
          : (_emaConfidence! * (1 - alpha) + refined.confidence * alpha);
      _emaConfidence = smoothedConf;
      refinedSmoothed = _LiteEstimate(
        f0Hz: smoothedF0,
        cents: _frequencyToCents(smoothedF0),
        confidence: smoothedConf,
        isVoiced: true,
        note: _frequencyToNoteName(smoothedF0),
        algorithm: refined.algorithm,
      );
    }

    // 9. Note locking avec paramètres adaptatifs
    final locked = _locker.update(refinedSmoothed, isSilentNow: isSilent);
    final outLite = locked.estimate;
    final out = _toPitchEstimate(outLite, now, voiced: true);

    // 10. Diagnostics optionnels (pour déboguer G3)
    if (this.debugDiagnostics && diagnosticsCallback != null) {
      try {
        diagnosticsCallback!({
          'timestamp': now.toIso8601String(),
          'note': outLite.note,
          'frequency': bestResult.frequency,
          'rms': rms,
          'profileName': profile.name,
          'adaptiveSilenceThreshold': adaptiveSilenceThreshold,
          'profileMinFloor': profile.minFloor,
          'profileAmpRatio': profile.ampRatioOfRecentMax,
          'profileDebounceFrames': profile.silentDebounceFrames,
          'silentFrames': _silentFrames,
          'recentMax': _amp.recentMax,
          'harmonicScore': harm,
          'ampFactor': ampFactor,
          'rawConfidence': bestResult.confidence,
          'adjustedConfidence': adjustedConfidence,
          'locked': locked.locked,
          'emaF0': _emaF0,
          'emaConfidence': _emaConfidence,
          'inMuteTransition': _inMuteTransition,
          'lastAmplitude': _lastAmplitude,
          'lastFrequency': _lastFrequency,
          'ratioToLast': _lastFrequency != null
              ? (bestResult.frequency / _lastFrequency!).toStringAsFixed(3)
              : null,
          'activeProfile': _currentProfile?.name,
        });
      } catch (_) {}
    }
    _emitDiagnostics(now, rms, profile, adaptiveSilenceThreshold, bestResult,
        harm, ampFactor, adjustedConfidence, locked, outLite);

    // 11. Hystérésis d'affichage + historique
    final finalEstimate = _applyDisplayHysteresis(out);
    _updateHistory(finalEstimate);
    return finalEstimate;
  }

  /// Stabilise la fréquence pendant l'attaque pour réduire le sautillement
  /// Utilise une médiane des premières détections pour éviter l'instabilité
  double _applyAttackStabilization(double frequency, DateTime now) {
    // Détecter le début d'une nouvelle attaque (pas de détection récente)
    final isNewAttack = _firstDetectionTime == null ||
        now.difference(_firstDetectionTime!).inMilliseconds > _attackTimeoutMs;

    if (isNewAttack) {
      // Nouvelle attaque détectée - réinitialiser
      _firstDetectionTime = now;
      _attackFrequencies.clear();
    }

    // Ajouter la fréquence actuelle à l'historique d'attaque
    _attackFrequencies.add(frequency);

    // Pendant la phase de stabilisation (premières frames)
    if (_attackFrequencies.length <= _attackStabilizationFrames) {
      // Utiliser la médiane des fréquences d'attaque pour plus de stabilité
      final sortedFreqs = List<double>.from(_attackFrequencies)..sort();
      final median = sortedFreqs[sortedFreqs.length ~/ 2];

      // Filtrer les valeurs aberrantes (>12% de différence avec la médiane)
      final deviationRatio = (frequency - median).abs() / median;
      if (deviationRatio > 0.12) {
        // Valeur aberrante - utiliser la médiane à la place
        return median;
      }
    }

    // Nettoyer l'historique d'attaque si trop ancien
    if (_attackFrequencies.length > _attackStabilizationFrames * 2) {
      _attackFrequencies.removeRange(
          0, _attackFrequencies.length - _attackStabilizationFrames);
    }

    return frequency;
  }

  /// Détecte si on est dans une phase d'étouffement de corde (doigt qui stoppe)
  /// Critères améliorés pour éviter les faux positifs harmoniques
  bool _detectMuteTransition(double currentRms, double? currentFreq) {
    if (_lastAmplitude == null || _lastFrequency == null) {
      return false; // Pas assez d'historique
    }

    // 1. Détection de chute d'amplitude rapide - sensibilité configurable
    final amplitudeDropRatio = currentRms / _lastAmplitude!;
    final dropThreshold =
        0.6 - (_muteDetectionSensitivity * 0.3); // 0.6 à 0.3 selon sensibilité
    final hasAmplitudeDrop = amplitudeDropRatio < dropThreshold;

    // 2. Détection de saut de fréquence important (plus strict pour éviter harmoniques)
    bool hasFrequencyJump = false;
    if (currentFreq != null && _lastFrequency != null) {
      final freqRatio = (currentFreq / _lastFrequency!);
      // Plus strict: éviter les rapports harmoniques courants (1.25, 1.33, 1.5, 2.0)
      hasFrequencyJump = freqRatio < 0.4 ||
          freqRatio > 2.5 ||
          (freqRatio > 1.15 && freqRatio < 1.35) || // Zone harmonique suspecte
          (freqRatio > 1.45 && freqRatio < 1.55); // Zone harmonique suspecte
    }

    // 3. Détection de confidence suspecte (nouveau critère)
    bool hasLowConfidence = false;
    if (currentFreq != null) {
      // Si on est dans le service, on peut accéder à la confidence via bestResult
      // Pour l'instant, on utilise un proxy basé sur la cohérence fréquentielle
      final midiFloat = 69 + 12 * (math.log(currentFreq / 440.0) / math.log(2));
      final centsFromNote = ((midiFloat - midiFloat.round()) * 100).abs();
      hasLowConfidence =
          centsFromNote > 35; // Plus strict: 35 cents au lieu de 45
    }

    // 4. Nouveau critère: amplitude très faible (transitoire résiduel)
    final isVeryQuiet = currentRms < 0.002; // Plus strict que 0.001

    // 5. Nouveau critère: changement de zone de fréquence suspect
    bool hasSuspiciousZoneChange = false;
    if (currentFreq != null && _lastFrequency != null) {
      // Détecter si on change de "zone musicale" de façon suspecte
      final lastNote = _frequencyToNoteName(_lastFrequency!);
      final currentNote = _frequencyToNoteName(currentFreq);

      // Si changement de note avec chute d'amplitude = suspect
      hasSuspiciousZoneChange = (lastNote != currentNote) && hasAmplitudeDrop;
    }

    // DÉCISION AMÉLIORÉE: c'est un transitoire d'étouffement si:
    // - (Chute d'amplitude modérée ET changement de note) OU
    // - (Chute d'amplitude forte ET saut de fréquence) OU
    // - (Très faible amplitude avec mauvaise justesse) OU
    // - (Changement de zone suspect)
    final isMuteTransition = (hasAmplitudeDrop && hasSuspiciousZoneChange) ||
        (amplitudeDropRatio < 0.25 && hasFrequencyJump) || // Chute très forte
        (isVeryQuiet && hasLowConfidence) ||
        (hasAmplitudeDrop && hasLowConfidence && hasFrequencyJump);

    return isMuteTransition;
  }

  /// Émission optionnelle de diagnostics pour déboguer des notes spécifiques
  void _emitDiagnostics(
      DateTime now,
      double rms,
      FrequencyProfile profile,
      double adaptiveSilenceThreshold,
      ({double frequency, double confidence, String algorithm}) bestResult,
      double harm,
      double ampFactor,
      double adjustedConfidence,
      NoteLockResult<_LiteEstimate> locked,
      _LiteEstimate outLite) {
    if (diagnosticsCallback != null) {
      try {
        // Émet pour toutes les notes ou filtrer sur une note spécifique
        final shouldEmit = outLite.note.startsWith('G3') ||
            outLite.note.startsWith('E2') ||
            outLite.note.startsWith('A2') ||
            outLite.note.startsWith('D3'); // Notes problématiques

        if (shouldEmit) {
          final diag = <String, dynamic>{
            'timestamp': now.toIso8601String(),
            'note': outLite.note,
            'frequency': bestResult.frequency,
            'rms': rms,
            'profileName': profile.name,
            'adaptiveSilenceThreshold': adaptiveSilenceThreshold,
            'profileMinFloor': profile.minFloor,
            'profileAmpRatio': profile.ampRatioOfRecentMax,
            'profileDebounceFrames': profile.silentDebounceFrames,
            'silentFrames': _silentFrames,
            'recentMax': _amp.recentMax,
            'harmonicScore': harm,
            'ampFactor': ampFactor,
            'rawConfidence': bestResult.confidence,
            'adjustedConfidence': adjustedConfidence,
            'locked': locked.locked,
            'emaF0': _emaF0,
            'emaConfidence': _emaConfidence,
            // Nouvelles informations de détection d'étouffement
            'inMuteTransition': _inMuteTransition,
            'lastAmplitude': _lastAmplitude,
            'lastFrequency': _lastFrequency,
          };
          diagnosticsCallback!(diag);
        }
      } catch (e) {
        // Keep diagnostics non-fatal
      }
    }
  }

  /// Détecte le silence basé sur RMS
  double _calculateRms(Float64List frame) {
    double sumSquares = 0.0;
    for (int i = 0; i < frame.length; i++) {
      sumSquares += frame[i] * frame[i];
    }
    return math.sqrt(sumSquares / frame.length);
  }

  /// Sélectionne le meilleur résultat entre YIN et MPM
  ({double frequency, double confidence, String algorithm})?
      _selectBestEstimate(
    ({double frequency, double confidence})? yinResult,
    ({double frequency, double confidence})? mpmResult,
  ) {
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

    final yinConf = yinResult.confidence;
    final mpmConf = mpmResult.confidence;
    final freqRatio = yinResult.frequency / mpmResult.frequency;

    if (freqRatio > 0.95 && freqRatio < 1.05) {
      // Préférence YIN en bande basse quand confiance comparable
      if (_preferYinBelowHz != null &&
          (yinResult.frequency < _preferYinBelowHz! ||
              mpmResult.frequency < _preferYinBelowHz!)) {
        if (yinConf >= mpmConf * 0.9) {
          return (
            frequency: yinResult.frequency,
            confidence: yinConf,
            algorithm: 'YIN'
          );
        }
      }
      return yinConf > mpmConf
          ? (
              frequency: yinResult.frequency,
              confidence: yinConf,
              algorithm: 'YIN'
            )
          : (
              frequency: mpmResult.frequency,
              confidence: mpmConf,
              algorithm: 'MPM'
            );
    }

    // Si bande basse, favoriser YIN si la confiance est proche
    if (_preferYinBelowHz != null &&
        (yinResult.frequency < _preferYinBelowHz! ||
            mpmResult.frequency < _preferYinBelowHz!)) {
      if (yinConf >= mpmConf * 0.9) {
        return (
          frequency: yinResult.frequency,
          confidence: yinConf,
          algorithm: 'YIN'
        );
      }
    }

    if (yinConf > mpmConf * 1.1) {
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
    _frequencyHistory.add(frequency);
    if (_frequencyHistory.length > _historySize) {
      _frequencyHistory.removeFirst();
    }

    if (_frequencyHistory.length >= _medianFilterSize) {
      final medianFreq = _calculateMedian(List.from(_frequencyHistory));
      final protectedFreq = _applyAntiOctaveProtection(medianFreq);

      if (_isOutlier(protectedFreq)) {
        return _lastValidF0;
      }

      _lastValidF0 = protectedFreq;
      return protectedFreq;
    }

    final protectedFreq = _applyAntiOctaveProtection(frequency);
    _lastValidF0 = protectedFreq;
    return protectedFreq;
  }

  double _calculateMedian(List<double> values) {
    values.sort();
    final middle = values.length ~/ 2;
    if (values.length % 2 == 0) {
      return (values[middle - 1] + values[middle]) / 2;
    } else {
      return values[middle];
    }
  }

  double _applyAntiOctaveProtection(double frequency) {
    if (_lastValidF0 == null) return frequency;
    final ratio = frequency / _lastValidF0!;

    // Protection octaves classiques (2x, 0.5x)
    if (_isNearRatio(ratio, 2.0, _octaveToleranceRatio)) {
      return _lastValidF0! * 2.0;
    } else if (_isNearRatio(ratio, 0.5, _octaveToleranceRatio)) {
      return _lastValidF0! * 0.5;
    }

    // NOUVEAU: Protection sous-harmoniques (problème E4→E2/A2)
    // Détection de chutes harmoniques suspectes quand amplitude baisse
    final currentRms = _lastAmplitude ?? 0.0;
    final isAmplitudeDeclining =
        _amp.recentMax > 0 && (currentRms / _amp.recentMax) < 0.7;

    if (isAmplitudeDeclining) {
      // Sous-harmoniques suspects: 1/3, 1/4, rapports non-musicaux
      if (_isNearRatio(ratio, 1.0 / 3.0,
              _octaveToleranceRatio * 1.5) || // 1/3 harmonique
          _isNearRatio(ratio, 1.0 / 4.0,
              _octaveToleranceRatio * 1.5) || // 1/4 harmonique
          _isNearRatio(ratio, 0.33, 0.12) || // E4→A2 (330→110)
          _isNearRatio(ratio, 0.25, 0.05) || // 1/4 harmonique strict
          (ratio < 0.38 && ratio > 0.18)) {
        // Zone sous-harmonique élargie

        // Garder la fréquence précédente au lieu d'accepter le sous-harmonique
        return _lastValidF0!;
      }
    }

    // Protection générale E4 → sous-harmoniques (même sans baisse d'amplitude)
    if (_isNearRatio(ratio, 0.33, 0.08) || // E4→A2 strict
        _isNearRatio(ratio, 0.25, 0.03)) {
      // 1/4 harmonique strict
      return _lastValidF0!;
    }

    // NOUVEAU: Si la fréquence candidate est dans la zone basse (E2..G2 ~= 82..100Hz)
    // et qu'on observe une baisse d'amplitude, bloquer les sauts vers des ratios
    // harmoniques proches (1.2-1.5) qui peuvent provenir d'harmoniques de la corde adjacente.
    if (_antiHarmonicLowBandGuardEnabled &&
        isAmplitudeDeclining &&
        _lastValidF0 != null) {
      final targetFreq = frequency;
      final lowBandMin = math.max(30.0, minF0);
      if (targetFreq > lowBandMin && targetFreq < _antiHarmonicLowBandMaxHz) {
        final r = frequency / _lastValidF0!;
        if ((r > 1.15 && r < 1.35) || (r > 1.45 && r < 1.55)) {
          // Bloquer ce saut suspect et conserver la dernière fréquence stable
          return _lastValidF0!;
        }
      }
    }

    return frequency;
  }

  bool _isNearRatio(double ratio, double target, double tolerance) {
    return (ratio - target).abs() / target < tolerance;
  }

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
    if (stdDev < 1.0) return false;
    final zScore = (frequency - mean).abs() / stdDev;
    return zScore > 2.0;
  }

  PitchEstimate _applyDisplayHysteresis(PitchEstimate estimate) {
    if (!estimate.isVoiced || estimate.note == null) {
      _lastDisplayedNote = null;
      return estimate;
    }

    if (_lastDisplayedNote == null || _lastDisplayedNote != estimate.note) {
      if (_lastDisplayedNote != null) {
        if (estimate.cents!.abs() < _hysteresisThresholdCents) {
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

  void _updateHistory(PitchEstimate estimate) {
    _estimateHistory.add(estimate);
    if (_estimateHistory.length > _historySize) {
      _estimateHistory.removeFirst();
    }
  }

  void _clearHistory() {
    _frequencyHistory.clear();
    _estimateHistory.clear();
    _lastDisplayedNote = null;
    _lastValidF0 = null;
    _locker.clear();
    _emaF0 = null;
    _emaConfidence = null;
    // Réinitialiser aussi l'état de détection d'étouffement
    _lastAmplitude = null;
    _lastFrequency = null;
    _inMuteTransition = false;
  }

  // Aides internes pour cent/note
  double _frequencyToCents(double frequency) {
    final midiFloat = 69 + 12 * (math.log(frequency / 440.0) / math.log(2));
    final midiNote = midiFloat.round();
    final cents = (midiFloat - midiNote) * 100;
    return cents;
  }

  String _frequencyToNoteName(double frequency) {
    const noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B'
    ];
    final midiFloat = 69 + 12 * (math.log(frequency / 440.0) / math.log(2));
    final midiNote = midiFloat.round();
    final octave = (midiNote / 12).floor() - 1;
    final noteIndex = midiNote % 12;
    return '${noteNames[noteIndex]}$octave';
  }

  PitchEstimate _toPitchEstimate(_LiteEstimate e, DateTime ts,
      {required bool voiced}) {
    return PitchEstimate(
      timestamp: ts,
      f0Hz: e.f0Hz,
      note: e.note,
      cents: e.cents,
      confidence: e.confidence,
      isVoiced: voiced,
      algorithm: e.algorithm ?? 'AUTO',
    );
  }

  /// Obtient le profil actuellement actif (pour débogage)
  FrequencyProfile? get currentProfile => _currentProfile;

  /// Informations sur le profil actuel
  String getProfileInfo() {
    if (_currentProfile == null) return 'Aucun profil actif';
    return FrequencyProfileManager.getProfileInfo(
        _currentProfile!.minFreq + 10);
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
      'activeProfile': _currentProfile?.name ?? 'DEFAULT',
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

  void reset() {
    _clearHistory();
  }
}

// Adaptateur interne pour le NoteLocker
class _LiteEstimate implements PitchLite {
  @override
  final double? f0Hz;
  @override
  final double cents;
  @override
  final double confidence;
  @override
  final bool isVoiced;
  @override
  final String note;
  final String? algorithm;

  _LiteEstimate({
    required this.f0Hz,
    required this.cents,
    required this.confidence,
    required this.isVoiced,
    required this.note,
    this.algorithm,
  });

  factory _LiteEstimate.fromSilence(DateTime ts) => _LiteEstimate(
        f0Hz: null,
        cents: 0,
        confidence: 0.0,
        isVoiced: false,
        note: '',
      );

  @override
  _LiteEstimate copyWith({double? f0Hz, double? confidence, bool? isVoiced}) {
    return _LiteEstimate(
      f0Hz: f0Hz ?? this.f0Hz,
      cents: cents,
      confidence: confidence ?? this.confidence,
      isVoiced: isVoiced ?? this.isVoiced,
      note: note,
      algorithm: algorithm,
    );
  }
}
