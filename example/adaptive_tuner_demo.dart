import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:math' as math;
import '../lib/src/services/adaptive_pitch_estimation_service.dart';

/// Exemple d'utilisation du service adaptatif pour résoudre le problème G3
/// Remplacez simplement PitchEstimationService par AdaptivePitchEstimationService
class AdaptiveTunerExample extends StatefulWidget {
  @override
  _AdaptiveTunerExampleState createState() => _AdaptiveTunerExampleState();
}

class _AdaptiveTunerExampleState extends State<AdaptiveTunerExample> {
  late AdaptivePitchEstimationService _pitchService;

  // États d'affichage
  String _currentNote = '';
  double _currentFrequency = 0.0;
  double _confidence = 0.0;
  String _activeProfile = 'NONE';
  bool _isVoiced = false;

  // Diagnostics G3
  List<String> _g3Diagnostics = [];
  bool _enableG3Debug = false;

  @override
  void initState() {
    super.initState();

    // SOLUTION G3: Service adaptatif avec diagnostics
    _pitchService = AdaptivePitchEstimationService(
      sampleRate: 44100,

      // ✅ ACTIVATION DU SYSTÈME ADAPTATIF (solution principale)
      enableFrequencyAdaptation: true,

      // ✅ Réactivité maximale si besoin
      disableEmaSmoothing: false, // true pour réaction immédiate

      // ✅ Callback de diagnostics pour G3 et notes graves
      diagnosticsCallback: _enableG3Debug ? _onDiagnostics : null,
    );
  }

  /// Callback de diagnostics - capture les métriques pour notes problématiques
  void _onDiagnostics(Map<String, dynamic> data) {
    final note = data['note']?.toString() ?? '';

    // Filtre sur les notes problématiques (G3, E2, A2, D3)
    if (note.startsWith('G3') ||
        note.startsWith('E2') ||
        note.startsWith('A2') ||
        note.startsWith('D3')) {
      final rms = data['rms']?.toStringAsFixed(6) ?? '0';
      final threshold =
          data['adaptiveSilenceThreshold']?.toStringAsFixed(6) ?? '0';
      final profile = data['profileName']?.toString() ?? 'UNKNOWN';
      final silentFrames = data['silentFrames']?.toString() ?? '0';
      final locked = data['locked']?.toString() ?? 'false';

      final diagnostic =
          '$note: RMS=$rms, Seuil=$threshold, Profile=$profile, Silent=$silentFrames, Locked=$locked';

      setState(() {
        _g3Diagnostics.add(diagnostic);
        if (_g3Diagnostics.length > 10) {
          _g3Diagnostics.removeAt(0); // Garder les 10 derniers
        }
      });
    }
  }

  /// Simule l'estimation de pitch sur un frame audio
  /// Dans une vraie app, ceci serait appelé depuis votre callback audio
  void _simulateAudioFrame() {
    // Simulation d'un frame audio (remplacez par vos vraies données)
    final audioFrame = _generateTestTone(196.0, 0.1); // G3 simulé

    // ✅ ESTIMATION AVEC ADAPTATION AUTOMATIQUE
    final estimate = _pitchService.estimatePitch(audioFrame);

    // Mise à jour de l'UI
    setState(() {
      _isVoiced = estimate.isVoiced;
      _currentNote = estimate.note ?? '';
      _currentFrequency = estimate.f0Hz ?? 0.0;
      _confidence = estimate.confidence;
      _activeProfile = _pitchService.currentProfile?.name ?? 'DEFAULT';
    });
  }

  /// Génère un tone de test pour simulation
  Float64List _generateTestTone(double frequency, double amplitude) {
    const int frameSize = 1024;
    const double sampleRate = 44100;
    final frame = Float64List(frameSize);

    for (int i = 0; i < frameSize; i++) {
      final t = i / sampleRate;
      frame[i] = amplitude * math.sin(2 * math.pi * frequency * t);
    }

    return frame;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tuner Adaptatif - Solution G3'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status principal
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'État de détection',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('Note: $_currentNote'),
                    Text(
                        'Fréquence: ${_currentFrequency.toStringAsFixed(2)} Hz'),
                    Text(
                        'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%'),
                    Text('Profil actif: $_activeProfile'),
                    Text('Status: ${_isVoiced ? "VOICED" : "SILENCE"}',
                        style: TextStyle(
                          color: _isVoiced ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        )),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Contrôles
            Row(
              children: [
                ElevatedButton(
                  onPressed: _simulateAudioFrame,
                  child: Text('Simuler G3'),
                ),
                SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _enableG3Debug = !_enableG3Debug;
                      // Réinitialiser le service avec/sans diagnostics
                      _pitchService = AdaptivePitchEstimationService(
                        sampleRate: 44100,
                        enableFrequencyAdaptation: true,
                        diagnosticsCallback:
                            _enableG3Debug ? _onDiagnostics : null,
                      );
                    });
                  },
                  child: Text(
                      _enableG3Debug ? 'Désactiver Debug' : 'Activer Debug G3'),
                ),
              ],
            ),

            SizedBox(height: 16),

            // Diagnostics G3
            if (_enableG3Debug) ...[
              Text(
                'Diagnostics G3 en temps réel:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    itemCount: _g3Diagnostics.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _g3Diagnostics[index],
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      );
                    },
                  ),
                ),
              ),
            ],

            // Informations sur la solution
            if (!_enableG3Debug)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Solution G3 Implémentée ✅',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green),
                        ),
                        SizedBox(height: 12),
                        Text('• Système adaptatif activé automatiquement'),
                        Text(
                            '• Profil BASS pour G3 (80-250 Hz): seuil 3%, debounce 12 frames'),
                        Text(
                            '• Profil MID_LOW pour C4-F4: seuil 6%, debounce 8 frames'),
                        Text(
                            '• Profil MID pour G4-C5: seuil 8%, debounce 5 frames'),
                        Text(
                            '• Profil HIGH pour D5+: seuil 12%, debounce 3 frames'),
                        SizedBox(height: 12),
                        Text(
                          'Résultat attendu:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                            'G3 reste affiché en continu même après 5+ secondes'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Nettoyage si nécessaire
    super.dispose();
  }
}

/// Exemple d'intégration dans une app existante
class MigrationExample {
  static void showMigration() {
    print('''
MIGRATION SIMPLE - Remplacer le service existant:

// AVANT (problème G3)
final service = PitchEstimationService(
  sampleRate: 44100,
);

// APRÈS (G3 résolu automatiquement)
final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  enableFrequencyAdaptation: true, // Solution G3
);

// Le reste du code reste identique !
final estimate = service.estimatePitch(audioFrame);

-----

CONFIGURATION AVANCÉE:

final service = AdaptivePitchEstimationService(
  sampleRate: 44100,
  
  // ✅ Système adaptatif (solution principale)
  enableFrequencyAdaptation: true,
  
  // ✅ Réactivité max si besoin (désactive l'EMA)
  disableEmaSmoothing: true,
  
  // ✅ Diagnostics pour déboguer des notes spécifiques
  diagnosticsCallback: (data) {
    if (data['note'].toString().startsWith('G3')) {
      print('G3 Debug: \${data}');
    }
  },
);

-----

RÉSULTATS ATTENDUS:
✅ G3 ne s'arrête plus après 1-2s
✅ E2, A2, D3, B3 également stabilisés
✅ Notes aiguës restent réactives
✅ Adaptation automatique selon fréquence
✅ Aucune régression sur les autres notes
''');
  }
}
