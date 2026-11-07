import 'track.dart';

/// A queued occurrence, including the playlist it was added from.
class QueueEntry {
  final Track track;
  final String? playlistId;

  const QueueEntry(this.track, {this.playlistId});

  Map<String, dynamic> toJson() => {
    'trackId': track.id,
    'playlistId': playlistId,
  };

  static QueueEntry? fromJson(
    Map<String, dynamic> json,
    Track? Function(String) getTrack,
  ) {
    final track = getTrack(json['trackId'] as String);
    return track == null
        ? null
        : QueueEntry(track, playlistId: json['playlistId'] as String?);
  }
}
