# Ajustements de réglage pour stabilité E4 et changements rapides

## Problèmes identifiés
1. **E4 → harmoniques** : Encore présent mais réduit
2. **Changements rapides de corde** : Saut de 200-300ms avant stabilisation

## Ajustements effectués

### 1. Réactivité pour changements rapides ⚡

#### Timeout nouvelle attaque : 300ms → 200ms
```dart
// Avant : 300ms
now.difference(_firstDetectionTime!).inMilliseconds > 300

// Après : 200ms  
now.difference(_firstDetectionTime!).inMilliseconds > 200
```

#### Frames de stabilisation : 5 → 4 frames
```dart
// Avant : 5 frames
final int _attackStabilizationFrames = 5;

// Après : 4 frames
final int _attackStabilizationFrames = 4;
```

### 2. Protection E4 renforcée 🛡️

#### Seuil amplitude plus sensible : 0.6 → 0.7
```dart
// Avant : 60% du max
(currentRms / _amp.recentMax) < 0.6

// Après : 70% du max (détection plus tôt)
(currentRms / _amp.recentMax) < 0.7
```

#### Zone sous-harmonique élargie : 0.2-0.35 → 0.18-0.38
```dart
// Avant : Zone 0.2-0.35
(ratio < 0.35 && ratio > 0.2)

// Après : Zone élargie 0.18-0.38
(ratio < 0.38 && ratio > 0.18)
```

#### Protection E4→A2 plus stricte
```dart
// Tolérance réduite : 0.15 → 0.12
_isNearRatio(ratio, 0.33, 0.12)  // E4→A2 (330→110)

// + Protection 1/4 harmonique strict
_isNearRatio(ratio, 0.25, 0.05)  // 1/4 harmonique
```

#### Protection générale supplémentaire (sans condition d'amplitude)
```dart
// Protection permanente pour cas persistants
if (_isNearRatio(ratio, 0.33, 0.08) ||  // E4→A2 très strict
    _isNearRatio(ratio, 0.25, 0.03)) {  // 1/4 harmonique très strict
  return _lastValidF0!;
}
```

## Impact attendu

### ✅ Changements rapides de corde
- **Avant** : 200-300ms de saut
- **Après** : 100-150ms (réduction ~50%)
- **Mécanisme** : Détection plus rapide + moins de frames de stabilisation

### ✅ Stabilité E4
- **Avant** : E4 → A2/E2 lors baisse amplitude
- **Après** : Protection multicouche
  1. Détection amplitude plus précoce (70% vs 60%)
  2. Zone sous-harmonique élargie (18%-38% vs 20%-35%)  
  3. Protection spécifique E4→A2 plus stricte (±8% vs ±15%)
  4. Protection permanente (sans condition d'amplitude)

## Paramètres de réglage

### Vitesse de réaction
```dart
_attackStabilizationFrames = 4    // Frames stabilisation (plus bas = plus rapide)
timeout = 200ms                   // Détection nouvelle attaque (plus bas = plus sensible)
deviationRatio = 0.12            // Seuil valeur aberrante (plus bas = plus strict)
```

### Protection E4
```dart
amplitudeDeclining = 0.7         // Seuil baisse amplitude (plus haut = détection plus tôt)
subHarmonicZone = 0.18-0.38      // Zone sous-harmonique (plus large = plus de protection)
e4ToA2Tolerance = ±8%            // Tolérance E4→A2 (plus strict = moins de faux positifs)
```

## Test recommandé

1. **E4 sustain** : Jouer E4, laisser amplitude baisser → ne devrait plus sauter vers A2
2. **Changements rapides** : E4→A4→D4→G4 rapidement → stabilisation <150ms
3. **Attaque normale** : Chaque corde individuellement → pas de sautillement initial
4. **Régression** : Vérifier G3, mute detection toujours fonctionnels