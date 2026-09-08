import 'dart:math' as math;

import 'package:deshplayer/visualization/tunnel/tunnel_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('organic cave geometry is deterministic', () {
    final firstGenerator = TunnelGenerator(seed: 1234);
    final secondGenerator = TunnelGenerator(seed: 1234);
    final first = firstGenerator.createSegmentData(4);
    final second = secondGenerator.createSegmentData(4);

    firstGenerator.fillSegment(first, 32);
    secondGenerator.fillSegment(second, 32);

    expect(first.basePositions, orderedEquals(second.basePositions));
    expect(first.radialDirections, orderedEquals(second.radialDirections));
  });

  test('ring radii vary organically while remaining bounded', () {
    final generator = TunnelGenerator(seed: 77);
    final data = generator.createSegmentData(3);
    generator.fillSegment(data, 10);
    final center = generator.path.sample(10 * generator.ringSpacing).position;
    var minimum = double.infinity;
    var maximum = 0.0;

    for (var side = 0; side < generator.verticesPerRing; side++) {
      final offset = side * 3;
      final dx = data.basePositions[offset] - center.x;
      final dy = data.basePositions[offset + 1] - center.y;
      final dz = data.basePositions[offset + 2] - center.z;
      final measured = math.sqrt(dx * dx + dy * dy + dz * dz);
      minimum = math.min(minimum, measured);
      maximum = math.max(maximum, measured);
    }

    expect(maximum - minimum, greaterThan(0.5));
    expect(minimum, greaterThan(generator.radius - 1.3));
    expect(maximum, lessThan(generator.radius + 1.3));
  });
}
