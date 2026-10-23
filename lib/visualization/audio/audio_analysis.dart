import 'dart:math' as math;

import 'package:flutter_soloud/flutter_soloud.dart';

/// Mutable normalized feature frame reused for the lifetime of the analyzer.
class AudioFeatures {
  double amplitude = 0;
  double bass = 0;
  double mids = 0;
  double treble = 0;
  bool beat = false;
}

/// Converts SoLoud visualization samples into stable normalized features.
class AudioAnalysis {
  AudioAnalysis({this.analysisRate = 30})
    : _audioData = AudioData(GetSamplesKind.linear);

  final double analysisRate;
  final AudioData _audioData;
  final AudioFeatures features = AudioFeatures();
  double _accumulator = 0;
  double _bassAverage = 0;
  double _beatCooldown = 0;

  AudioFeatures update(double deltaSeconds, {required bool isPlaying}) {
    features.beat = false;
    _beatCooldown = math.max(0, _beatCooldown - deltaSeconds);
    _accumulator += deltaSeconds;
    final interval = 1 / analysisRate;
    if (_accumulator < interval) return features;
    final elapsed = _accumulator.clamp(interval, 0.15);
    _accumulator = 0;

    var amplitude = 0.0;
    var bass = 0.0;
    var mids = 0.0;
    var treble = 0.0;
    if (isPlaying && SoLoud.instance.isInitialized) {
      try {
        _audioData.updateSamples();
        final samples = _audioData.getAudioData();
        if (samples.length >= 256) {
          bass = _bandEnergy(samples, 1, 13, 4.8);
          mids = _bandEnergy(samples, 13, 65, 5.8);
          treble = _bandEnergy(samples, 65, 201, 7.2);
        }
        if (samples.length >= 512) {
          var squareSum = 0.0;
          for (var index = 256; index < 512; index++) {
            final value = samples[index];
            squareSum += value * value;
          }
          amplitude = (math.sqrt(squareSum / 256) * 2.6).clamp(0, 1);
        } else {
          amplitude = (bass * 0.45 + mids * 0.4 + treble * 0.15).clamp(0, 1);
        }
      } catch (_) {
        // Audio can disappear while a source is being replaced. Envelopes
        // release naturally instead of injecting fallback noise.
      }
    }

    _bassAverage = _smooth(_bassAverage, bass, elapsed, 0.08, 0.45);
    final onsetThreshold = math.max(0.22, _bassAverage * 1.38);
    if (_beatCooldown <= 0 && bass > onsetThreshold) {
      features.beat = true;
      _beatCooldown = 0.22;
    }

    features.amplitude = _smooth(
      features.amplitude,
      amplitude,
      elapsed,
      0.055,
      0.3,
    );
    features.bass = _smooth(features.bass, bass, elapsed, 0.045, 0.28);
    features.mids = _smooth(features.mids, mids, elapsed, 0.07, 0.35);
    features.treble = _smooth(features.treble, treble, elapsed, 0.025, 0.2);
    return features;
  }

  static double _bandEnergy(
    List<double> samples,
    int start,
    int end,
    double gain,
  ) {
    var sum = 0.0;
    for (var index = start; index < end; index++) {
      final magnitude = samples[index].abs();
      sum += magnitude * magnitude;
    }
    return (math.sqrt(sum / (end - start)) * gain).clamp(0, 1);
  }

  static double _smooth(
    double current,
    double target,
    double seconds,
    double attack,
    double release,
  ) {
    final timeConstant = target > current ? attack : release;
    final alpha = 1 - math.exp(-seconds / timeConstant);
    return current + (target - current) * alpha;
  }

  void dispose() => _audioData.dispose();
}
