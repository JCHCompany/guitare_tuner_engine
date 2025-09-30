import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'tuner_config.dart';

/// Service for capturing audio from the device microphone.
/// 
/// This service handles microphone permissions, audio recording,
/// and provides a stream of audio samples for analysis.
class AudioCaptureService {
  /// The configuration used for audio capture.
  final TunerConfig config;

  /// The audio recorder instance.
  final AudioRecorder _recorder = AudioRecorder();

  /// Subscription to the audio stream.
  StreamSubscription<Uint8List>? _recordingSubscription;

  /// Controller for the audio data stream.
  StreamController<List<double>>? _audioStreamController;
  
  /// Buffer for accumulating audio samples.
  final List<int> _audioBuffer = [];

  /// Creates a new audio capture service with the given configuration.
  AudioCaptureService(this.config);

  /// Stream of normalized audio samples (-1.0 to 1.0).
  /// Each list contains exactly [config.bufferSize] samples.
  Stream<List<double>> get audioStream => 
      _audioStreamController?.stream ?? const Stream.empty();

  /// Whether audio recording is currently active.
  bool get isRecording => _recordingSubscription != null;

  /// Requests microphone permission from the user.
  /// 
  /// Returns true if permission is granted, false otherwise.
  Future<bool> requestPermissions() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

  /// Checks if the app has microphone permission.
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status == PermissionStatus.granted;
  }

  /// Starts audio recording.
  /// 
  /// Returns true if recording started successfully, false otherwise.
  /// Automatically requests permissions if not already granted.
  Future<bool> startRecording() async {
    try {
      // Check permissions
      if (!await hasPermission() && !await requestPermissions()) {
        return false;
      }

      // Check if microphone is available
      if (!await _recorder.hasPermission()) {
        return false;
      }

      _audioStreamController = StreamController<List<double>>.broadcast();

      // Start recording with specific configuration
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: config.sampleRate,
          numChannels: 1, // Mono
          androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.mic,
          ),
        ),
      );

      _recordingSubscription = stream.listen(
        _onAudioData,
        onError: (error) {
          // Stop recording on error
          stopRecording();
        },
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Processes incoming audio data from the recorder.
  void _onAudioData(Uint8List data) {
    // Convert bytes to int16 samples
    final samples = <int>[];
    for (int i = 0; i < data.length; i += 2) {
      if (i + 1 < data.length) {
        final sample = (data[i + 1] << 8) | data[i];
        // Convert from unsigned to signed 16-bit
        final signedSample = sample > 32767 ? sample - 65536 : sample;
        samples.add(signedSample);
      }
    }

    _audioBuffer.addAll(samples);

    // Process buffer when we have enough samples
    if (_audioBuffer.length >= config.bufferSize) {
      final processBuffer = _audioBuffer.take(config.bufferSize).toList();
      _audioBuffer.removeRange(0, config.bufferSize);

      // Convert to normalized double values (-1.0 to 1.0)
      final normalizedSamples = processBuffer
          .map((sample) => sample / 32768.0)
          .toList();

      _audioStreamController?.add(normalizedSamples);
    }
  }

  /// Stops audio recording.
  Future<void> stopRecording() async {
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    
    await _recorder.stop();
    
    await _audioStreamController?.close();
    _audioStreamController = null;
    
    _audioBuffer.clear();
  }

  /// Disposes of resources used by this service.
  /// Call this when you no longer need the service.
  void dispose() {
    stopRecording();
    _recorder.dispose();
  }
}