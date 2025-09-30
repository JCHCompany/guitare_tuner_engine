# Pitch Detection

A Flutter package for real-time pitch detection using YIN and MPM algorithms, optimized for musical instruments.

## Features

- **Dual Algorithm Support**: YIN and MPM algorithms for robust pitch detection
- **Real-time Processing**: Optimized for low-latency audio analysis
- **Post-processing Pipeline**: Anti-octave protection, median filtering, outlier detection
- **Musical Optimization**: Specifically tuned for guitar and other musical instruments
- **High Accuracy**: Advanced stabilization and hysteresis for stable results

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  pitch_detection: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Usage

### Basic Pitch Detection

```dart
import 'package:pitch_detection/pitch_detection.dart';
import 'dart:typed_data';

// Create the service
final pitchService = PitchEstimationService(
  sampleRate: 44100.0,
  minF0: 70.0,    // Minimum frequency (Hz)
  maxF0: 1000.0,  // Maximum frequency (Hz)
);

// Analyze audio frame (Float64List samples)
final estimate = pitchService.estimatePitch(audioSamples);

if (estimate.isVoiced) {
  print('Detected: ${estimate.note} at ${estimate.f0Hz} Hz');
  print('Cents deviation: ${estimate.cents}');
  print('Confidence: ${estimate.confidence}');
  print('Algorithm used: ${estimate.algorithm}');
} else {
  print('Silence detected');
}
```

### Using Individual Algorithms

```dart
// YIN Algorithm
final yinDetector = YinPitchDetector(
  sampleRate: 44100.0,
  minF0: 70.0,
  maxF0: 1000.0,
);

final yinResult = yinDetector.estimatePitch(audioSamples);
if (yinResult != null) {
  print('YIN: ${yinResult.frequency} Hz (confidence: ${yinResult.confidence})');
}

// MPM Algorithm  
final mpmDetector = MpmPitchDetector(
  sampleRate: 44100.0,
  minF0: 70.0,
  maxF0: 1000.0,
);

final mpmResult = mpmDetector.estimatePitch(audioSamples);
if (mpmResult != null) {
  print('MPM: ${mpmResult.frequency} Hz (confidence: ${mpmResult.confidence})');
}
```

### Real-time Audio Integration

```dart
import 'package:record/record.dart';

final audioRecorder = AudioRecorder();
final pitchService = PitchEstimationService(sampleRate: 44100.0);

// Start recording
const config = RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 44100,
  numChannels: 1,
);

final stream = await audioRecorder.startStream(config);

await for (final audioData in stream) {
  // Convert Uint8List to Float64List
  final samples = convertToFloat64(audioData);
  
  // Analyze pitch
  final estimate = pitchService.estimatePitch(samples);
  
  if (estimate.isVoiced) {
    print('Note: ${estimate.note} (${estimate.cents}¢)');
  }
}
```

## API Reference

### PitchEstimate

Main result class containing pitch detection information:

```dart
class PitchEstimate {
  final DateTime timestamp;      // When the estimate was made
  final double? f0Hz;           // Fundamental frequency in Hz
  final String? note;           // Musical note (e.g., "E2", "A4")
  final double? cents;          // Deviation in cents from the note
  final double confidence;      // Confidence level [0-1]
  final bool isVoiced;         // Whether a pitch was detected
  final String algorithm;       // Algorithm used ("YIN", "MPM", or "SILENCE")
}
```

### PitchEstimationService

Main service class with advanced post-processing:

```dart
PitchEstimationService({
  required double sampleRate,   // Audio sample rate (Hz)
  double minF0 = 70.0,         // Minimum frequency to detect
  double maxF0 = 1000.0,       // Maximum frequency to detect
})

// Methods
PitchEstimate estimatePitch(Float64List audioFrame);
Map<String, dynamic> getPerformanceStats();
void reset();
```

### YinPitchDetector

YIN algorithm implementation:

```dart
YinPitchDetector({
  required double sampleRate,
  double minF0 = 70.0,
  double maxF0 = 1000.0,
  double troughThreshold = 0.15,
})

({double frequency, double confidence})? estimatePitch(Float64List audioFrame);
```

### MpmPitchDetector

MPM (McLeod Pitch Method) implementation:

```dart
MpmPitchDetector({
  required double sampleRate,
  double minF0 = 70.0,
  double maxF0 = 1000.0,
  double clarityThreshold = 0.75,
})

({double frequency, double confidence})? estimatePitch(Float64List audioFrame);
```

## Algorithms

### YIN Algorithm
- **Reference**: "YIN, a fundamental frequency estimator for speech and music" (2002)
- **Strengths**: Excellent for monophonic signals, stable results
- **Use case**: Guitar tuning, vocal analysis

### MPM Algorithm  
- **Reference**: "A Smarter Way to Find Pitch" (McLeod & Wyvill, 2005)
- **Strengths**: Good harmonic content handling, FFT-optimized
- **Use case**: Complex instruments, polyphonic signals

## Performance Tips

1. **Frame Size**: Use 2048-4096 samples for best accuracy
2. **Sample Rate**: 44.1 kHz recommended for musical applications  
3. **Frequency Range**: Tune `minF0`/`maxF0` to your specific instrument
4. **Memory**: Service maintains small history buffers for stability

## Example App

See the `/example` directory for a complete Flutter app demonstrating real-time pitch detection with microphone input.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.