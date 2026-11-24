import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:deshplayer/services/desh_audio_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestAudioSession implements AudioSession {
  final deviceChanges = StreamController<AudioDevicesChangedEvent>.broadcast();
  final outputs = <AudioDevice>{};

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {}

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      const Stream.empty();

  @override
  Stream<void> get becomingNoisyEventStream => const Stream.empty();

  @override
  Stream<AudioDevicesChangedEvent> get devicesChangedEventStream =>
      deviceChanges.stream;

  @override
  Future<Set<AudioDevice>> getDevices({
    bool includeInputs = true,
    bool includeOutputs = true,
  }) async => Set.of(outputs);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAudioHandler extends DeshAudioHandler {
  _TestAudioHandler(_TestAudioSession session) : super(audioSession: session);

  int playRequests = 0;

  @override
  Future<void> play() async {
    playRequests++;
    await super.play();
  }
}

void main() {
  const android = TargetPlatformVariant({TargetPlatform.android});
  final headphones = AudioDevice(
    id: 'headphones',
    name: 'Bluetooth headphones',
    isInput: false,
    isOutput: true,
    // ignore: experimental_member_use
    type: AudioDeviceType.bluetoothA2dp,
  );
  late _TestAudioSession session;
  late _TestAudioHandler handler;

  setUp(() {
    session = _TestAudioSession()..outputs.add(headphones);
    addTearDown(session.deviceChanges.close);
  });

  testWidgets('keeps playback paused when Bluetooth disconnects', (
    tester,
  ) async {
    handler = _TestAudioHandler(session);
    final click = handler.click();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 630));
    expect(handler.playRequests, 0);

    session.outputs.remove(headphones);
    session.deviceChanges.add(
      AudioDevicesChangedEvent(devicesRemoved: {headphones}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 370));
    await click;
    expect(handler.playRequests, 0);
  }, variant: android);

  testWidgets('resumes from a media button when Bluetooth stays connected', (
    tester,
  ) async {
    handler = _TestAudioHandler(session);
    final click = handler.click();
    await tester.pump();
    expect(handler.playRequests, 0);
    await tester.pump(const Duration(seconds: 1));
    await click;
    expect(handler.playRequests, 1);
  }, variant: android);

  testWidgets('direct Play works immediately and replaces a pending resume', (
    tester,
  ) async {
    handler = _TestAudioHandler(session);
    final click = handler.click();
    await tester.pump();
    await handler.play();
    expect(handler.playRequests, 1);
    await tester.pump(const Duration(seconds: 1));
    await click;
    expect(handler.playRequests, 1);
  }, variant: android);

  testWidgets('media button resumes immediately without Bluetooth', (
    tester,
  ) async {
    session.outputs.clear();
    handler = _TestAudioHandler(session);
    await handler.click();
    expect(handler.playRequests, 1);
  }, variant: android);
}
