import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import 'cloud_provider.dart';
import 'yandex_disk_provider.dart';
import 'secure_storage_service.dart';
import 'hive_storage_service.dart';
import '../models/exceptions.dart';
import 'package:logging/logging.dart';

class CloudMediaService {
  final _log = Logger('CloudMediaService');
  late final SecureStorageService _secureStorage;
  late final List<CloudProvider> providers;

  // Singleton pattern for simplicity
  static final CloudMediaService _instance = CloudMediaService._internal();
  factory CloudMediaService() => _instance;

  CloudMediaService._internal() {
    _secureStorage = SecureStorageService();
    providers = [
      YandexDiskProvider(_secureStorage),
    ];
  }

  CloudProvider? getProvider(String providerId) {
    try {
      return providers.firstWhere((p) => p.id == providerId);
    } catch (_) {
      return null;
    }
  }

  Future<Directory> getCacheDir() async {
    Directory baseDir;
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      baseDir = Directory('$home/.deshplayer');
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final cacheDir = Directory('${baseDir.path}/music_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    return cacheDir;
  }

  Future<String> downloadAndCacheTrack(Track track) async {
    _log.info('Requesting download for track: ${track.id} from ${track.cloudPath}');
    // Determine provider from cloudPath if possible, or assume format "providerId://path"
    // Since previous track definition just had "cloudPath", let's define a convention:
    // cloudPath will be formatted as: "providerId://<actual_path>"

    final schemeIdx = track.cloudPath.indexOf('://');
    if (schemeIdx == -1) {
        _log.warning('Invalid cloudPath URI format: ${track.cloudPath}, falling back to mock download');
        // Fallback for mock tracks
        return _mockDownload(track);
    }

    final providerId = track.cloudPath.substring(0, schemeIdx);
    final path = track.cloudPath.substring(schemeIdx + 3); // remove "scheme://"

    final provider = getProvider(providerId);
    if (provider == null) {
      _log.warning('Provider not found: $providerId');
      // Fallback for mock tracks
      if (track.cloudPath.startsWith('http')) {
         return _mockDownload(track);
      }
      throw Exception('Provider not found: $providerId');
    }

    _log.fine('Obtaining download URL for path: $path');
    String? downloadUrl;
    try {
      downloadUrl = await provider.getDownloadUrl(path);
    } on CloudFileNotFoundException catch (e) {
      _log.severe('File not found in cloud, removing globally: ${track.id}');
      await HiveStorageService().deleteTrackGlobally(track.id);
      throw TrackRemovedException('Track "${track.title}" was removed from the cloud and has been deleted from your library.');
    }

    if (downloadUrl == null) {
      _log.severe('No download URL obtained for path: $path');
      throw Exception('No download URL obtained');
    }

    final cacheDir = await getCacheDir();

    final file = File('${cacheDir.path}/${track.id}');
    if (!file.existsSync()) {
      _log.info('Downloading file to cache: ${file.path}');
      // Download actual file using streaming
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await request.send();

      if (response.statusCode == 200) {
        final sink = file.openWrite();
        await response.stream.pipe(sink);
        await sink.close();
        _log.info('Download complete: ${file.path}');

        await _cleanupCache(cacheDir);
      } else if (response.statusCode == 404) {
        _log.severe('Download URL returned 404, removing globally: ${track.id}');
        await HiveStorageService().deleteTrackGlobally(track.id);
        throw TrackRemovedException('Track "${track.title}" was removed from the cloud and has been deleted from your library.');
      } else {
        _log.severe('Failed to download track: ${response.statusCode}');
        throw Exception('Failed to download track: ${response.statusCode}');
      }
    } else {
      _log.info('File already in cache: ${file.path}');
    }

    return file.path;
  }

  Future<void> _cleanupCache(Directory cacheDir) async {
    _log.info('Running cache cleanup...');
    try {
      final hive = HiveStorageService();
      final maxCacheSizeBytes = hive.getSettings().maxCacheSizeBytes;

      int totalSize = 0;
      final files = <File>[];
      if (cacheDir.existsSync()) {
        for (final entity in cacheDir.listSync()) {
          if (entity is File) {
            files.add(entity);
            totalSize += entity.lengthSync();
          }
        }
      }

      _log.info('Current cache size: $totalSize, Max allowed: $maxCacheSizeBytes');

      if (totalSize <= maxCacheSizeBytes) {
        _log.info('Cache size is within limits.');
        return;
      }

      _log.info('Cache size exceeds limits, cleaning up...');

      // Get all tracks from Hive to determine lastAccessed
      final allTracks = hive.tracksBox.values.toList();
      final cachedTracks = allTracks.where((t) => t.localCachePath != null).toList();

      // Sort tracks by lastAccessed (oldest first)
      // Tracks without lastAccessed will be treated as very old
      cachedTracks.sort((a, b) {
        final dateA = a.lastAccessed ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.lastAccessed ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateA.compareTo(dateB);
      });

      for (final track in cachedTracks) {
        if (totalSize <= maxCacheSizeBytes) {
          break;
        }

        final localPath = track.localCachePath;
        if (localPath != null) {
          final file = File(localPath);
          if (file.existsSync()) {
            final fileSize = file.lengthSync();
            file.deleteSync();
            totalSize -= fileSize;
            _log.info('Deleted cached file for track ${track.id}: $localPath, Reclaimed $fileSize bytes');

            // Clear local cache path in Hive
            track.localCachePath = null;
            await hive.saveTrack(track);
          } else {
            // File doesn't exist, just clear the reference
            track.localCachePath = null;
            await hive.saveTrack(track);
          }
        }
      }

      _log.info('Cache cleanup finished. New total size: $totalSize');
    } catch (e) {
      _log.severe('Error during cache cleanup: $e');
    }
  }

  Future<String> _mockDownload(Track track) async {
    _log.info('Mock downloading track: ${track.id}');
    await Future.delayed(const Duration(seconds: 1));
    final cacheDir = await getCacheDir();

    final file = File('${cacheDir.path}/${track.id}');
    if (!file.existsSync()) {
        file.writeAsBytesSync([0]);
    }
    _log.info('Mock download complete: ${file.path}');

    await _cleanupCache(cacheDir);

    return file.path;
  }
}
