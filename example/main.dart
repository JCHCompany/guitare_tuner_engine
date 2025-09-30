import 'package:flutter/material.dart';
import 'package:guitar_tuner_engine/guitar_tuner_engine.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guitar Tuner Engine Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const TunerExamplePage(),
    );
  }
}

class TunerExamplePage extends StatefulWidget {
  const TunerExamplePage({super.key});

  @override
  State<TunerExamplePage> createState() => _TunerExamplePageState();
}

class _TunerExamplePageState extends State<TunerExamplePage> {
  late GuitarTunerEngine _tuner;
  StreamSubscription<TuningResult>? _subscription;

  TuningResult? _lastResult;
  TunerConfig _currentConfig = const TunerConfig();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _tuner = GuitarTunerEngine(_currentConfig);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _tuner.dispose();
    super.dispose();
  }

  void _startTuning() async {
    final success = await _tuner.startTuning();
    if (success) {
      setState(() {
        _isListening = true;
      });

      _subscription = _tuner.tuningResults.listen((result) {
        setState(() {
          _lastResult = result;
        });
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Failed to start tuning. Check microphone permissions.'),
          ),
        );
      }
    }
  }

  void _stopTuning() async {
    await _tuner.stopTuning();
    await _subscription?.cancel();
    _subscription = null;

    setState(() {
      _isListening = false;
      _lastResult = null;
    });
  }

  void _changeConfig(TunerConfig newConfig) async {
    final wasListening = _isListening;

    if (wasListening) {
      _stopTuning();
    }

    _tuner.dispose();
    _tuner = GuitarTunerEngine(newConfig);

    setState(() {
      _currentConfig = newConfig;
    });

    if (wasListening) {
      _startTuning();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guitar Tuner Engine Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Configuration selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configuration Presets',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8.0,
                      children: [
                        _ConfigButton(
                          'Default',
                          const TunerConfig(),
                          _currentConfig,
                          _changeConfig,
                        ),
                        _ConfigButton(
                          'Acoustic',
                          TunerConfig.acoustic(),
                          _currentConfig,
                          _changeConfig,
                        ),
                        _ConfigButton(
                          'Electric',
                          TunerConfig.electric(),
                          _currentConfig,
                          _changeConfig,
                        ),
                        _ConfigButton(
                          'Bass',
                          TunerConfig.bass(),
                          _currentConfig,
                          _changeConfig,
                        ),
                        _ConfigButton(
                          'Noisy',
                          TunerConfig.noisyEnvironment(),
                          _currentConfig,
                          _changeConfig,
                        ),
                        _ConfigButton(
                          'Quiet',
                          TunerConfig.quiet(),
                          _currentConfig,
                          _changeConfig,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isListening ? null : _startTuning,
                  icon: const Icon(Icons.mic),
                  label: const Text('Start Tuning'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isListening ? _stopTuning : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: ${_isListening ? "Listening..." : "Stopped"}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isListening ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Results
            if (_lastResult != null) _buildResultCard(_lastResult!),

            const SizedBox(height: 20),

            // Configuration details
            _buildConfigDetails(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(TuningResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tuning Result',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (result.isValid) ...[
              Text('Frequency: ${result.frequency!.toStringAsFixed(1)} Hz'),
              Text('Note: ${result.closestNote ?? "Unknown"}'),
              if (result.centsOffset != null)
                Text('Cents: ${result.centsOffset!.toStringAsFixed(1)}¢'),
              Text('In Tune: ${result.isInTune ? "Yes" : "No"}'),
              Text('Amplitude: ${result.amplitude.toStringAsFixed(4)}'),
              Text(
                  'Has Harmonics: ${result.hasHarmonicStructure ? "Yes" : "No"}'),
              Text('Stable: ${result.isStable ? "Yes" : "No"}'),
            ] else ...[
              Text(
                'No valid note detected',
                style: TextStyle(color: Colors.orange[800]),
              ),
              if (result.failureReason != null)
                Text('Reason: ${result.failureReason}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfigDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Min Amplitude: ${_currentConfig.minAmplitudeThreshold}'),
            Text('Min Harmonics: ${_currentConfig.minHarmonicsRequired}'),
            Text(
                'Harmonic Tolerance: ${(_currentConfig.harmonicTolerance * 100).toStringAsFixed(1)}%'),
            Text(
                'Stability Duration: ${_currentConfig.stabilityDuration.inMilliseconds}ms'),
            Text(
                'Frequency Range: ${_currentConfig.minFrequency.toStringAsFixed(0)}-${_currentConfig.maxFrequency.toStringAsFixed(0)} Hz'),
            Text('Sample Rate: ${_currentConfig.sampleRate} Hz'),
            Text('Buffer Size: ${_currentConfig.bufferSize}'),
          ],
        ),
      ),
    );
  }
}

class _ConfigButton extends StatelessWidget {
  final String name;
  final TunerConfig config;
  final TunerConfig currentConfig;
  final Function(TunerConfig) onSelected;

  const _ConfigButton(
    this.name,
    this.config,
    this.currentConfig,
    this.onSelected,
  );

  @override
  Widget build(BuildContext context) {
    final isSelected = config == currentConfig;

    return ElevatedButton(
      onPressed: () => onSelected(config),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
        foregroundColor: isSelected ? Colors.white : Colors.black87,
      ),
      child: Text(name),
    );
  }
}
