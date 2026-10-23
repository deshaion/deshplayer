import 'dart:math' as math;

/// Local contrast above the recent sound level, rather than absolute loudness.
class TunnelAudioResponse {
  double _baseline = 0;
  double energy = 0;

  void advance(double seconds, double level) {
    final dt = seconds.clamp(0.0, 0.15);
    final sample = level.clamp(0.0, 1.0);
    final contrast =
        ((sample - _baseline - 0.025) / math.max(0.12, 1 - _baseline)).clamp(
          0.0,
          1.0,
        );
    _baseline += (sample - _baseline) * (1 - math.exp(-dt / 0.8));
    final responseTime = contrast > energy ? 0.045 : 0.22;
    energy += (contrast - energy) * (1 - math.exp(-dt / responseTime));
  }
}
