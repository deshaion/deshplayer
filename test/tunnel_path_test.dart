import 'package:flutter_test/flutter_test.dart';
import 'package:deshplayer/visualization/tunnel/tunnel_path.dart';

void main() {
  test('tunnel path is deterministic for a seed', () {
    final first = const TunnelPath(seed: 42).sample(13.75);
    final second = const TunnelPath(seed: 42).sample(13.75);

    expect(first.position.x, second.position.x);
    expect(first.position.y, second.position.y);
    expect(first.tangent.x, second.tangent.x);
    expect(first.tangent.y, second.tangent.y);
  });

  test('infinite spline remains smooth across a control-point boundary', () {
    const path = TunnelPath(seed: 91);
    final before = path.sample(path.controlPointSpacing - 0.0001);
    final after = path.sample(path.controlPointSpacing + 0.0001);

    expect((after.position - before.position).length, lessThan(0.001));
    expect(after.tangent.dot(before.tangent), greaterThan(0.999999));
  });

  test('distant samples reconstruct without retained path history', () {
    const distance = 100000.25;
    final first = const TunnelPath(seed: 7).sample(distance);
    final second = const TunnelPath(seed: 7).sample(distance);

    expect(first.position.x, second.position.x);
    expect(first.position.y, second.position.y);
    expect(first.position.z, distance);
  });
}
