class CloudFileNotFoundException implements Exception {
  final String message;
  CloudFileNotFoundException([this.message = 'File not found in cloud storage (404).']);

  @override
  String toString() => 'CloudFileNotFoundException: $message';
}

class TrackRemovedException implements Exception {
  final String message;
  TrackRemovedException([this.message = 'Track was removed from cloud and local storage.']);

  @override
  String toString() => message;
}
