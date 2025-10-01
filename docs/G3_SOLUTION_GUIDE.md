# Solution pour le problème G3 et notes graves

## Problème identifié

La note G3 (~196 Hz) et autres notes graves (E2, A2, D3, B3) s'arrêtent après 1.5-2 secondes de sustain à cause de :

1. **Seuil de silence adaptatif trop agressif** (cause principale)
2. **Plancher de bruit fixe inadapté aux graves**  
3. **Pondération de confidence défavorable aux graves**
4. **Debounce de silence trop court**

## Solution implémentée

### Système adaptatif par zones de fréquence

Le système détecte automatiquement la fréquence et adapte les paramètres :

- **BASS (80-250 Hz)** : G3, E2, A2, D3, B3 - Très permissif
- **MID_LOW (250-400 Hz)** : C4, D4, E4, F4 - Modérément permissif  
- **MID (400-650 Hz)** : G4, A4, B4, C5 - Équilibré
- **HIGH (650-1200 Hz)** : D5, E5+ - Plus strict mais réactif

### Paramètres adaptatifs spécifiques pour BASS (solution G3)

```dart
// Zone BASS - Spécialement pour G3 et notes graves
FrequencyProfile(
  name: 'BASS',
  minFreq: 80.0,
  maxFreq: 250.0,
  
  // Seuil de silence très permissif (3% vs 10% par défaut)
  ampRatioOfRecentMax: 0.03,
  
  // Plancher très bas pour amplitude faible des graves  
  minFloor: 0.00005, // vs 0.0003 par défaut
  
  // Patience avant silence (12 vs 3 frames par défaut)
  silentDebounceFrames: 12,
  
  // Confidence favorable aux graves
  confHarmBase: 0.8,     // Base haute (moins de pénalisation)
  confHarmWeight: 0.2,   // Poids faible pour harmoniques
  confAmpBase: 0.7,      // Base haute  
  confAmpWeight: 0.3,    // Poids faible pour amplitude
  
  // Verrouillage facilité
  lockMinConfidenceToLock: 0.5,   // vs 0.75 par défaut
  lockHoldMsAfterSilence: 1200,   // Tient 1.2s vs 400ms
)
```

## Usage recommandé

### Option 1: Service adaptatif (RECOMMANDÉ)

```dart
import 'package:guitare_tuner_engine/src/services/adaptive_pitch_estimation_service.dart';

// Remplacer PitchEstimationService par AdaptivePitchEstimationService
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  
  // Le système adaptatif est activé par défaut
  enableFrequencyAdaptation: true, // SOLUTION G3
  
  // Autres paramètres optionnels
  disableEmaSmoothing: false, // true pour réactivité max
  
  // Callback optionnel pour diagnostics G3
  diagnosticsCallback: (Map<String, dynamic> data) {
    if (data['note'].toString().startsWith('G3')) {
      print('G3 Debug: ${data}');
    }
  },
);

// Usage identique
final estimate = service.estimatePitch(audioFrame);
```

### Option 2: Configuration manuelle du service existant

Si vous ne voulez pas changer de service, ajustez manuellement :

```dart
final service = PitchEstimationService(
  sampleRate: 44100,
  
  // Paramètres optimisés pour notes graves
  ampHistorySize: 48,              // Plus de contexte
  ampMinThreshold: 0.00005,        // Plancher très bas  
  ampRatioOfRecentMax: 0.03,       // 3% au lieu de 10%
  
  silentDebounceFrames: 12,        // 12 frames au lieu de 3
  
  lockMinConfidenceToLock: 0.5,    // Plus facile à verrouiller
  lockHoldMsAfterSilence: 1200,    // Tient plus longtemps
  
  disableEmaSmoothing: true,       // Réactivité maximum
  
  // Confidence moins pénalisante
  confHarmBase: 0.8,
  confHarmWeight: 0.2,
  confAmpBase: 0.7,
  confAmpWeight: 0.3,
);
```

## Tests de validation

### Test 1: G3 sustained 

```dart
void testG3Sustain() async {
  final service = AdaptivePitchEstimationService(
    sampleRate: 44100,
    enableFrequencyAdaptation: true,
    diagnosticsCallback: (data) => print('G3: ${data["note"]} - ${data["rms"]} - ${data["profileName"]}'),
  );
  
  // Simuler G3 sustained pendant 5 secondes
  // Vérifier que la fréquence reste affichée en continu
  
  for (int i = 0; i < 200; i++) { // ~5s à 40fps
    final estimate = service.estimatePitch(generateG3Frame());
    assert(estimate.isVoiced, 'G3 doit rester voiced à frame $i');
    assert(estimate.note?.startsWith('G3') == true);
    await Future.delayed(Duration(milliseconds: 25));
  }
  
  print('✅ Test G3 sustained - PASSED');
}
```

### Test 2: Transition entre zones

```dart
void testFrequencyTransitions() {
  final service = AdaptivePitchEstimationService(
    sampleRate: 44100,
    enableFrequencyAdaptation: true,
  );
  
  // Test E2 -> G3 -> C4 -> G4 -> C5
  final testFrequencies = [82.0, 196.0, 262.0, 392.0, 523.0];
  
  for (final freq in testFrequencies) {
    final frame = generateToneFrame(freq);
    final estimate = service.estimatePitch(frame);
    final profile = service.currentProfile;
    
    print('Freq: $freq Hz -> Profile: ${profile?.name}');
    assert(estimate.isVoiced);
  }
}
```

## Diagnostics G3

Pour déboguer G3 en temps réel :

```dart
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true,
  diagnosticsCallback: (Map<String, dynamic> data) {
    // Filtre sur G3 seulement
    if (data['note'].toString().startsWith('G3')) {
      final rms = data['rms'];
      final threshold = data['adaptiveSilenceThreshold'];
      final frames = data['silentFrames'];
      final profile = data['profileName'];
      
      print('G3 Debug:');
      print('  RMS: ${rms.toStringAsFixed(6)}');
      print('  Seuil: ${threshold.toStringAsFixed(6)}');
      print('  Silent frames: $frames');
      print('  Profile: $profile');
      print('  Status: ${rms > threshold ? "VOICED" : "SILENT"}');
      print('---');
    }
  },
);
```

## Migration depuis le service existant

### Changement minimal (drop-in replacement)

```dart
// Avant
final service = PitchEstimationService(sampleRate: 44100);

// Après (résout automatiquement G3)
final service = AdaptivePitchEstimationService(sampleRate: 44100);
```

### Optimisation complète

```dart
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  
  // Système adaptatif (solution G3)
  enableFrequencyAdaptation: true,
  
  // Réactivité maximale si nécessaire
  disableEmaSmoothing: true,
  
  // Diagnostics pour les notes problématiques
  diagnosticsCallback: enableDebug ? debugCallback : null,
);
```

## Résultats attendus

Avec le système adaptatif :

- ✅ **G3 reste affiché en continu** même après 5+ secondes de sustain
- ✅ **E2, A2, D3, B3** également stabilisés  
- ✅ **Notes aiguës restent réactives** (pas de régression)
- ✅ **Transition automatique** entre profils selon la fréquence
- ✅ **Diagnostics disponibles** pour déboguer des cas spécifiques

## Comparaison des approches

| Aspect | Service Original | Service Adaptatif |
|--------|------------------|-------------------|
| G3 stability | ❌ Coupe après 1-2s | ✅ Continu |
| Configuration | Paramètres fixes | Auto-adaptation |
| Notes graves | Problématiques | Optimisées |
| Notes aiguës | OK | OK |
| Diagnostics | Limités | Complets |
| Migration | - | Drop-in compatible |