import 'dart:convert';
import 'dart:io';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:logging/logging.dart';
import '../models/track.dart';
import 'cloud_provider.dart';
import 'hive_storage_service.dart';

class MetadataService {
  final _log = Logger('MetadataService');
  static const String metadataFileName = 'metadata.json';

  // Read metadata.json from cloud path
  Future<Map<String, dynamic>?> getCloudMetadata(
    CloudProvider provider,
    String dirPath,
    Directory localCacheDir,
  ) async {
    try {
      final cloudMetadataPath =
          '${dirPath.endsWith('/') ? dirPath : '$dirPath/'}$metadataFileName';
      final downloadUrl = await provider.getDownloadUrl(cloudMetadataPath);

      if (downloadUrl != null) {
        final request = await HttpClient().getUrl(Uri.parse(downloadUrl));
        final response = await request.close();

        if (response.statusCode == 200) {
          final content = await response.transform(utf8.decoder).join();
          return json.decode(content);
        }
      }
    } catch (e) {
      _log.fine('No existing metadata.json found or failed to load: $e');
    }
    return null;
  }

  Future<void> updateMetadataInCloud(
    CloudProvider provider,
    String cloudFilePath,
    Track track,
    Directory localCacheDir,
  ) async {
    try {
      final schemeIdx = cloudFilePath.indexOf('://');
      if (schemeIdx == -1) return;
      final actualPath = cloudFilePath.substring(schemeIdx + 3);
      final dirPath = actualPath.substring(0, actualPath.lastIndexOf('/'));

      final cloudMetadataPath =
          '${dirPath.endsWith('/') ? dirPath : '$dirPath/'}$metadataFileName';

      Map<String, dynamic> metadata = {};
      final existingMetadata = await getCloudMetadata(
        provider,
        dirPath,
        localCacheDir,
      );
      final fileName = actualPath.split('/').last;
      final providerPrefix = cloudFilePath.substring(0, schemeIdx + 3);

      if (existingMetadata != null) {
        metadata = existingMetadata;

        final hive = HiveStorageService();
        final allTracks = hive.getAllTracks();

        final Map<String, List<Track>> tracksByCloudPath = {};
        for (final t in allTracks) {
          tracksByCloudPath.putIfAbsent(t.cloudPath, () => []).add(t);
        }

        for (final entry in existingMetadata.entries) {
          final currentFileName = entry.key;
          final entryData = entry.value;

          final expectedCloudPath =
              '$providerPrefix${dirPath.endsWith('/') ? dirPath : '$dirPath/'}$currentFileName';
          final matchingTracks = tracksByCloudPath[expectedCloudPath] ?? [];
          for (final t in matchingTracks) {
            if (t.artist == null || t.duration.inSeconds == 0) {
              t.artist = entryData['artist'];
              t.title = entryData['title'];
              t.duration = Duration(milliseconds: entryData['durationMs']);
              await hive.saveTrack(t);

              if (t.id == track.id) {
                track.artist = t.artist;
                track.title = t.title;
                track.duration = t.duration;
              }
            }
          }
        }
      }

      final isCurrentTrackPopulated =
          track.artist != null &&
          track.artist != 'Unknown Artist' &&
          track.title != null &&
          track.title != 'Unknown Track' &&
          track.duration.inSeconds > 0;
      if (metadata.containsKey(fileName) && isCurrentTrackPopulated) {
        _log.info(
          'Current track is already populated and exists in cloud metadata. No reason to upload.',
        );
        return;
      }

      if (track.localCachePath == null ||
          !File(track.localCachePath!).existsSync()) {
        _log.warning('Cannot read tags, file missing: ${track.localCachePath}');
        return;
      }

      final tagFile = await TagLibFile.openAsync(track.localCachePath!);
      if (tagFile == null) {
        _log.info('No audio tags found in file: ${track.localCachePath}');
        return;
      }

      late final String? title;
      late final String? artist;
      late final Duration duration;
      try {
        title = tagFile.title.trim().isEmpty ? track.title : tagFile.title;
        artist = tagFile.artist.trim().isEmpty ? track.artist : tagFile.artist;
        duration = tagFile.duration > Duration.zero
            ? tagFile.duration
            : track.duration;
      } finally {
        tagFile.close();
      }

      track.title = title;
      track.artist = artist;
      track.duration = duration;

      final hive = HiveStorageService();
      await hive.saveTrack(track);

      metadata[fileName] = {
        'title': title,
        'artist': artist,
        'durationMs': duration.inMilliseconds,
      };

      final localMetadataFile = File(
        '${localCacheDir.path}/${DateTime.now().millisecondsSinceEpoch}_metadata.json',
      );
      await localMetadataFile.writeAsString(json.encode(metadata));

      await provider.uploadFile(cloudMetadataPath, localMetadataFile);

      if (localMetadataFile.existsSync()) {
        localMetadataFile.deleteSync();
      }

      _log.info('Successfully updated metadata for $fileName in cloud');
    } catch (e, stackTrace) {
      _log.severe('Failed to update metadata in cloud: $e', e, stackTrace);
    }
  }
}
