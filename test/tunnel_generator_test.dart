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

  test('fork opens internal walls and recycling restores closed tube', () {
    final generator = TunnelGenerator(seed: 77);
    final junction = generator.path.junctionAt(0);
    final data = generator.createSegmentData(12);
    final start = ((junction.splitStart + 8) / generator.ringSpacing).round();
    generator.fillSegment(data, start);
    int openFaces() {
      var count = 0;
      for (var i = 0; i < data.indices.length; i += 3) {
        if (data.indices[i] == data.indices[i + 1]) count++;
      }
      return count;
    }

    expect(openFaces(), greaterThan(0));
    expect(openFaces(), lessThan(data.indices.length ~/ 3));
    expect(data.junctionRings, isNotEmpty);
    generator.fillUnselectedBranch(data, junction);
    expect(openFaces(), greaterThan(0));
    generator.fillSegment(data, 0);
    expect(openFaces(), 0);
    expect(data.junctionRings, isEmpty);
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
