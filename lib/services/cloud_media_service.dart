import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import 'cloud_provider.dart';
import 'yandex_disk_provider.dart';
import 'secure_storage_service.dart';
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
    final downloadUrl = await provider.getDownloadUrl(path);
    if (downloadUrl == null) {
      _log.severe('No download URL obtained for path: $path');
      throw Exception('No download URL obtained');
    }

    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/music_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final file = File('${cacheDir.path}/${track.id}.mp3');
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
      } else {
        _log.severe('Failed to download track: ${response.statusCode}');
        throw Exception('Failed to download track: ${response.statusCode}');
      }
    } else {
      _log.info('File already in cache: ${file.path}');
    }

    return file.path;
  }

  Future<String> _mockDownload(Track track) async {
    _log.info('Mock downloading track: ${track.id}');
    await Future.delayed(const Duration(seconds: 1));
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/music_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final file = File('${cacheDir.path}/${track.id}.mp3');
    if (!file.existsSync()) {
        file.writeAsBytesSync([0]);
    }
    _log.info('Mock download complete: ${file.path}');
    return file.path;
  }
}
