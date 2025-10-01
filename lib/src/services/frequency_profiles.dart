/// Profils adaptatifs de paramètres selon les zones de fréquence
/// Permet d'optimiser la détection pour différents types de notes (graves, aiguës, etc.)

/// Configuration de paramètres adaptatifs selon la fréquence détectée
class FrequencyProfile {
  final String name;
  final double minFreq;
  final double maxFreq;

  // Paramètres de seuil de silence
  final double ampRatioOfRecentMax;
  final int silentDebounceFrames;
  final double minFloor;

  // Paramètres de pondération de confidence
  final double confHarmBase;
  final double confHarmWeight;
  final double confAmpBase;
  final double confAmpWeight;

  // Paramètres de verrouillage de note
  final double lockMinConfidenceToLock;
  final int lockHoldMsAfterSilence;

  const FrequencyProfile({
    required this.name,
    required this.minFreq,
    required this.maxFreq,
    required this.ampRatioOfRecentMax,
    required this.silentDebounceFrames,
    required this.minFloor,
    required this.confHarmBase,
    required this.confHarmWeight,
    required this.confAmpBase,
    required this.confAmpWeight,
    required this.lockMinConfidenceToLock,
    required this.lockHoldMsAfterSilence,
  });
}

/// Gestionnaire des profils de fréquence pour adaptation automatique
class FrequencyProfileManager {
  static const List<FrequencyProfile> profiles = [
    // Zone basses (80-250 Hz) - Notes E2, A2, D3, G3, B3
    // Problème : amplitude faible, decay lent, harmoniques faibles
    // Solution : très permissif, tient longtemps
    FrequencyProfile(
      name: 'BASS',
      minFreq: 80.0,
      maxFreq: 250.0,
      ampRatioOfRecentMax: 0.03, // 3% du max récent (très permissif)
      silentDebounceFrames: 12, // 12 frames avant silence (très patient)
      minFloor: 0.00005, // Plancher très bas
      confHarmBase: 0.8, // Base haute (moins de pénalisation harmonique)
      confHarmWeight: 0.2, // Poids faible pour harmoniques
      confAmpBase: 0.7, // Base haute (moins de pénalisation amplitude)
      confAmpWeight: 0.3, // Poids faible pour amplitude
      lockMinConfidenceToLock: 0.5, // Plus facile à verrouiller
      lockHoldMsAfterSilence: 1200, // Tient 1.2s après silence
    ),

    // Zone médium-grave (250-400 Hz) - Notes C4, D4, E4, F4
    // Problème : transition grave/aigu, sensibilité contextuelle
    // Solution : modérément permissif
    FrequencyProfile(
      name: 'MID_LOW',
      minFreq: 250.0,
      maxFreq: 400.0,
      ampRatioOfRecentMax: 0.06, // 6% du max récent
      silentDebounceFrames: 8, // 8 frames avant silence
      minFloor: 0.0001, // Plancher bas
      confHarmBase: 0.7,
      confHarmWeight: 0.3,
      confAmpBase: 0.6,
      confAmpWeight: 0.4,
      lockMinConfidenceToLock: 0.65,
      lockHoldMsAfterSilence: 800, // Tient 0.8s après silence
    ),

    // Zone médium (400-650 Hz) - Notes G4, A4, B4, C5
    // Comportement équilibré, paramètres standards
    FrequencyProfile(
      name: 'MID',
      minFreq: 400.0,
      maxFreq: 650.0,
      ampRatioOfRecentMax: 0.08, // 8% du max récent
      silentDebounceFrames: 5, // 5 frames avant silence
      minFloor: 0.0002, // Plancher modéré
      confHarmBase: 0.6, // Paramètres équilibrés
      confHarmWeight: 0.4,
      confAmpBase: 0.5,
      confAmpWeight: 0.5,
      lockMinConfidenceToLock: 0.7,
      lockHoldMsAfterSilence: 500, // Tient 0.5s après silence
    ),

    // Zone aiguë (650-1200 Hz) - Notes D5, E5, F5, G5+
    // Problème : amplitude forte mais decay rapide, harmoniques complexes
    // Solution : plus strict mais réactif
    FrequencyProfile(
      name: 'HIGH',
      minFreq: 650.0,
      maxFreq: 1200.0,
      ampRatioOfRecentMax: 0.12, // 12% du max récent (plus strict)
      silentDebounceFrames: 3, // 3 frames avant silence (plus réactif)
      minFloor: 0.0003, // Plancher plus élevé
      confHarmBase: 0.5, // Base plus basse (plus de pondération)
      confHarmWeight: 0.5, // Poids fort pour harmoniques
      confAmpBase: 0.4, // Base plus basse
      confAmpWeight: 0.6, // Poids fort pour amplitude
      lockMinConfidenceToLock: 0.75, // Plus difficile à verrouiller
      lockHoldMsAfterSilence: 300, // Tient 0.3s après silence
    ),
  ];

  /// Sélectionne le profil approprié pour une fréquence donnée
  static FrequencyProfile selectProfile(double frequency) {
    for (final profile in profiles) {
      if (frequency >= profile.minFreq && frequency < profile.maxFreq) {
        return profile;
      }
    }

    // Fallback pour les fréquences hors plage
    if (frequency < 250.0) {
      return profiles[0]; // BASS profile pour très basses fréquences
    } else {
      return profiles.last; // HIGH profile pour très hautes fréquences
    }
  }

  /// Profil spécial pour détecter et gérer les transitoires d'étouffement
  /// Version renforcée pour éviter les harmoniques parasites (E2→G#2, etc.)
  static FrequencyProfile getMuteTransitionProfile() {
    return const FrequencyProfile(
      name: 'MUTE_TRANSITION',
      minFreq: 0.0,
      maxFreq: 2000.0,
      ampRatioOfRecentMax: 0.30, // Plus strict: 30% vs 20% (rejette plus vite)
      silentDebounceFrames: 1, // Immédiat - zéro patience
      minFloor:
          0.003, // Plancher beaucoup plus élevé vs 0.001 (rejette transitoires faibles)
      confHarmBase: 0.1, // Très très strict sur harmoniques
      confHarmWeight: 0.9, // Harmoniques quasi-obligatoires
      confAmpBase: 0.1, // Très très strict sur amplitude
      confAmpWeight: 0.9, // Amplitude quasi-obligatoire
      lockMinConfidenceToLock: 0.95, // Quasi-impossible à verrouiller (vs 0.9)
      lockHoldMsAfterSilence: 25, // Tient encore moins longtemps (vs 50ms)
    );
  }

  /// Crée un profil par défaut (désactivation du système adaptatif)
  static FrequencyProfile createDefaultProfile({
    required double ampRatioOfRecentMax,
    required int silentDebounceFrames,
    required double minFloor,
    required double confHarmBase,
    required double confHarmWeight,
    required double confAmpBase,
    required double confAmpWeight,
    required double lockMinConfidenceToLock,
    required int lockHoldMsAfterSilence,
  }) {
    return FrequencyProfile(
      name: 'DEFAULT',
      minFreq: 0.0,
      maxFreq: 2000.0,
      ampRatioOfRecentMax: ampRatioOfRecentMax,
      silentDebounceFrames: silentDebounceFrames,
      minFloor: minFloor,
      confHarmBase: confHarmBase,
      confHarmWeight: confHarmWeight,
      confAmpBase: confAmpBase,
      confAmpWeight: confAmpWeight,
      lockMinConfidenceToLock: lockMinConfidenceToLock,
      lockHoldMsAfterSilence: lockHoldMsAfterSilence,
    );
  }

  /// Informations de débogage sur les profils
  static String getProfileInfo(double frequency) {
    final profile = selectProfile(frequency);
    return '''
Fréquence: ${frequency.toStringAsFixed(1)} Hz
Profil actif: ${profile.name}
Plage: ${profile.minFreq}-${profile.maxFreq} Hz
Seuil amplitude: ${(profile.ampRatioOfRecentMax * 100).toStringAsFixed(1)}%
Debounce silence: ${profile.silentDebounceFrames} frames
Plancher: ${profile.minFloor}
Confidence base H/A: ${profile.confHarmBase}/${profile.confAmpBase}
Verrouillage min: ${profile.lockMinConfidenceToLock}
Maintien silence: ${profile.lockHoldMsAfterSilence}ms
''';
  }
}
