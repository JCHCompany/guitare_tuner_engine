import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pitch_detection/pitch_detection.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pitch Detection Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PitchDetectionDemo(),
    );
  }
}

class PitchDetectionDemo extends StatefulWidget {
  const PitchDetectionDemo({super.key});

  @override
  State<PitchDetectionDemo> createState() => _PitchDetectionDemoState();
}

class _PitchDetectionDemoState extends State<PitchDetectionDemo> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final PitchEstimationService _pitchService;

  bool _isListening = false;
  PitchEstimate? _currentEstimate;
  String _statusMessage = 'Appuyez pour commencer l\'écoute';

  static const double sampleRate = 44100.0;

  @override
  void initState() {
    super.initState();

    _pitchService = PitchEstimationService(
      sampleRate: sampleRate,
      minF0: 70.0,
      maxF0: 1000.0,
    );
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    // Demander permission microphone
    final permission = await Permission.microphone.request();
    if (permission != PermissionStatus.granted) {
      setState(() {
        _statusMessage = 'Permission microphone refusée';
      });
      return;
    }

    // Vérifier support de l'enregistrement
    if (!await _audioRecorder.hasPermission()) {
      setState(() {
        _statusMessage = 'Permission microphone non accordée';
      });
      return;
    }

    try {
      // Commencer l'enregistrement en stream
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        bitRate: 16,
        numChannels: 1,
      );

      final stream = await _audioRecorder.startStream(config);

      setState(() {
        _isListening = true;
        _statusMessage = 'Écoute en cours...';
      });

      // Traiter le stream audio
      await for (final audioData in stream) {
        if (!_isListening) break;

        _processAudioData(audioData);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur: $e';
      });
    }
  }

  Future<void> _stopListening() async {
    await _audioRecorder.stop();
    setState(() {
      _isListening = false;
      _statusMessage = 'Écoute arrêtée';
      _currentEstimate = null;
    });
  }

  void _processAudioData(Uint8List audioData) {
    try {
      // Convertir bytes en Float64List
      final samples = _convertToFloat64(audioData);

      // Analyser avec le service de pitch detection
      final estimate = _pitchService.estimatePitch(samples);

      setState(() {
        _currentEstimate = estimate;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Erreur traitement: $e';
      });
    }
  }

  Float64List _convertToFloat64(Uint8List audioData) {
    // Conversion PCM 16-bit vers Float64
    final samples = Float64List(audioData.length ~/ 2);

    for (int i = 0; i < samples.length; i++) {
      final int16Value = (audioData[i * 2 + 1] << 8) | audioData[i * 2];
      final normalizedValue = int16Value.toSigned(16) / 32768.0;
      samples[i] = normalizedValue;
    }

    return samples;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Pitch Detection Demo'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Statut
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _statusMessage,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Résultats de détection
              if (_currentEstimate != null) ...[
                _buildPitchDisplay(_currentEstimate!),
                const SizedBox(height: 32),
              ],

              // Bouton d'écoute
              ElevatedButton.icon(
                onPressed: _toggleListening,
                icon: Icon(_isListening ? Icons.stop : Icons.play_arrow),
                label: Text(_isListening ? 'Arrêter' : 'Commencer'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(160, 48),
                ),
              ),

              const SizedBox(height: 32),

              // Informations du package
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Package: pitch_detection',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text('Algorithmes: YIN & MPM'),
                      const Text('Post-traitement: Anti-octave, filtre médian'),
                      const Text('Optimisé pour instruments musicaux'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPitchDisplay(PitchEstimate estimate) {
    if (!estimate.isVoiced) {
      return Card(
        color: Colors.grey.shade100,
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(Icons.volume_off, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('SILENCE',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    // Note détectée
    final frequency = estimate.f0Hz!;
    final note = estimate.note!;
    final cents = estimate.cents!;
    final algorithm = estimate.algorithm;
    final confidence = estimate.confidence;

    // Couleur selon la justesse
    Color noteColor = Colors.green;
    if (cents.abs() > 10) {
      noteColor = Colors.orange;
    }
    if (cents.abs() > 25) {
      noteColor = Colors.red;
    }

    return Card(
      color: noteColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Note principale
            Text(
              note,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: noteColor,
              ),
            ),

            const SizedBox(height: 8),

            // Fréquence
            Text(
              '${frequency.toStringAsFixed(2)} Hz',
              style: Theme.of(context).textTheme.titleLarge,
            ),

            const SizedBox(height: 8),

            // Cents
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${cents >= 0 ? '+' : ''}${cents.toStringAsFixed(0)}¢',
                  style: TextStyle(
                    fontSize: 24,
                    color: noteColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Informations techniques
            Text(
              'Algorithme: $algorithm',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Confiance: ${(confidence * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }
}
