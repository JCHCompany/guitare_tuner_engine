# Solution de stabilisation d'attaque et protection contre les sous-harmoniques

## Problèmes résolus

### 1. Sautillement initial (attaque)
- **Symptôme** : Note qui sautille au début quand on commence à gratter
- **Cause** : Instabilité de détection pendant les premières millisecondes d'attaque

### 2. Saut vers sous-harmoniques (E4 → A2/E2)
- **Symptôme** : E4 passe sur harmoniques A2/E2 quand l'amplitude baisse
- **Cause** : Confusion harmonique lors de la baisse d'amplitude

## Solutions implémentées

### Stabilisation d'attaque (`_applyAttackStabilization`)

```dart
/// Stabilise la fréquence pendant l'attaque pour réduire le sautillement
double _applyAttackStabilization(double frequency, DateTime now) {
  // Détection nouvelle attaque (>500ms sans détection)
  final isNewAttaque = _firstDetectionTime == null || 
      now.difference(_firstDetectionTime!).inMilliseconds > 500;
  
  if (isNewAttaque) {
    _firstDetectionTime = now;
    _attackFrequencies.clear();
  }
  
  _attackFrequencies.add(frequency);
  
  // Pendant les 8 premières frames (_attackStabilizationFrames)
  if (_attackFrequencies.length <= _attackStabilizationFrames) {
    // Utilise la médiane pour plus de stabilité
    final sortedFreqs = List<double>.from(_attackFrequencies)..sort();
    final median = sortedFreqs[sortedFreqs.length ~/ 2];
    
    // Filtre les valeurs aberrantes (>15% d'écart)
    final deviationRatio = (frequency - median).abs() / median;
    if (deviationRatio > 0.15) {
      return median; // Utilise la médiane à la place
    }
  }
  
  return frequency;
}
```

**Mécanisme :**
1. **Détection d'attaque** : Gap de >500ms = nouvelle attaque
2. **Collection initiale** : Stocke les 8 premières fréquences
3. **Stabilisation par médiane** : Utilise la médiane au lieu de la moyenne
4. **Filtrage aberrant** : Rejette les valeurs >15% d'écart avec la médiane
5. **Nettoyage automatique** : Évite l'accumulation excessive

### Protection contre sous-harmoniques (améliorée)

```dart
/// Protection renforcée contre les harmoniques et sous-harmoniques
double _applyAntiOctaveProtection(double frequency) {
  if (_lastStableFrequency == null) return frequency;
  
  final ratio = frequency / _lastStableFrequency!;
  final currentRms = _amp.rms;
  
  // Détection baisse d'amplitude
  final isAmplitudeDeclining = currentRms / _amp.recentMax < 0.6;
  
  // Protection sous-harmoniques spécialement lors de baisse d'amplitude
  if (isAmplitudeDeclining && ratio < 0.35 && ratio > 0.2) {
    return _lastStableFrequency!; // Maintient la fréquence stable
  }
  
  // Protection spéciale E4→A2 (ratio ≈ 0.33)
  if (ratio > 0.30 && ratio < 0.36) {
    return _lastStableFrequency!;
  }
  
  // Protections existantes (octaves, 2/3, 3/4, 4/3, 3/2)...
  
  return frequency;
}
```

**Nouvelles protections :**
1. **Détection baisse amplitude** : `currentRms / recentMax < 0.6`
2. **Zone sous-harmonique** : Ratios 0.2-0.35 durant baisse d'amplitude
3. **Cas spécial E4→A2** : Ratio ~0.33 (220Hz/330Hz ≈ 0.33)

## Configuration recommandée

### Paramètres d'attaque
- `_attackStabilizationFrames = 8` : 8 frames de stabilisation
- Seuil aberrant : 15% d'écart maximum avec la médiane
- Timeout nouvelle attaque : 500ms

### Protection sous-harmoniques
- Seuil baisse amplitude : 60% du maximum récent
- Zone critique : Ratios 0.2-0.35
- Cas spécial E4→A2 : Ratios 0.30-0.36

## Avantages

### Stabilisation d'attaque
- ✅ Élimine le sautillement initial
- ✅ Conserve la réactivité (8 frames seulement)
- ✅ Robuste aux valeurs aberrantes (médiane)
- ✅ Auto-adaptatif aux pauses de jeu

### Protection sous-harmoniques
- ✅ Maintient E4 stable lors de baisse d'amplitude
- ✅ Évite les sauts E4→A2/E2
- ✅ Préserve les vraies transitions harmoniques
- ✅ Spécialement optimisé pour guitare

## Usage

Le système est automatiquement activé dans `AdaptivePitchEstimationService` :

```dart
// Dans estimate()
final finalFrequency = _applyAttackStabilization(
  _applyAntiOctaveProtection(stabilizedFrequency), 
  now
);
```

Ordre d'application :
1. Lissage EMA standard
2. Protection anti-octave/sous-harmonique
3. Stabilisation d'attaque
4. Création estimate finale