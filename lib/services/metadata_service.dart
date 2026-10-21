import 'dart:convert';
import 'dart:io';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import '../models/exceptions.dart';
import '../models/track.dart';
import 'cloud_provider.dart';
import 'hive_storage_service.dart';
import 'google_drive_provider.dart';

class MetadataService {
  MetadataService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _log = Logger('MetadataService');
  static const String metadataFileName = 'metadata.json';
  static final Map<String, Future<void>> _pendingUpdates = {};

  // Read metadata.json from cloud path
  Future<Map<String, dynamic>?> getCloudMetadata(
    CloudProvider provider,
    String dirPath,
    Directory localCacheDir, {
    bool throwOnError = false,
  }) async {
    try {
      final cloudMetadataPath =
          '${dirPath.endsWith('/') ? dirPath : '$dirPath/'}$metadataFileName';
      final paths = provider is GoogleDriveProvider
          ? await provider.metadataFilePaths(dirPath)
          : [cloudMetadataPath];
      Map<String, dynamic>? metadata;
      for (final path in paths) {
        try {
          final downloadUrl = await provider.getDownloadUrl(path);
          if (downloadUrl == null) continue;
          final response = await _client.get(
            Uri.parse(downloadUrl),
            headers: await provider.getDownloadHeaders(),
          );
          if (response.statusCode == 404) continue;
          if (response.statusCode != 200) {
            throw HttpException(
              'Read cloud metadata failed (${response.statusCode}).',
            );
          }
          final content = Map<String, dynamic>.from(
            jsonDecode(response.body) as Map,
          );
          metadata ??= {};
          metadata.addAll(content);
        } on CloudFileNotFoundException {
          // A copy may have been removed between listing and downloading.
        }
      }
      return metadata;
    } on CloudFileNotFoundException {
      return null;
    } catch (e) {
      _log.warning('Failed to read cloud metadata: $e');
      if (throwOnError) rethrow;
    }
    return null;
  }

  Future<void> updateMetadataInCloud(
    CloudProvider provider,
    String cloudFilePath,
    Track track,
    Directory localCacheDir, {
    bool force = false,
  }) async {
    final schemeIdx = cloudFilePath.indexOf('://');
    if (schemeIdx == -1) return;
    final dirEnd = cloudFilePath.lastIndexOf('/');
    if (dirEnd < schemeIdx + 3) return;
    final key = '${provider.id}:${cloudFilePath.substring(0, dirEnd)}';
    final previous = _pendingUpdates[key] ?? Future<void>.value();
    final update = previous.then(
      (_) => _updateMetadataInCloud(
        provider,
        cloudFilePath,
        track,
        localCacheDir,
        force: force,
      ),
    );
    _pendingUpdates[key] = update;
    try {
      await update;
    } finally {
      if (identical(_pendingUpdates[key], update)) _pendingUpdates.remove(key);
    }
  }

  Future<void> _updateMetadataInCloud(
    CloudProvider provider,
    String cloudFilePath,
    Track track,
    Directory localCacheDir, {
    bool force = false,
  }) async {
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
        throwOnError: true,
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
            // A manual refresh makes the local audio file authoritative for
            // the selected track. Do not restore its stale cloud values before
            // TagLib gets a chance to inspect it.
            if (force && t.id == track.id) continue;
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
      if (!force && metadata.containsKey(fileName) && isCurrentTrackPopulated) {
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

      final tagFile = await TagLibFile.openAsync(
        track.localCachePath!,
        audioPropertiesStyle: force
            ? TagLibAudioPropertiesStyle.accurate
            : TagLibAudioPropertiesStyle.average,
      );
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

      final uploadDirectory = await localCacheDir.createTemp('metadata_');
      final localMetadataFile = File('${uploadDirectory.path}/metadata.json');
      try {
        await localMetadataFile.writeAsString(json.encode(metadata));
        await provider.uploadFile(cloudMetadataPath, localMetadataFile);
      } finally {
        await uploadDirectory.delete(recursive: true);
      }

      _log.info('Successfully updated metadata for $fileName in cloud');
    } catch (e, stackTrace) {
      _log.severe('Failed to update metadata in cloud: $e', e, stackTrace);
    }
  }
}
