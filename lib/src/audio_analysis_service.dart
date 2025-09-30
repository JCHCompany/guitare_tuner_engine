import 'dart:typed_data';
import 'dart:math' as math;
import 'package:fftea/fftea.dart';
import 'tuner_config.dart';
import 'tuning_result.dart';

/// Service for analyzing audio data and detecting guitar notes.
///
/// This service uses FFT analysis and harmonic detection to identify
/// musical notes while filtering out noise and non-musical sounds.
class AudioAnalysisService {
  /// The configuration used for analysis.
  final TunerConfig config;

  /// Tracks frequency stability over time.
  final Map<double, DateTime> _frequencyStabilityTracker = {};

  /// Creates a new audio analysis service with the given configuration.
  AudioAnalysisService(this.config);

  /// Analyzes audio data and returns a tuning result.
  ///
  /// [audioData] should contain normalized audio samples (-1.0 to 1.0).
  /// [sampleRate] is the audio sampling rate in Hz.
  ///
  /// Returns a [TuningResult] indicating whether a valid note was detected
  /// and providing detailed analysis information.
  TuningResult analyzeAudioData(List<double> audioData, double sampleRate) {
    if (audioData.isEmpty) {
      return TuningResult.failed('Empty audio data');
    }

    // Convert to complex numbers for FFT
    final complexData = Float64x2List(audioData.length);
    for (int i = 0; i < audioData.length; i++) {
      complexData[i] = Float64x2(audioData[i], 0.0);
    }

    // Perform FFT
    final fft = FFT(audioData.length);
    fft.inPlaceFft(complexData);

    // Calculate magnitude spectrum
    final spectrum = _calculateMagnitudeSpectrum(complexData);

    // Find fundamental frequency
    final fundamentalResult = _findFundamentalFrequency(spectrum, sampleRate);
    if (fundamentalResult == null) {
      return TuningResult.failed(
        'No significant frequency found',
        spectrum: spectrum,
      );
    }

    final frequency = fundamentalResult.frequency;
    final amplitude = fundamentalResult.amplitude;

    // Check amplitude threshold
    if (amplitude < config.minAmplitudeThreshold) {
      return TuningResult.failed(
        'Amplitude too low (${amplitude.toStringAsFixed(6)} < ${config.minAmplitudeThreshold})',
        spectrum: spectrum,
      );
    }

    // Check if frequency is in valid range
    if (!_isInFrequencyRange(frequency)) {
      return TuningResult.failed(
        'Frequency outside valid range (${frequency.toStringAsFixed(1)} Hz)',
        spectrum: spectrum,
      );
    }

    // Validate harmonic structure
    final hasHarmonics =
        _validateHarmonicStructure(spectrum, frequency, sampleRate);
    if (!hasHarmonics) {
      return TuningResult.failed(
        'No harmonic structure detected',
        spectrum: spectrum,
      );
    }

    // Check temporal stability
    final isStable = _checkTemporalStability(frequency);

    return TuningResult.success(
      frequency: frequency,
      amplitude: amplitude,
      spectrum: spectrum,
      hasHarmonicStructure: true,
      isStable: isStable,
      guitarStringFreqs: config.guitarStringFreqs,
    );
  }

  /// Calculates the magnitude spectrum from complex FFT data.
  List<double> _calculateMagnitudeSpectrum(Float64x2List complexData) {
    final spectrum = <double>[];
    for (int i = 0; i < complexData.length ~/ 2; i++) {
      final real = complexData[i].x;
      final imag = complexData[i].y;
      final magnitude = math.sqrt(real * real + imag * imag);
      spectrum.add(magnitude);
    }
    return spectrum;
  }

  /// Finds the fundamental frequency from the spectrum.
  _FrequencyResult? _findFundamentalFrequency(
      List<double> spectrum, double sampleRate) {
    double maxMagnitude = 0;
    int maxIndex = 0;

    // Find the peak in the spectrum within our frequency range
    final minBin =
        (config.minFrequency / (sampleRate / 2) * spectrum.length).round();
    final maxBin =
        (config.maxFrequency / (sampleRate / 2) * spectrum.length).round();

    for (int i = math.max(1, minBin);
        i < math.min(spectrum.length, maxBin);
        i++) {
      if (spectrum[i] > maxMagnitude) {
        maxMagnitude = spectrum[i];
        maxIndex = i;
      }
    }

    if (maxMagnitude <= 0) return null;

    // Convert bin index to frequency
    final frequency = (maxIndex * sampleRate) / (2 * spectrum.length);

    return _FrequencyResult(frequency: frequency, amplitude: maxMagnitude);
  }

  /// Checks if a frequency is within the configured range.
  bool _isInFrequencyRange(double frequency) {
    return frequency >= config.minFrequency && frequency <= config.maxFrequency;
  }

  /// Validates that the spectrum contains harmonics of the fundamental frequency.
  bool _validateHarmonicStructure(
      List<double> spectrum, double fundamental, double sampleRate) {
    int detectedHarmonics = 0;
    final binWidth = sampleRate / (2 * spectrum.length);
    final fundamentalBin = (fundamental / binWidth).round();
    final fundamentalAmplitude = spectrum[fundamentalBin];

    // Check for harmonics at 2f, 3f, 4f, 5f
    for (int harmonic = 2; harmonic <= 5; harmonic++) {
      final harmonicFreq = fundamental * harmonic;
      final expectedBin = (harmonicFreq / binWidth).round();

      if (expectedBin >= spectrum.length) break;

      // Check if there's significant energy around the harmonic frequency
      final tolerance =
          (fundamental * config.harmonicTolerance / binWidth).round();
      bool harmonicFound = false;

      for (int i = math.max(0, expectedBin - tolerance);
          i <= math.min(spectrum.length - 1, expectedBin + tolerance);
          i++) {
        // Harmonic should have significant amplitude relative to fundamental
        if (spectrum[i] > fundamentalAmplitude * 0.1) {
          harmonicFound = true;
          break;
        }
      }

      if (harmonicFound) {
        detectedHarmonics++;
      }
    }

    return detectedHarmonics >= config.minHarmonicsRequired;
  }

  /// Checks if a frequency has been stable for the required duration.
  bool _checkTemporalStability(double frequency) {
    final now = DateTime.now();
    final rounded = (frequency * 10).round() / 10; // Round to 0.1 Hz

    _frequencyStabilityTracker[rounded] = now;

    // Clean old entries
    _frequencyStabilityTracker.removeWhere((freq, time) =>
        now.difference(time) > const Duration(milliseconds: 200));

    // Check if this frequency has been stable for the required duration
    final firstDetection = _frequencyStabilityTracker[rounded];
    if (firstDetection != null) {
      return now.difference(firstDetection) >= config.stabilityDuration;
    }

    return false;
  }

  /// Resets the stability tracker.
  /// Call this when starting a new tuning session.
  void resetStabilityTracker() {
    _frequencyStabilityTracker.clear();
  }
}

/// Internal class for storing frequency detection results.
class _FrequencyResult {
  final double frequency;
  final double amplitude;

  _FrequencyResult({required this.frequency, required this.amplitude});
}
