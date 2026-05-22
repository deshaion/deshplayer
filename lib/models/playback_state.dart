import 'package:hive/hive.dart';

part 'playback_state.g.dart';

@HiveType(typeId: 2)
class PlaybackState {
  @HiveField(0)
  final String playlistId;

  @HiveField(1)
  String? currentTrackId;

  @HiveField(2)
  Duration position;

  PlaybackState({
    required this.playlistId,
    this.currentTrackId,
    this.position = Duration.zero,
  });
}
