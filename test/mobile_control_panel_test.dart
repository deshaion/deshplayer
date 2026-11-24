import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:deshplayer/models/settings.dart';
import 'package:deshplayer/models/track.dart';
import 'package:deshplayer/services/player_provider.dart';
import 'package:deshplayer/ui/layouts/mobile/mobile_control_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('paints the restored position on the first frame with duration', (
    tester,
  ) async {
    const savedPosition = Duration(seconds: 30);
    const trackDuration = Duration(minutes: 2);
    const barHeight = 4.0;
    const thumbRadius = 6.0;
    const referenceKey = ValueKey('reference');
    final player = _TestPlayer();
    addTearDown(player.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerProvider>.value(
        value: player,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MobileControlPanel(),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: ProgressBar(
                    key: referenceKey,
                    progress: savedPosition,
                    total: trackDuration,
                    barHeight: barHeight,
                    thumbRadius: thumbRadius,
                    timeLabelTextStyle: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final bar = find.descendant(
      of: find.byType(MobileControlPanel),
      matching: find.byType(ProgressBar),
    );
    Offset thumbCenter(double fraction) => Offset(
      barHeight / 2 + (tester.getSize(bar).width - barHeight) * fraction,
      thumbRadius,
    );

    void expectThumbAt(double fraction) {
      final center = thumbCenter(fraction);
      expect(
        bar,
        paints..circle(x: center.dx, y: center.dy, radius: thumbRadius),
      );
    }

    expectThumbAt(0);

    player.currentTrack = Track(
      id: 'track',
      cloudPath: 'track.mp3',
      duration: trackDuration,
    );
    player.setPosition(savedPosition);
    await tester.pump();

    expectThumbAt(0.25);
    // The times are canvas-painted. Compare the rendered bar and labels with
    // a reference that had both values on its first build.
    final reference = tester.renderObject<RenderBox>(find.byKey(referenceKey));
    final layer = reference.debugLayer! as OffsetLayer;
    final referenceImage = layer.toImageSync(Offset.zero & reference.size);
    addTearDown(referenceImage.dispose);
    await expectLater(bar, matchesReferenceImage(referenceImage));

    final restoredBar = tester.renderObject<RenderBox>(bar);
    player.isPlaying = true;
    player.setPosition(const Duration(seconds: 36));
    await tester.pump();
    expect(tester.renderObject<RenderBox>(bar), same(restoredBar));
    expectThumbAt(0.3);

    final bounds = tester.getRect(bar);
    final thumb = bounds.topLeft + thumbCenter(0.3);
    await tester.dragFrom(thumb, Offset(bounds.center.dx - thumb.dx, 0));
    expect(player.lastSeek, const Duration(minutes: 1));
  });
}

class _TestPlayer extends ChangeNotifier implements PlayerProvider {
  @override
  Track? currentTrack;

  @override
  final settings = AppSettings();

  @override
  bool isPlaying = false;

  @override
  Duration position = Duration.zero;

  @override
  Duration get duration => Duration.zero;

  Duration? lastSeek;

  void setPosition(Duration value) {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
