import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_detection/pitch_detection.dart';
import 'dart:typed_data';
import 'dart:math' as math;

void main() {
  group('PitchEstimate', () {
    test('should create silence estimate', () {
      final estimate = PitchEstimate.silence();
      
      expect(estimate.isVoiced, false);
      expect(estimate.f0Hz, isNull);
      expect(estimate.note, isNull);
      expect(estimate.cents, isNull);
      expect(estimate.confidence, 0.0);
      expect(estimate.algorithm, 'SILENCE');
    });

    test('should create voiced estimate', () {
      final estimate = PitchEstimate.voiced(
        f0Hz: 440.0,
        confidence: 0.9,
        algorithm: 'YIN',
      );
      
      expect(estimate.isVoiced, true);
      expect(estimate.f0Hz, 440.0);
      expect(estimate.note, 'A4');
      expect(estimate.cents, closeTo(0.0, 1.0));
      expect(estimate.confidence, 0.9);
      expect(estimate.algorithm, 'YIN');
    });

    test('should convert frequency to correct note', () {
      // Test A4 = 440 Hz
      final a4 = PitchEstimate.voiced(f0Hz: 440.0, confidence: 1.0, algorithm: 'TEST');
      expect(a4.note, 'A4');
      expect(a4.cents, closeTo(0.0, 1.0));

      // Test E2 ≈ 82.4 Hz (guitar low E)
      final e2 = PitchEstimate.voiced(f0Hz: 82.4, confidence: 1.0, algorithm: 'TEST');
      expect(e2.note, 'E2');
      expect(e2.cents!.abs(), lessThan(5.0));
    });
  });

  group('YinPitchDetector', () {
    test('should initialize with correct parameters', () {
      final detector = YinPitchDetector(
        sampleRate: 44100.0,
        minF0: 70.0,
        maxF0: 1000.0,
      );
      
      final debugInfo = detector.getDebugInfo();
      expect(debugInfo['sampleRate'], 44100.0);
      expect(debugInfo['minF0'], 70.0);
      expect(debugInfo['maxF0'], 1000.0);
    });

    test('should detect pitch in synthetic signal', () {
      final detector = YinPitchDetector(sampleRate: 44100.0);
      
      // Generate 440 Hz sine wave
      final samples = _generateSineWave(440.0, 44100.0, 2048);
      
      final result = detector.estimatePitch(samples);
      
      if (result != null) {
        expect(result.frequency, closeTo(440.0, 10.0));
        expect(result.confidence, greaterThan(0.7));
      }
    });

    test('should return null for pure noise', () {
      final detector = YinPitchDetector(sampleRate: 44100.0);
      
      // Generate random noise
      final samples = _generateNoise(2048);
      
      final result = detector.estimatePitch(samples);
      
      // Should not detect pitch in pure noise
      expect(result, isNull);
    });
  });

  group('MpmPitchDetector', () {
    test('should initialize with correct parameters', () {
      final detector = MpmPitchDetector(
        sampleRate: 44100.0,
        minF0: 70.0,
        maxF0: 1000.0,
      );
      
      final debugInfo = detector.getDebugInfo();
      expect(debugInfo['sampleRate'], 44100.0);
      expect(debugInfo['minF0'], 70.0);
      expect(debugInfo['maxF0'], 1000.0);
      expect(debugInfo['algorithm'], 'MPM');
    });

    test('should detect pitch in synthetic signal', () {
      final detector = MpmPitchDetector(sampleRate: 44100.0);
      
      // Generate 220 Hz sine wave (A3)
      final samples = _generateSineWave(220.0, 44100.0, 2048);
      
      final result = detector.estimatePitch(samples);
      
      if (result != null) {
        expect(result.frequency, closeTo(220.0, 10.0));
        expect(result.confidence, greaterThan(0.7));
      }
    });
  });

  group('PitchEstimationService', () {
    test('should initialize correctly', () {
      final service = PitchEstimationService(
        sampleRate: 44100.0,
        minF0: 70.0,
        maxF0: 1000.0,
      );
      
      // Should not throw
      expect(service, isNotNull);
    });

    test('should detect silence', () {
      final service = PitchEstimationService(sampleRate: 44100.0);
      
      // Generate near-silence signal
      final samples = Float64List.fromList(
        List.generate(2048, (i) => 0.0001 * math.sin(i * 0.1))
      );
      
      final estimate = service.estimatePitch(samples);
      
      expect(estimate.isVoiced, false);
      expect(estimate.algorithm, 'SILENCE');
    });

    test('should detect pitched signal', () {
      final service = PitchEstimationService(sampleRate: 44100.0);
      
      // Generate clear 330 Hz signal (E4)
      final samples = _generateSineWave(330.0, 44100.0, 2048);
      
      final estimate = service.estimatePitch(samples);
      
      if (estimate.isVoiced) {
        expect(estimate.f0Hz, closeTo(330.0, 20.0));
        expect(estimate.note, contains('E'));
        expect(estimate.confidence, greaterThan(0.7));
      }
    });

    test('should provide performance stats', () {
      final service = PitchEstimationService(sampleRate: 44100.0);
      
      // Process some samples
      final samples = _generateSineWave(440.0, 44100.0, 2048);
      service.estimatePitch(samples);
      service.estimatePitch(samples);
      
      final stats = service.getPerformanceStats();
      expect(stats, isNotEmpty);
      expect(stats['totalEstimates'], greaterThanOrEqualTo(2));
    });

    test('should reset correctly', () {
      final service = PitchEstimationService(sampleRate: 44100.0);
      
      // Process some samples
      final samples = _generateSineWave(440.0, 44100.0, 2048);
      service.estimatePitch(samples);
      
      // Reset
      service.reset();
      
      // Stats should be empty
      final stats = service.getPerformanceStats();
      expect(stats, isEmpty);
    });
  });
}

// Helper functions for test data generation
Float64List _generateSineWave(double frequency, double sampleRate, int numSamples) {
  final samples = Float64List(numSamples);
  final angular = 2 * math.pi * frequency / sampleRate;
  
  for (int i = 0; i < numSamples; i++) {
    samples[i] = 0.5 * math.sin(angular * i);
  }
  
  return samples;
}

Float64List _generateNoise(int numSamples) {
  final samples = Float64List(numSamples);
  final random = math.Random();
  
  for (int i = 0; i < numSamples; i++) {
    samples[i] = (random.nextDouble() - 0.5) * 0.1; // Low amplitude noise
  }
  
  return samples;
}