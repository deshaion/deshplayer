import 'package:deshplayer/visualization/tunnel/tunnel_audio_response.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sustained high levels stop driving continuous highlights', () {
    final response = TunnelAudioResponse();
    for (var frame = 0; frame < 300; frame++) {
      response.advance(1 / 60, frame.isEven ? 0.91 : 0.9);
    }
    expect(response.energy, lessThan(0.02));
    for (var frame = 0; frame < 6; frame++) {
      response.advance(1 / 60, 1);
    }
    expect(response.energy, greaterThan(0.25));
    for (var frame = 0; frame < 300; frame++) {
      response.advance(1 / 60, 1);
    }
    expect(response.energy, lessThan(0.02));
  });

  test('silence releases highlights', () {
    final response = TunnelAudioResponse();
    response.advance(0.1, 0.8);
    expect(response.energy, greaterThan(0));
    for (var frame = 0; frame < 120; frame++) {
      response.advance(1 / 60, 0);
    }
    expect(response.energy, lessThan(0.001));
  });
}
