import 'dart:convert';
import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:logging/logging.dart';
import '../models/track.dart';
import 'cloud_provider.dart';

class MetadataService {
  final _log = Logger('MetadataService');
  static const String metadataFileName = 'metadata.json';

  // Read metadata.json from cloud path
  Future<Map<String, dynamic>?> getCloudMetadata(CloudProvider provider, String dirPath, Directory localCacheDir) async {
    try {
      final cloudMetadataPath = '${dirPath.endsWith('/') ? dirPath : '$dirPath/'}$metadataFileName';
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

  Future<void> updateMetadataInCloud(CloudProvider provider, String cloudFilePath, Track track, Directory localCacheDir) async {
    try {
      if (track.localCachePath == null || !File(track.localCachePath!).existsSync()) {
        _log.warning('Cannot read tags, file missing: ${track.localCachePath}');
        return;
      }

      final tags = await AudioTags.read(track.localCachePath!);
      if (tags == null) {
        _log.info('No audio tags found in file: ${track.localCachePath}');
        return;
      }

      final title = tags.title ?? track.title;
      final artist = tags.trackArtist ?? track.artist;
      final duration = tags.duration != null ? Duration(seconds: tags.duration!) : track.duration;

      track.title = title;
      track.artist = artist;
      track.duration = duration;

      final schemeIdx = cloudFilePath.indexOf('://');
      if (schemeIdx == -1) return;
      final actualPath = cloudFilePath.substring(schemeIdx + 3);
      final dirPath = actualPath.substring(0, actualPath.lastIndexOf('/'));

      final cloudMetadataPath = '${dirPath.endsWith('/') ? dirPath : '$dirPath/'}$metadataFileName';

      Map<String, dynamic> metadata = {};
      final existingMetadata = await getCloudMetadata(provider, dirPath, localCacheDir);
      if (existingMetadata != null) {
        metadata = existingMetadata;
      }

      final fileName = actualPath.split('/').last;
      metadata[fileName] = {
        'title': title,
        'artist': artist,
        'durationMs': duration.inMilliseconds,
      };

      final localMetadataFile = File('${localCacheDir.path}/${DateTime.now().millisecondsSinceEpoch}_metadata.json');
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
