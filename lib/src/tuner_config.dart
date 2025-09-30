/// Configuration class for the guitar tuner engine.
///
/// This class allows you to customize various aspects of the tuning detection
/// algorithm to better suit different guitars, environments, or use cases.
class TunerConfig {
  /// Minimum amplitude threshold for signal detection.
  /// Signals below this threshold will be ignored.
  ///
  /// Default: 0.001
  /// Range: 0.0001 - 0.1
  final double minAmplitudeThreshold;

  /// Number of harmonics required to validate a musical note.
  /// A higher value makes the detection more strict but may miss quiet notes.
  ///
  /// Default: 2 (requires 2f, 3f harmonics to be present)
  /// Range: 1 - 4
  final int minHarmonicsRequired;

  /// Tolerance for harmonic detection as a percentage.
  /// Higher values allow more variation in harmonic frequencies.
  ///
  /// Default: 0.05 (5% tolerance)
  /// Range: 0.01 - 0.2
  final double harmonicTolerance;

  /// Duration that a frequency must remain stable before being reported.
  /// Helps filter out transient noises and brief sounds.
  ///
  /// Default: 80ms
  /// Range: 50ms - 500ms
  final Duration stabilityDuration;

  /// Minimum frequency to detect (Hz).
  /// Frequencies below this will be ignored.
  ///
  /// Default: 75.0 (below low E on guitar)
  /// Range: 50.0 - 150.0
  final double minFrequency;

  /// Maximum frequency to detect (Hz).
  /// Frequencies above this will be ignored.
  ///
  /// Default: 450.0 (above high E on guitar + some headroom)
  /// Range: 300.0 - 1000.0
  final double maxFrequency;

  /// Audio sample rate in Hz.
  /// Higher sample rates provide better frequency resolution.
  ///
  /// Default: 44100
  /// Common values: 22050, 44100, 48000
  final int sampleRate;

  /// Buffer size for FFT analysis (must be power of 2).
  /// Larger buffers provide better frequency resolution but slower response.
  ///
  /// Default: 4096
  /// Common values: 2048, 4096, 8192
  final int bufferSize;

  /// Custom guitar string frequencies.
  /// Override to support different tunings or instruments.
  ///
  /// Default: Standard guitar tuning (E-A-D-G-B-E)
  final Map<String, double> guitarStringFreqs;

  /// Creates a new tuner configuration.
  const TunerConfig({
    this.minAmplitudeThreshold = 0.001,
    this.minHarmonicsRequired = 2,
    this.harmonicTolerance = 0.05,
    this.stabilityDuration = const Duration(milliseconds: 80),
    this.minFrequency = 75.0,
    this.maxFrequency = 450.0,
    this.sampleRate = 44100,
    this.bufferSize = 4096,
    this.guitarStringFreqs = const {
      'E6': 82.41, // 6th string (low E)
      'A5': 110.00, // 5th string
      'D4': 146.83, // 4th string
      'G3': 196.00, // 3rd string
      'B2': 246.94, // 2nd string
      'E1': 329.63, // 1st string (high E)
    },
  })  : assert(
            minAmplitudeThreshold > 0, 'Amplitude threshold must be positive'),
        assert(minHarmonicsRequired >= 1, 'Must require at least 1 harmonic'),
        assert(harmonicTolerance > 0 && harmonicTolerance < 1,
            'Harmonic tolerance must be between 0 and 1'),
        assert(minFrequency < maxFrequency,
            'Min frequency must be less than max frequency'),
        assert(sampleRate > 0, 'Sample rate must be positive'),
        assert(bufferSize > 0 && (bufferSize & (bufferSize - 1)) == 0,
            'Buffer size must be a power of 2');

  /// Creates a configuration optimized for acoustic guitar.
  factory TunerConfig.acoustic() {
    return const TunerConfig(
      minAmplitudeThreshold: 0.002,
      minHarmonicsRequired: 2,
      harmonicTolerance: 0.08,
      stabilityDuration: Duration(milliseconds: 100),
    );
  }

  /// Creates a configuration optimized for electric guitar.
  factory TunerConfig.electric() {
    return const TunerConfig(
      minAmplitudeThreshold: 0.001,
      minHarmonicsRequired: 3,
      harmonicTolerance: 0.04,
      stabilityDuration: Duration(milliseconds: 60),
    );
  }

  /// Creates a configuration optimized for bass guitar.
  factory TunerConfig.bass() {
    return const TunerConfig(
      minAmplitudeThreshold: 0.003,
      minHarmonicsRequired: 2,
      harmonicTolerance: 0.1,
      stabilityDuration: Duration(milliseconds: 120),
      minFrequency: 30.0,
      maxFrequency: 200.0,
      guitarStringFreqs: {
        'E4': 41.20, // 4th string (low E)
        'A3': 55.00, // 3rd string
        'D2': 73.42, // 2nd string
        'G1': 98.00, // 1st string (high G)
      },
    );
  }

  /// Creates a configuration for noisy environments.
  /// More strict detection to avoid false positives.
  factory TunerConfig.noisyEnvironment() {
    return const TunerConfig(
      minAmplitudeThreshold: 0.005,
      minHarmonicsRequired: 3,
      harmonicTolerance: 0.03,
      stabilityDuration: Duration(milliseconds: 150),
    );
  }

  /// Creates a configuration for quiet environments.
  /// More sensitive detection to catch quiet notes.
  factory TunerConfig.quiet() {
    return const TunerConfig(
      minAmplitudeThreshold: 0.0005,
      minHarmonicsRequired: 1,
      harmonicTolerance: 0.1,
      stabilityDuration: Duration(milliseconds: 50),
    );
  }

  /// Creates a copy of this configuration with optional overrides.
  TunerConfig copyWith({
    double? minAmplitudeThreshold,
    int? minHarmonicsRequired,
    double? harmonicTolerance,
    Duration? stabilityDuration,
    double? minFrequency,
    double? maxFrequency,
    int? sampleRate,
    int? bufferSize,
    Map<String, double>? guitarStringFreqs,
  }) {
    return TunerConfig(
      minAmplitudeThreshold:
          minAmplitudeThreshold ?? this.minAmplitudeThreshold,
      minHarmonicsRequired: minHarmonicsRequired ?? this.minHarmonicsRequired,
      harmonicTolerance: harmonicTolerance ?? this.harmonicTolerance,
      stabilityDuration: stabilityDuration ?? this.stabilityDuration,
      minFrequency: minFrequency ?? this.minFrequency,
      maxFrequency: maxFrequency ?? this.maxFrequency,
      sampleRate: sampleRate ?? this.sampleRate,
      bufferSize: bufferSize ?? this.bufferSize,
      guitarStringFreqs: guitarStringFreqs ?? this.guitarStringFreqs,
    );
  }
}
