/// A Flutter package for intelligent guitar tuning with advanced noise filtering.
///
/// This package provides a complete solution for detecting guitar notes
/// while filtering out non-musical sounds. It uses FFT analysis combined
/// with harmonic detection and temporal stability checking to ensure
/// accurate note detection.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:guitar_tuner_engine/guitar_tuner_engine.dart';
///
/// // Create a tuner
/// final tuner = GuitarTunerEngine();
///
/// // Listen for results
/// tuner.tuningResults.listen((result) {
///   if (result.isValid) {
///     print('Note: ${result.closestNote} (${result.frequency}Hz)');
///   }
/// });
///
/// // Start tuning
/// await tuner.startTuning();
/// ```
///
/// ## Configuration
///
/// The package provides several pre-configured setups:
///
/// ```dart
/// // For acoustic guitar
/// final acousticTuner = GuitarTunerEngine(TunerConfig.acoustic());
///
/// // For electric guitar
/// final electricTuner = GuitarTunerEngine(TunerConfig.electric());
///
/// // For bass guitar
/// final bassTuner = GuitarTunerEngine(TunerConfig.bass());
///
/// // For noisy environments
/// final noisyTuner = GuitarTunerEngine(TunerConfig.noisyEnvironment());
/// ```
///
/// You can also create custom configurations:
///
/// ```dart
/// final customConfig = TunerConfig(
///   minAmplitudeThreshold: 0.002,
///   minHarmonicsRequired: 3,
///   stabilityDuration: Duration(milliseconds: 100),
/// );
/// final customTuner = GuitarTunerEngine(customConfig);
/// ```
library guitar_tuner_engine;

export 'src/guitar_tuner_engine.dart';
export 'src/tuner_config.dart';
export 'src/tuning_result.dart';
