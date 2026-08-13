import 'dart:io';
import '../models/track.dart';
import 'hive_storage_service.dart';
import 'cloud_media_service.dart';
import 'metadata_service.dart';
import 'dart:async';
import 'package:logging/logging.dart';
import 'package:audio_service/audio_service.dart';
import 'desh_audio_handler.dart';

class AudioPlayerService {
  final _log = Logger('AudioPlayerService');
  final HiveStorageService storageService;
  final CloudMediaService cloudMediaService = CloudMediaService();
  final MetadataService metadataService = MetadataService();

  late final DeshAudioHandler audioHandler;

  AudioPlayerService(this.storageService);

  Future<void> init() async {
    final handler = await AudioService.init(
      builder: () => DeshAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
        androidNotificationChannelName: 'Audio playback',
        androidNotificationOngoing: true,
      ),
    );
    audioHandler = handler ;
  }

  Future<void> preCacheTrack(Track track, {List<Track>? protectedTracks}) async {
    if (track.localCachePath != null &&
        File(track.localCachePath!).existsSync()) {
      return;
    }

    _log.info('Pre-caching track: ${track.id}');
    try {
      final localPath = await cloudMediaService.downloadAndCacheTrack(track, protectedTracks: protectedTracks);
      track.localCachePath = localPath;
      await storageService.saveTrack(track);

      if (track.artist == null || track.duration.inSeconds == 0) {
        syncMetadataAsync(track);
      }
    } catch (e) {
      _log.warning('Failed to pre-cache track: ${track.id}', e);
    }
  }

  Future<void> playTrack(Track track, {List<Track>? protectedTracks}) async {
    _log.info('Attempting to play track: ${track.id} (${track.title})');

    try {
      String localPath;
      String? downloadUrl;

      if (track.localCachePath != null &&
          File(track.localCachePath!).existsSync()) {
        _log.fine('Playing from local cache: ${track.localCachePath}');
        localPath = track.localCachePath!;
        downloadUrl = "local"; // not needed for local playback
      } else {
        _log.fine('Track not in local cache, requesting download URL from cloud: ${track.cloudPath}');
        downloadUrl = await cloudMediaService.getDownloadUrlForTrack(track);
        final cacheDir = await cloudMediaService.getCacheDir();
        localPath = '${cacheDir.path}/${track.id}';
      }

      await audioHandler.playTrack(track, downloadUrl: downloadUrl, localPath: localPath);

      // Update metadata and tracking
      track.localCachePath = localPath;
      track.lastAccessed = DateTime.now();
      await storageService.saveTrack(track);

      if (track.artist == null || track.duration.inSeconds == 0) {
        syncMetadataAsync(track);
      }

      _log.info('Started playback for track: ${track.id}');
      storageService.addToHistory(track.id);
    } catch (e, stackTrace) {
      _log.severe('Error playing track: ${track.id}', e, stackTrace);
      rethrow;
    }
  }

  Future<void> syncMetadataAsync(Track track) async {
    try {
      final schemeIdx = track.cloudPath.indexOf('://');
      if (schemeIdx == -1) return;
      final providerId = track.cloudPath.substring(0, schemeIdx);
      final provider = cloudMediaService.getProvider(providerId);
      if (provider != null) {
        final cacheDir = await cloudMediaService.getCacheDir();
        await metadataService.updateMetadataInCloud(
          provider,
          track.cloudPath,
          track,
          cacheDir,
        );
        await storageService.saveTrack(track);
      }
    } catch (e) {
      _log.severe('Error syncing metadata for track ${track.id}', e);
    }
  }

  Future<void> pause() async {
    await audioHandler.pause();
  }

  Future<void> play() async {
    await audioHandler.play();
  }

  Future<void> seek(Duration position) async {
    await audioHandler.seek(position);
  }

  Future<void> setVolume(double volume) async {
    audioHandler.setVolume(volume);
  }
}
