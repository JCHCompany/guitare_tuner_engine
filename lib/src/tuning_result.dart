import 'dart:math' as math;

/// Result of tuning detection analysis.
class TuningResult {
  /// Whether a valid musical note was detected.
  final bool isValid;

  /// The detected fundamental frequency in Hz.
  /// Null if no valid frequency was detected.
  final double? frequency;

  /// The amplitude of the detected signal (0.0 to 1.0+).
  final double amplitude;

  /// The frequency spectrum data for visualization.
  final List<double> spectrum;

  /// Whether the detected frequency has a harmonic structure.
  final bool hasHarmonicStructure;

  /// Whether the frequency has been stable for the required duration.
  final bool isStable;

  /// The closest guitar string note to the detected frequency.
  /// Null if no frequency was detected.
  final String? closestNote;

  /// The target frequency for the closest note in Hz.
  /// Null if no frequency was detected.
  final double? targetFrequency;

  /// The offset from the target frequency in cents.
  /// Positive values indicate the detected frequency is sharp (too high).
  /// Negative values indicate the detected frequency is flat (too low).
  /// Null if no frequency was detected.
  final double? centsOffset;

  /// Whether the detected frequency is considered "in tune".
  /// True if the cents offset is within ±5 cents.
  final bool isInTune;

  /// Reason why the detection failed (if isValid is false).
  final String? failureReason;

  /// Timestamp when this result was generated.
  final DateTime timestamp;

  /// Creates a new tuning result.
  TuningResult({
    required this.isValid,
    this.frequency,
    this.amplitude = 0.0,
    this.spectrum = const [],
    this.hasHarmonicStructure = false,
    this.isStable = false,
    this.closestNote,
    this.targetFrequency,
    this.centsOffset,
    this.isInTune = false,
    this.failureReason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates a failed result with a reason.
  TuningResult.failed(
    String reason, {
    List<double> spectrum = const [],
    double amplitude = 0.0,
    DateTime? timestamp,
  }) : this(
          isValid: false,
          spectrum: spectrum,
          amplitude: amplitude,
          failureReason: reason,
          timestamp: timestamp,
        );

  /// Creates a successful result from detection data.
  factory TuningResult.success({
    required double frequency,
    required double amplitude,
    required List<double> spectrum,
    required bool hasHarmonicStructure,
    required bool isStable,
    required Map<String, double> guitarStringFreqs,
    DateTime? timestamp,
  }) {
    // Find closest note
    String? closestNote;
    double? targetFrequency;
    double minDifference = double.infinity;

    for (final entry in guitarStringFreqs.entries) {
      final difference = (frequency - entry.value).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closestNote = entry.key;
        targetFrequency = entry.value;
      }
    }

    // Calculate cents offset
    double? centsOffset;
    if (targetFrequency != null) {
      centsOffset = 1200 * math.log(frequency / targetFrequency) / math.ln2;
    }

    // Check if in tune (within 5 cents)
    final isInTune = centsOffset != null && centsOffset.abs() <= 5.0;

    return TuningResult(
      isValid: isStable, // Only valid if stable
      frequency: frequency,
      amplitude: amplitude,
      spectrum: spectrum,
      hasHarmonicStructure: hasHarmonicStructure,
      isStable: isStable,
      closestNote: closestNote,
      targetFrequency: targetFrequency,
      centsOffset: centsOffset,
      isInTune: isInTune,
      failureReason: isStable ? null : 'Frequency not stable enough',
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    if (!isValid) {
      return 'TuningResult(invalid: $failureReason)';
    }

    final freqStr = frequency?.toStringAsFixed(1) ?? 'null';
    final noteStr = closestNote ?? 'unknown';
    final centsStr = centsOffset?.toStringAsFixed(1) ?? 'null';
    final tuneStr = isInTune ? 'in tune' : 'out of tune';

    return 'TuningResult($freqStr Hz, $noteStr, ${centsStr}¢, $tuneStr)';
  }
}
