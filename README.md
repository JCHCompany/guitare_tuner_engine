# Guitar Tuner Engine

A Flutter package for intelligent guitar tuning with advanced noise filtering and harmonic detection.

## Features

🎸 **Intelligent Note Detection**: Uses FFT analysis with harmonic validation to distinguish musical notes from noise  
🔇 **Advanced Noise Filtering**: Filters out taps, clicks, speech, and other non-musical sounds  
⚙️ **Highly Configurable**: Customizable parameters for different guitars and environments  
🎯 **Accurate Tuning**: Provides frequency, note name, and cent offset for precise tuning  
📱 **Flutter Ready**: Easy to integrate into Flutter apps with stream-based API  

## Quick Start

Add to your `pubspec.yaml`:

```yaml
dependencies:
  guitar_tuner_engine: ^1.0.0
```

Basic usage:

```dart
import 'package:guitar_tuner_engine/guitar_tuner_engine.dart';

// Create a tuner
final tuner = GuitarTunerEngine();

// Listen for results
tuner.tuningResults.listen((result) {
  if (result.isValid && result.isStable) {
    print('🎵 Note: ${result.closestNote}');
    print('📊 Frequency: ${result.frequency!.toStringAsFixed(1)} Hz');
    print('🎯 Cents: ${result.centsOffset!.toStringAsFixed(1)}¢');
    print('✅ In tune: ${result.isInTune}');
  }
});

// Start tuning
if (await tuner.startTuning()) {
  print('🎤 Listening for guitar notes...');
} else {
  print('❌ Failed to start - check microphone permissions');
}

// Stop when done
await tuner.stopTuning();
tuner.dispose();
```

## Configuration Presets

Choose the preset that best fits your use case:

```dart
// For acoustic guitar (default settings)
final tuner = GuitarTunerEngine(TunerConfig.acoustic());

// For electric guitar (more strict harmonic detection)
final tuner = GuitarTunerEngine(TunerConfig.electric());

// For bass guitar (lower frequency range)
final tuner = GuitarTunerEngine(TunerConfig.bass());

// For noisy environments (more conservative detection)
final tuner = GuitarTunerEngine(TunerConfig.noisyEnvironment());

// For quiet practice (more sensitive detection)
final tuner = GuitarTunerEngine(TunerConfig.quiet());
```

## Custom Configuration

Fine-tune the detection algorithm for your specific needs:

```dart
final config = TunerConfig(
  minAmplitudeThreshold: 0.002,      // Minimum signal strength
  minHarmonicsRequired: 2,           // Harmonics needed (1-4)
  harmonicTolerance: 0.05,           // 5% tolerance for harmonics
  stabilityDuration: Duration(milliseconds: 80), // Stability time
  minFrequency: 75.0,                // Min frequency (Hz)
  maxFrequency: 450.0,               // Max frequency (Hz)
  
  // Custom tuning (e.g., Drop D)
  guitarStringFreqs: {
    'D6': 73.42,   // 6th string dropped to D
    'A5': 110.00,  // 5th string
    'D4': 146.83,  // 4th string  
    'G3': 196.00,  // 3rd string
    'B2': 246.94,  // 2nd string
    'E1': 329.63,  // 1st string
  },
);

final tuner = GuitarTunerEngine(config);
```

## How It Works

### 1. Audio Capture
- Records audio at 44.1kHz sample rate in mono
- Processes audio in 4096-sample buffers for real-time analysis
- Automatically handles microphone permissions

### 2. FFT Analysis  
- Performs Fast Fourier Transform on each audio buffer
- Calculates magnitude spectrum to find frequency peaks
- Focuses on guitar frequency range (75-450Hz by default)

### 3. Harmonic Validation
```dart
// Checks for harmonics at 2f, 3f, 4f, 5f
for (int harmonic = 2; harmonic <= 5; harmonic++) {
  final harmonicFreq = fundamental * harmonic;
  // Looks for significant energy at harmonic frequencies
  // Rejects sounds without musical harmonic structure
}
```

### 4. Temporal Stability
- Frequency must remain stable for 80ms (configurable)
- Prevents detection of brief transient noises
- Ensures reliable note identification

### 5. Note Identification
- Matches detected frequency to closest guitar string
- Calculates cent offset for tuning accuracy  
- Determines if note is "in tune" (within ±5 cents)

## API Reference

### TuningResult

```dart
class TuningResult {
  final bool isValid;              // Whether a valid note was detected
  final double? frequency;         // Detected frequency in Hz
  final double amplitude;          // Signal amplitude (0.0-1.0+)
  final bool hasHarmonicStructure; // Whether harmonics were found
  final bool isStable;            // Whether frequency is stable
  final String? closestNote;      // Closest guitar string (e.g., "E6")
  final double? centsOffset;      // Offset in cents (+/-)
  final bool isInTune;           // Whether note is in tune (±5¢)
  final String? failureReason;    // Why detection failed
  final List<double> spectrum;    // FFT spectrum for visualization
}
```

### TunerConfig

```dart
class TunerConfig {
  final double minAmplitudeThreshold;    // 0.0001 - 0.1
  final int minHarmonicsRequired;        // 1 - 4  
  final double harmonicTolerance;        // 0.01 - 0.2 (1%-20%)
  final Duration stabilityDuration;      // 50ms - 500ms
  final double minFrequency;             // 50Hz - 150Hz
  final double maxFrequency;             // 300Hz - 1000Hz
  final int sampleRate;                  // Audio sample rate
  final int bufferSize;                  // FFT buffer size (power of 2)
  final Map<String, double> guitarStringFreqs; // Note frequencies
}
```

## Permissions

Add to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MICROPHONE" />
```

For iOS, add to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to detect guitar notes for tuning.</string>
```

## Performance Tips

- **Buffer Size**: Larger buffers (8192) give better frequency resolution but slower response
- **Sample Rate**: 44.1kHz is optimal for guitars; higher rates don't improve accuracy
- **Stability Duration**: Increase for noisy environments, decrease for faster response
- **Harmonic Requirements**: More harmonics = better noise rejection but may miss quiet notes

## Troubleshooting

**No notes detected:**
- Check microphone permissions
- Ensure guitar is loud enough (increase sensitivity or decrease `minAmplitudeThreshold`)  
- Try the "quiet" preset: `TunerConfig.quiet()`

**False positives from noise:**
- Use "noisy environment" preset: `TunerConfig.noisyEnvironment()`
- Increase `minHarmonicsRequired` to 3 or 4
- Increase `stabilityDuration` to 150ms+

**Slow response:**
- Decrease `stabilityDuration` to 50ms
- Decrease `bufferSize` to 2048 (may reduce accuracy)
- Use fewer required harmonics

## Example Project

See the `/example` folder for a complete Flutter app demonstrating all features:

- Configuration preset switching  
- Real-time tuning display
- Frequency spectrum visualization
- Configuration parameter details

## Contributing

Contributions welcome! Please read our contributing guidelines and submit pull requests to our GitHub repository.

## License

MIT License - see LICENSE file for details.