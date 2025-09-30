# Changelog

All notable changes to the pitch_detection package will be documented in this file.

## [1.0.0] - 2025-09-30

### Added
- Initial release of the pitch_detection package
- YIN algorithm implementation for pitch detection
- MPM (McLeod Pitch Method) algorithm implementation
- PitchEstimationService with advanced post-processing
- Anti-octave protection and outlier detection
- Median filtering for stability
- Real-time performance optimization
- Complete API documentation
- Example Flutter app demonstrating usage
- Support for musical note conversion with cents deviation
- Confidence scoring for detection reliability

### Features
- Dual algorithm approach (YIN + MPM) for robust detection
- Musical instrument optimization (70-1000 Hz range)
- Low-latency processing suitable for real-time applications
- Comprehensive post-processing pipeline for stable results
- Easy integration with Flutter audio packages

### Dependencies
- fftea: ^1.5.0+1 (for FFT operations in MPM algorithm)
- flutter: ">=3.22.0"

### Performance
- Optimized for 44.1 kHz sample rate
- Recommended frame sizes: 2048-4096 samples
- Target latency: <150ms for real-time applications