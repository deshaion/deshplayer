import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import 'cloud_provider.dart';
import 'network_http_client.dart';
import 'cached_file_download.dart';
import 'yandex_disk_provider.dart';
import 'google_drive_provider.dart';
import 'secure_storage_service.dart';
import 'hive_storage_service.dart';
import '../models/exceptions.dart';
import 'package:logging/logging.dart';

class CloudMediaService {
  final _log = Logger('CloudMediaService');
  final _client = NetworkHttpClient();
  final _cacheDownloads = <String, Future<String>>{};
  late final SecureStorageService _secureStorage;
  late final List<CloudProvider> providers;

  // Singleton pattern for simplicity
  static final CloudMediaService _instance = CloudMediaService._internal();
  factory CloudMediaService() => _instance;

  CloudMediaService._internal() {
    _secureStorage = SecureStorageService();
    providers = [
      YandexDiskProvider(_secureStorage),
      GoogleDriveProvider(_secureStorage),
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

  Future<String> downloadAndCacheTrack(
    Track track, {
    List<Track>? protectedTracks,
  }) async {
    final pending = _cacheDownloads[track.id];
    if (pending != null) return pending;
    final download = _downloadAndCacheTrack(
      track,
      protectedTracks: protectedTracks,
    );
    _cacheDownloads[track.id] = download;
    try {
      return await download;
    } finally {
      _cacheDownloads.remove(track.id);
    }
  }

  Future<String> _downloadAndCacheTrack(
    Track track, {
    List<Track>? protectedTracks,
  }) async {
    final cacheDir = await getCacheDir();
    final file = File('${cacheDir.path}/${track.id}');
    if (await file.exists() && await file.length() > 0) return file.path;
    _log.info(
      'Requesting download for track: ${track.id} from ${track.cloudPath}',
    );
    // Determine provider from cloudPath if possible, or assume format "providerId://path"
    // Since previous track definition just had "cloudPath", let's define a convention:
    // cloudPath will be formatted as: "providerId://<actual_path>"

    final schemeIdx = track.cloudPath.indexOf('://');
    if (schemeIdx == -1) {
      _log.severe('Invalid cloudPath URI format: ${track.cloudPath}');
      throw Exception('Invalid cloudPath URI format: ${track.cloudPath}');
    }

    final providerId = track.cloudPath.substring(0, schemeIdx);
    final path = track.cloudPath.substring(schemeIdx + 3); // remove "scheme://"

    final provider = getProvider(providerId);
    if (provider == null) {
      _log.severe('Provider not found: $providerId');
      throw Exception('Provider not found: $providerId');
    }

    _log.fine('Obtaining download URL for path: $path');
    String? downloadUrl;
    try {
      downloadUrl = await provider.getDownloadUrl(path);
    } on CloudFileNotFoundException {
      _log.severe('File not found in cloud, removing globally: ${track.id}');
      await HiveStorageService().deleteTrackGlobally(track.id);
      throw TrackRemovedException(
        'Track "${track.title}" was removed from the cloud and has been deleted from your library.',
      );
    }

    if (downloadUrl == null) {
      _log.severe('No download URL obtained for path: $path');
      throw Exception('No download URL obtained');
    }

    _log.info('Downloading file to cache: ${file.path}');
    await downloadCacheFile(
      client: _client,
      url: Uri.parse(downloadUrl),
      destination: file,
      headers: await provider.getDownloadHeaders(),
    );
    _log.info('Download complete: ${file.path}');
    await _cleanupCache(cacheDir, protectedTracks: protectedTracks);

    return file.path;
  }

  Future<void> _cleanupCache(
    Directory cacheDir, {
    List<Track>? protectedTracks,
  }) async {
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

      _log.info(
        'Current cache size: $totalSize, Max allowed: $maxCacheSizeBytes',
      );

      if (totalSize <= maxCacheSizeBytes) {
        _log.info('Cache size is within limits.');
        return;
      }

      _log.info('Cache size exceeds limits, cleaning up...');

      // Get all tracks from Hive to determine lastAccessed
      final allTracks = hive.tracksBox.values.toList();
      var cachedTracks = allTracks
          .where((t) => t.localCachePath != null)
          .toList();

      if (protectedTracks != null && protectedTracks.isNotEmpty) {
        final protectedIds = protectedTracks.map((t) => t.id).toSet();
        cachedTracks = cachedTracks
            .where((t) => !protectedIds.contains(t.id))
            .toList();
      }

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
            _log.info(
              'Deleted cached file for track ${track.id}: $localPath, Reclaimed $fileSize bytes',
            );

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

  Future<Map<String, String>> getDownloadHeadersForTrack(Track track) async {
    final provider = getProvider(track.cloudPath.split('://').first);
    if (provider == null) throw StateError('Cloud provider is unavailable.');
    return provider.getDownloadHeaders();
  }

  Future<String> getDownloadUrlForTrack(Track track) async {
    final schemeIdx = track.cloudPath.indexOf('://');
    if (schemeIdx == -1) {
      throw Exception('Invalid cloudPath URI format: ${track.cloudPath}');
    }

    final providerId = track.cloudPath.substring(0, schemeIdx);
    final path = track.cloudPath.substring(schemeIdx + 3);

    final provider = getProvider(providerId);
    if (provider == null) {
      throw Exception('Provider not found: $providerId');
    }

    String? downloadUrl;
    try {
      downloadUrl = await provider.getDownloadUrl(path);
    } on CloudFileNotFoundException {
      await HiveStorageService().deleteTrackGlobally(track.id);
      throw TrackRemovedException(
        'Track "${track.title}" was removed from the cloud and has been deleted from your library.',
      );
    }

    if (downloadUrl == null) {
      throw Exception('No download URL obtained');
    }

    return downloadUrl;
  }
}
