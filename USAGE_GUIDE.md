# Guide d'utilisation : Comment intégrer guitar_tuner_engine dans votre app

## Remplacement de pitch_detector_dart

Voici comment remplacer `pitch_detector_dart` par `guitar_tuner_engine` dans votre app existante.

### 1. Installation

Ajoutez le package à votre `pubspec.yaml` :

```yaml
dependencies:
  # Remplacez pitch_detector_dart par :
  guitar_tuner_engine: 
    path: ../guitar_tuner_engine  # Chemin local pour le développement
    # Ou quand publié sur pub.dev :
    # guitar_tuner_engine: ^1.0.0
```

### 2. Migration de pitch_detector_dart

#### Ancien code avec pitch_detector_dart :
```dart
import 'package:pitch_detector_dart/pitch_detector_dart.dart';

class OldTuner {
  late PitchDetector _pitchDetector;
  
  void initTuner() {
    _pitchDetector = PitchDetector(44100, 2000);
  }
  
  void processAudio(List<double> samples) {
    final result = _pitchDetector.getPitch(samples);
    if (result.pitched) {
      final frequency = result.pitch;
      // Traitement basique de la fréquence
      print('Fréquence: $frequency Hz');
    }
  }
}
```

#### Nouveau code avec guitar_tuner_engine :
```dart
import 'package:guitar_tuner_engine/guitar_tuner_engine.dart';

class NewTuner {
  late GuitarTunerEngine _tuner;
  StreamSubscription<TuningResult>? _subscription;
  
  void initTuner() {
    // Configuration plus précise que pitch_detector_dart
    final config = TunerConfig(
      minAmplitudeThreshold: 0.002,    // Seuil de bruit
      minHarmonicsRequired: 2,         // Validation harmonique
      stabilityDuration: Duration(milliseconds: 100), // Anti-bruit temporel
    );
    
    _tuner = GuitarTunerEngine(config);
  }
  
  Future<void> startTuning() async {
    if (await _tuner.startTuning()) {
      _subscription = _tuner.tuningResults.listen((result) {
        if (result.isValid && result.isStable) {
          // Fréquence validée avec filtrages anti-bruits
          final frequency = result.frequency!;
          final note = result.closestNote!;
          final cents = result.centsOffset!;
          
          print('Note: $note, Fréquence: ${frequency.toStringAsFixed(1)} Hz');
          print('Accordage: ${cents.toStringAsFixed(1)}¢');
          print('Juste: ${result.isInTune}');
          
          // Votre logique métier ici...
          onNoteDetected(frequency, note, cents, result.isInTune);
        }
      });
    }
  }
  
  void onNoteDetected(double freq, String note, double cents, bool inTune) {
    // Votre traitement des résultats
  }
  
  void dispose() {
    _subscription?.cancel();
    _tuner.dispose();
  }
}
```

### 3. Avantages par rapport à pitch_detector_dart

#### Filtrage intelligent des bruits :
```dart
// ❌ pitch_detector_dart détecte tout, même les bruits
// Détecte : choc de tasse, parole, bruit de table, etc.

// ✅ guitar_tuner_engine filtre intelligemment
final config = TunerConfig.noisyEnvironment(); // Pour environnements bruyants
// Ignore : chocs, parole, bruits non-musicaux
// Détecte : vraies notes de guitare même à faible volume
```

#### Validation harmonique :
```dart
// ❌ pitch_detector_dart : détection de fréquence basique
// Peut détecter des faux positifs sur des bruits

// ✅ guitar_tuner_engine : validation harmonique
final config = TunerConfig(
  minHarmonicsRequired: 2, // Exige 2f, 3f harmoniques
  harmonicTolerance: 0.05, // 5% de tolérance
);
// Ne valide que les sons avec structure harmonique musicale
```

#### Stabilité temporelle :
```dart
// ❌ pitch_detector_dart : résultat instantané
// Fluctuations sur les bruits impulsifs

// ✅ guitar_tuner_engine : stabilité requise
final config = TunerConfig(
  stabilityDuration: Duration(milliseconds: 80), // 80ms stable requis
);
// Filtre les bruits de courte durée automatiquement
```

### 4. Configurations pour différents cas d'usage

#### Guitare acoustique (défaut) :
```dart
final tuner = GuitarTunerEngine(TunerConfig.acoustic());
// Paramètres équilibrés pour guitare acoustique standard
```

#### Guitare électrique (plus strict) :
```dart
final tuner = GuitarTunerEngine(TunerConfig.electric());
// Détection plus stricte, moins de tolérance aux harmoniques
```

#### Environnement bruyant :
```dart
final tuner = GuitarTunerEngine(TunerConfig.noisyEnvironment());
// Seuils plus élevés, plus de stabilité requise
// Parfait pour concerts, répétitions, environnements urbains
```

#### Guitare basse :
```dart
final tuner = GuitarTunerEngine(TunerConfig.bass());
// Gamme de fréquences adaptée aux basses (30-200Hz)
```

#### Configuration personnalisée fine :
```dart
final customConfig = TunerConfig(
  minAmplitudeThreshold: 0.003,    // Plus strict pour éviter bruits faibles
  minHarmonicsRequired: 3,         // Exige 3 harmoniques (très strict)
  harmonicTolerance: 0.03,         // 3% tolérance (très précis)
  stabilityDuration: Duration(milliseconds: 150), // 150ms stable
  minFrequency: 80.0,              // Ignore fréquences < 80Hz
  maxFrequency: 400.0,             // Ignore fréquences > 400Hz
);
```

### 5. Gestion des résultats avancée

```dart
_tuner.tuningResults.listen((result) {
  if (result.isValid) {
    if (result.isStable) {
      // Note confirmée et stable
      updateUI(
        note: result.closestNote!,
        frequency: result.frequency!,
        cents: result.centsOffset!,
        inTune: result.isInTune,
      );
    } else {
      // Note détectée mais pas encore stable
      showPreviewNote(result.frequency!);
    }
  } else {
    // Aucune note valide
    clearDisplay();
    
    // Debug : pourquoi la détection a échoué
    if (kDebugMode) {
      print('Échec détection : ${result.failureReason}');
      print('Amplitude : ${result.amplitude}');
    }
  }
});
```

### 6. Optimisation des performances

```dart
// Pour une réponse plus rapide (au détriment de la précision)
final fastConfig = TunerConfig(
  bufferSize: 2048,                        // Plus petit buffer
  stabilityDuration: Duration(milliseconds: 50), // Moins de stabilité
  minHarmonicsRequired: 1,                 // Moins strict
);

// Pour une précision maximale (réponse plus lente)
final preciseConfig = TunerConfig(
  bufferSize: 8192,                        // Plus gros buffer
  stabilityDuration: Duration(milliseconds: 200), // Plus de stabilité
  minHarmonicsRequired: 4,                 // Très strict
);
```

### 7. Accordages alternatifs

```dart
// Drop D
final dropDConfig = TunerConfig(
  guitarStringFreqs: {
    'D6': 73.42,   // 6ème corde abaissée en D
    'A5': 110.00,
    'D4': 146.83,
    'G3': 196.00,
    'B2': 246.94,
    'E1': 329.63,
  },
);

// Open G
final openGConfig = TunerConfig(
  guitarStringFreqs: {
    'D6': 73.42,   // D
    'G5': 98.00,   // G
    'D4': 146.83,  // D
    'G3': 196.00,  // G
    'B2': 246.94,  // B
    'D1': 293.66,  // D
  },
);
```

### 8. Intégration dans votre UI existante

```dart
class YourExistingTunerPage extends StatefulWidget {
  @override
  _YourExistingTunerPageState createState() => _YourExistingTunerPageState();
}

class _YourExistingTunerPageState extends State<YourExistingTunerPage> {
  late GuitarTunerEngine _tuner;
  TuningResult? _currentResult;

  @override
  void initState() {
    super.initState();
    
    // Remplacez votre ancien PitchDetector par ceci :
    _tuner = GuitarTunerEngine(TunerConfig.acoustic());
  }

  // Remplacez votre ancienne méthode de start
  Future<void> startListening() async {
    if (await _tuner.startTuning()) {
      _tuner.tuningResults.listen((result) {
        setState(() => _currentResult = result);
        
        // Gardez votre logique UI existante, mais avec des données plus fiables :
        if (result.isValid && result.isStable) {
          updateTunerDisplay(
            frequency: result.frequency!,
            note: result.closestNote!,
            cents: result.centsOffset!,
            inTune: result.isInTune,
          );
        }
      });
    }
  }

  void updateTunerDisplay({required double frequency, required String note, required double cents, required bool inTune}) {
    // Votre code UI existant ici - pas besoin de changer !
  }

  @override
  void dispose() {
    _tuner.dispose(); // Remplacez votre ancien dispose
    super.dispose();
  }
}
```

Ce package vous donne un contrôle beaucoup plus fin que `pitch_detector_dart` et résout les problèmes de bruits parasites que vous mentionnez !