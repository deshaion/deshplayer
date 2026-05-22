import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import 'cloud_provider.dart';
import 'yandex_disk_provider.dart';
import 'secure_storage_service.dart';

class CloudMediaService {
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
    // Determine provider from cloudPath if possible, or assume format "providerId://path"
    // Since previous track definition just had "cloudPath", let's define a convention:
    // cloudPath will be formatted as: "providerId://<actual_path>"

    final uri = Uri.tryParse(track.cloudPath);
    if (uri == null || uri.scheme.isEmpty) {
        // Fallback for mock tracks
        return _mockDownload(track);
    }

    final providerId = uri.scheme;
    final path = track.cloudPath.substring(providerId.length + 3); // remove "scheme://"

    final provider = getProvider(providerId);
    if (provider == null) {
      // Fallback for mock tracks
      if (track.cloudPath.startsWith('http')) {
         return _mockDownload(track);
      }
      throw Exception('Provider not found: $providerId');
    }

    final downloadUrl = await provider.getDownloadUrl(path);
    if (downloadUrl == null) throw Exception('No download URL obtained');

    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/music_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final file = File('${cacheDir.path}/${track.id}.mp3');
    if (!file.existsSync()) {
      // Download actual file using streaming
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await request.send();

      if (response.statusCode == 200) {
        final sink = file.openWrite();
        await response.stream.pipe(sink);
        await sink.close();
      } else {
        throw Exception('Failed to download track: ${response.statusCode}');
      }
    }

    return file.path;
  }

  Future<String> _mockDownload(Track track) async {
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
    return file.path;
  }
}
