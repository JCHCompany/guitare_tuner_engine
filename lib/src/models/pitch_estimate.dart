import 'dart:math' as dart_math;

/// Résultat d'estimation de fréquence fondamentale
class PitchEstimate {
  final DateTime timestamp;
  final double? f0Hz; // Fréquence fondamentale en Hz
  final String? note; // Note musicale (ex: "E2", "A2")
  final double? cents; // Écart en cents par rapport à la note
  final double confidence; // Confiance [0-1]
  final bool isVoiced; // Signal contient-il une note ?
  final String algorithm; // "YIN" ou "MPM"

  const PitchEstimate({
    required this.timestamp,
    this.f0Hz,
    this.note,
    this.cents,
    required this.confidence,
    required this.isVoiced,
    required this.algorithm,
  });

  /// Crée une estimation de silence
  static PitchEstimate silence() {
    return PitchEstimate(
      timestamp: DateTime.now(),
      confidence: 0.0,
      isVoiced: false,
      algorithm: 'SILENCE',
    );
  }

  /// Crée une estimation avec fréquence
  static PitchEstimate voiced({
    required double f0Hz,
    required double confidence,
    required String algorithm,
  }) {
    final noteInfo = _frequencyToNote(f0Hz);

    return PitchEstimate(
      timestamp: DateTime.now(),
      f0Hz: f0Hz,
      note: noteInfo.note,
      cents: noteInfo.cents,
      confidence: confidence,
      isVoiced: true,
      algorithm: algorithm,
    );
  }

  @override
  String toString() {
    if (!isVoiced) return 'SILENCE (conf: ${confidence.toStringAsFixed(2)})';
    return '${f0Hz!.toStringAsFixed(1)}Hz → $note ${cents!.toStringAsFixed(0)}¢ ($algorithm, conf: ${confidence.toStringAsFixed(2)})';
  }
}

/// Information de note musicale
class NoteInfo {
  final String note;
  final double cents;

  const NoteInfo({required this.note, required this.cents});
}

/// Convertit une fréquence en note + cents (A4 = 440Hz)
NoteInfo _frequencyToNote(double frequency) {
  // Notes dans une octave
  const List<String> noteNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B'
  ];

  // A4 = 440 Hz = MIDI note 69
  final double midiFloat =
      69 + 12 * (frequency / 440.0).log() / 0.693147180559945; // ln(2)
  final int midiNote = midiFloat.round();
  final double cents = (midiFloat - midiNote) * 100;

  // Calculer octave et note
  final int octave = (midiNote / 12).floor() - 1;
  final int noteIndex = midiNote % 12;
  final String noteName = '${noteNames[noteIndex]}$octave';

  return NoteInfo(note: noteName, cents: cents);
}

extension on double {
  double log() => dart_math.log(this);
}