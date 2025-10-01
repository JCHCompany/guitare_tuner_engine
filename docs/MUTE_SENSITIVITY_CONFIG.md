# Configuration Anti-Étouffement Avancée

## Problème résolu

Le passage **E2 -2c → G#2 -25c** lors de l'étouffement est maintenant géré par :

1. **Détection améliorée** des transitoires harmoniques
2. **Profil MUTE_TRANSITION renforcé** (quasi-impossible à verrouiller)
3. **Protection contre changements suspects** (force le silence)
4. **Sensibilité configurable** pour s'adapter à différents instruments

## Configuration recommandée

### Pour guitare classique/folk (sensibilité normale)
```dart
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true,
  
  // Sensibilité anti-étouffement normale (défaut)
  muteDetectionSensitivity: 0.7, // 0.0 à 1.0
);

// Tuning additionnel pour réduire les sauts lors de changements rapides de corde
// Utilisez ces paramètres depuis votre app si vous observez ~200-300ms de saut
final serviceWithAttackTuning = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true,
  muteDetectionSensitivity: 0.7,
  // Réduire le nombre de frames pour stabiliser l'attaque → plus réactif
  attackStabilizationFrames: 3,
  // Timeout pour détecter une nouvelle attaque (ms). Réduisez pour changements rapides.
  attackTimeoutMs: 150,
);

// Diagnostics prêts à coller dans l'app pour capturer les données pendant le test E2
final diagService = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true,
  diagnosticsCallback: (data) {
    // Collez ces logs dans vos tests afin de partager un enregistrement précis
    print('DIAG ${data['timestamp']} note=${data['note']} freq=${data['frequency']} rms=${data['rms']}');
    print('   profile=${data['profileName']} inMute=${data['inMuteTransition']} lastFreq=${data['lastFrequency']} lastAmp=${data['lastAmplitude']}');
  },
);
```

### Pour guitare électrique (plus sensible aux transitoires)
```dart
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true,
  
  // Plus strict pour éviter les transitoires d'ampli/effets
  muteDetectionSensitivity: 0.9,
);
```

### Pour basse/contrebasse (moins sensible)
```dart
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true,
  
  // Moins strict pour les harmoniques naturelles des graves
  muteDetectionSensitivity: 0.4,
);
```

### Pour instruments à vent/voix (désactivé)
```dart
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true,
  
  // Pas d'étouffement sur ces instruments
  muteDetectionSensitivity: 0.0, // Désactivé
);
```

## Comportement selon la sensibilité

| Sensibilité | Seuil Amplitude | Comportement | Usage |
|-------------|----------------|--------------|--------|
| 0.0 | Désactivé | Pas de détection d'étouffement | Instruments à vent, voix |
| 0.3 | 51% baisse | Très tolérant aux transitoires | Basse, contrebasse |
| 0.5 | 45% baisse | Équilibré | Usage général |
| 0.7 | 39% baisse | **Recommandé guitare** | Guitare acoustique/classique |
| 0.9 | 33% baisse | Très strict | Guitare électrique, studio |
| 1.0 | 30% baisse | Maximum | Environnement très bruité |

## Diagnostics pour ajuster

```dart
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true,
  muteDetectionSensitivity: 0.7, // Ajustez selon vos tests
  
  diagnosticsCallback: (data) {
    // Observer les transitions d'étouffement
    if (data['inMuteTransition'] == true) {
      print('🛑 ÉTOUFFEMENT: ${data["lastFrequency"]?.toStringAsFixed(1)} Hz → ${data["frequency"]?.toStringAsFixed(1)} Hz');
      print('   Amplitude: ${data["lastAmplitude"]?.toStringAsFixed(6)} → ${data["rms"]?.toStringAsFixed(6)}');
      print('   Note: ${data["note"]} (${data["rawConfidence"]?.toStringAsFixed(2)} conf)');
      
      // Si vous voyez encore des fausses notes, augmentez la sensibilité
      // Si vous perdez des vraies notes, diminuez la sensibilité
    }
  },
);
```

## Améliorations implémentées

### 1. Critères de détection renforcés
- **Chute amplitude** : Configurable 30-60% selon sensibilité
- **Saut fréquence** : Évite zones harmoniques suspectes (1.15-1.35x, 1.45-1.55x)
- **Confidence faible** : <35 cents d'une note musicale
- **Changement de note** : Détecte les sauts E2→G#2, etc.

### 2. Profil MUTE_TRANSITION ultra-strict
```dart
// Nouveau profil renforcé
ampRatioOfRecentMax: 0.30,     // vs 0.20 (plus strict)
minFloor: 0.003,               // vs 0.001 (rejette mieux les transitoires)
lockMinConfidenceToLock: 0.95, // vs 0.9 (quasi-impossible)
lockHoldMsAfterSilence: 25,    // vs 50ms (encore moins longtemps)
```

### 3. Protection contre changements suspects
```dart
// Si transition d'étouffement + changement >30% + faible confidence
// → Force le silence au lieu d'afficher la fausse note
if (isMuteTransition && freqChange > 30% && confidence < 0.8) {
  return PitchEstimate.silence();
}
```

## Test de validation

1. **Jouez E2** et maintenez 2-3 secondes ✅
2. **Étouffez rapidement** avec le doigt
3. **Vérifiez** : doit passer directement en silence (pas de G#2 -25c) ✅
4. **Jouez une nouvelle note** → doit s'afficher normalement ✅

### Si vous voyez encore des fausses notes :
```dart
// Augmentez la sensibilité
muteDetectionSensitivity: 0.9, // Plus strict
```

### Si vous perdez des vraies notes :
```dart
// Diminuez la sensibilité  
muteDetectionSensitivity: 0.5, // Plus tolérant
```

## Résumé

**Le package gère maintenant complètement le problème d'étouffement** avec :
- ✅ **Détection E2→G#2 évitée** (critères renforcés)
- ✅ **Passage direct au silence** (pas de gel sur transitoires)
- ✅ **Sensibilité configurable** (s'adapte aux instruments)
- ✅ **Diagnostics complets** (pour ajustement fin)

**Usage simple :** Utilisez `muteDetectionSensitivity: 0.7` pour guitare standard, et ajustez selon vos tests.