# Show the saved playback position on Android cold start

When a user reopens DeshPlayer with a paused track, the seek thumb and elapsed-time label should show the saved position on the first frame that has both the position and the track duration. On Android, the thumb can stay at the beginning until the screen turns off and the user wakes it. Reopening the app while it is still in memory can show the correct position immediately.

## Cause

The [mobile control panel](../lib/ui/layouts/mobile/mobile_control_panel.dart) initially builds the bar with zero progress and zero duration. During startup, [PlayerProvider](../lib/services/player_provider.dart) restores the track and position together. In `audio_video_progress_bar` 2.0.3, `ProgressBar.updateRenderObject` sets `progress` before `total`. The progress setter clamps the saved position to the old total of zero. The total setter then recalculates the thumb using that clamped position.

A widget test reproduced this with a saved position of 30 seconds in a two-minute track. The first update left the rendered progress at zero. A second build with the same inputs moved it to 30 seconds. On Android, the provider's resume notification can trigger that second build, which explains why waking the screen can correct the display.

## Fix

In the progress bar dependency's `updateRenderObject`, assign `total` before `progress`. This lets the progress setter clamp against the incoming track duration on the same update. Use a dependency release containing the fix or pin a patched copy through [pubspec.yaml](../pubspec.yaml) so CI and Android builds use the same code.

For a smaller app-side fix scoped to mobile, key the `ProgressBar` by whether its total duration is known, for example `ValueKey(total > Duration.zero)`, using the same `total` passed to the widget. When the duration changes from zero to positive, Flutter creates the bar with the restored values together. The key stays stable during ordinary playback ticks.

## Verification

- Add a widget regression test for the chosen fix. Start at zero position and duration, then supply 30 seconds and two minutes in one update. After one pump, verify that the rendered thumb is at 25% and the elapsed label shows 30 seconds. Checking the widget inputs alone would miss the bug.
- On Android, pause a cached track at a known nonzero position, close the app, open another app, then reopen DeshPlayer. Verify the correct position appears while playback is still paused, before touching the controls or cycling the screen.
- Resume playback and drag the thumb. Verify progress advances from the restored position and seeking still works.
