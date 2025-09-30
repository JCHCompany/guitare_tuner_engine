import 'dart:async';
import 'tuner_config.dart';
import 'tuning_result.dart';
import 'audio_capture_service.dart';
import 'audio_analysis_service.dart';

/// The main engine for guitar tuning with intelligent noise filtering.
///
/// This class provides a high-level API for detecting guitar notes
/// while filtering out non-musical sounds like taps, clicks, and ambient noise.
///
/// Example usage:
/// ```dart
/// // Create tuner with default configuration
/// final tuner = GuitarTunerEngine();
///
/// // Or create with custom configuration for electric guitar
/// final tuner = GuitarTunerEngine(TunerConfig.electric());
///
/// // Listen to tuning results
/// tuner.tuningResults.listen((result) {
///   if (result.isValid) {
///     print('Detected: ${result.frequency}Hz (${result.closestNote})');
///     print('Cents offset: ${result.centsOffset}');
///     print('In tune: ${result.isInTune}');
///   }
/// });
///
/// // Start tuning
/// await tuner.startTuning();
///
/// // Stop when done
/// await tuner.stopTuning();
///
/// // Clean up
/// tuner.dispose();
/// ```
class GuitarTunerEngine {
  /// The configuration used by this tuner engine.
  final TunerConfig config;

  /// Audio capture service.
  late final AudioCaptureService _audioCaptureService;

  /// Audio analysis service.
  late final AudioAnalysisService _audioAnalysisService;

  /// Controller for tuning results.
  StreamController<TuningResult>? _resultsController;

  /// Subscription to audio data.
  StreamSubscription<List<double>>? _audioSubscription;

  /// Creates a new guitar tuner engine with the given configuration.
  ///
  /// If no configuration is provided, uses default settings suitable
  /// for most acoustic and electric guitars.
  GuitarTunerEngine([TunerConfig? config])
      : config = config ?? const TunerConfig() {
    _audioCaptureService = AudioCaptureService(this.config);
    _audioAnalysisService = AudioAnalysisService(this.config);
  }

  /// Stream of tuning results.
  ///
  /// Listen to this stream to receive real-time tuning analysis.
  /// Results are emitted whenever audio is analyzed, regardless of
  /// whether a valid note was detected.
  Stream<TuningResult> get tuningResults =>
      _resultsController?.stream ?? const Stream.empty();

  /// Whether the tuner is currently active and listening for audio.
  bool get isActive => _audioCaptureService.isRecording;

  /// Starts the tuning process.
  ///
  /// This will:
  /// 1. Request microphone permissions if needed
  /// 2. Start audio capture from the microphone
  /// 3. Begin analyzing audio and emitting results
  ///
  /// Returns true if tuning started successfully, false otherwise.
  /// Common reasons for failure include missing microphone permissions
  /// or hardware issues.
  Future<bool> startTuning() async {
    if (isActive) {
      return true; // Already active
    }

    try {
      // Reset analysis state
      _audioAnalysisService.resetStabilityTracker();

      // Create results stream
      _resultsController = StreamController<TuningResult>.broadcast();

      // Start audio capture
      final success = await _audioCaptureService.startRecording();
      if (!success) {
        await _resultsController?.close();
        _resultsController = null;
        return false;
      }

      // Listen to audio data and analyze it
      _audioSubscription = _audioCaptureService.audioStream.listen(
        _analyzeAudioData,
        onError: (error) {
          // Emit error result and stop
          _resultsController
              ?.add(TuningResult.failed('Audio capture error: $error'));
          stopTuning();
        },
      );

      return true;
    } catch (e) {
      await _resultsController?.close();
      _resultsController = null;
      return false;
    }
  }

  /// Stops the tuning process.
  ///
  /// This will stop audio capture and analysis. No more results
  /// will be emitted until [startTuning] is called again.
  Future<void> stopTuning() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    await _audioCaptureService.stopRecording();

    await _resultsController?.close();
    _resultsController = null;
  }

  /// Processes incoming audio data and emits tuning results.
  void _analyzeAudioData(List<double> audioData) {
    final result = _audioAnalysisService.analyzeAudioData(
      audioData,
      config.sampleRate.toDouble(),
    );

    _resultsController?.add(result);
  }

  /// Checks if the app has microphone permission.
  Future<bool> hasPermission() async {
    return _audioCaptureService.hasPermission();
  }

  /// Requests microphone permission from the user.
  Future<bool> requestPermissions() async {
    return _audioCaptureService.requestPermissions();
  }

  /// Disposes of resources used by this tuner engine.
  ///
  /// Call this when you no longer need the tuner to free up resources.
  /// After calling dispose, this tuner instance should not be used anymore.
  void dispose() {
    stopTuning();
    _audioCaptureService.dispose();
  }
}
