/// Résultat d'un update de NoteLocker
class NoteLockResult<T> {
  final T estimate;
  final bool locked;
  NoteLockResult(this.estimate, this.locked);
}

/// Interface minimale pour être agnostique du modèle public
abstract class PitchLite {
  double? get f0Hz;
  double get cents; // écart en cents par rapport à la note la plus proche
  double get confidence; // [0..1]
  bool get isVoiced;
  String get note; // "E4" etc.
  PitchLite copyWith({
    double? f0Hz,
    double? confidence,
    bool? isVoiced,
  });
}

/// Verrou de note avec hystérésis et protection anti-octave
class NoteLocker<T extends PitchLite> {
  final double centsHysteresis; // ne pas changer si |Δcents| <=
  final double minConfidenceToLock;
  final int holdMsAfterSilence; // garder un court instant après silence
  final double weakerConfidenceRatio; // protection anti-octave

  T? _locked;
  DateTime? _lastStrongUpdate;

  NoteLocker({
    this.centsHysteresis = 5.0,
    this.minConfidenceToLock = 0.75,
    this.holdMsAfterSilence = 250,
    this.weakerConfidenceRatio = 0.9,
  });

  T? get locked => _locked;

  void clear() {
    _locked = null;
    _lastStrongUpdate = null;
  }

  /// newEst: estimation courante
  /// isSilentNow: silence selon seuil adaptatif
  NoteLockResult<T> update(T newEst, {required bool isSilentNow}) {
    final now = DateTime.now();

    if (!newEst.isVoiced) {
      if (_locked != null && _lastStrongUpdate != null) {
        final dt = now.difference(_lastStrongUpdate!).inMilliseconds;
        if (dt <= holdMsAfterSilence) {
          return NoteLockResult(_locked as T, true);
        }
      }
      return NoteLockResult(newEst, false);
    }

    if (_locked == null) {
      if (newEst.confidence >= minConfidenceToLock) {
        _locked = newEst;
        _lastStrongUpdate = now;
        return NoteLockResult(_locked as T, true);
      }
      return NoteLockResult(newEst, false);
    }

    // Hystérésis cents
    final deltaCents = (newEst.cents - _locked!.cents).abs();
    final isSmallChange = deltaCents <= centsHysteresis;

    // Protection anti-octave renforcée et anti-chute brutale
    final prevF0 = _locked!.f0Hz ?? 0.0;
    final newF0 = newEst.f0Hz ?? 0.0;
    final ratio = prevF0 > 0 ? (newF0 / prevF0) : 1.0;
    final isOctaveish =
        (ratio > 1.8 && ratio < 2.2) || (ratio > 0.45 && ratio < 0.55);
    final notClearlyStronger =
        newEst.confidence < _locked!.confidence * 1.2; // plus strict

    // Si octave ou demi-octave et pas clairement plus confiant, on garde l'ancienne
    if (isOctaveish && notClearlyStronger) {
      return NoteLockResult(_locked as T, true);
    }

    // Si la fréquence chute brutalement (>30%) et la confiance n'est pas meilleure, on ignore
    if (prevF0 > 0 &&
        newF0 < prevF0 * 0.7 &&
        newEst.confidence <= _locked!.confidence) {
      return NoteLockResult(_locked as T, true);
    }

    // Suivre une dérive intentionnelle légère: si petit changement et confiance très proche
    final nearConfidence = newEst.confidence >= _locked!.confidence * 0.95;
    final moderateChange = deltaCents >= (centsHysteresis * 0.75);
    if (isSmallChange && (nearConfidence || moderateChange)) {
      _locked = newEst;
      _lastStrongUpdate = now;
      return NoteLockResult(_locked as T, true);
    }

    if (isSmallChange && newEst.confidence < _locked!.confidence) {
      return NoteLockResult(_locked as T, true);
    }

    if (newEst.confidence >= minConfidenceToLock ||
        !isSmallChange ||
        newEst.confidence > _locked!.confidence) {
      _locked = newEst;
      _lastStrongUpdate = now;
      return NoteLockResult(_locked as T, true);
    }

    return NoteLockResult(_locked as T, true);
  }
}
