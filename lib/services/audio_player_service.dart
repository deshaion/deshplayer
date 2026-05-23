import 'dart:io';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'hive_storage_service.dart';
import 'cloud_media_service.dart';
import 'package:logging/logging.dart';

class AudioPlayerService {
  final _log = Logger('AudioPlayerService');
  final AudioPlayer player = AudioPlayer();
  final HiveStorageService storageService;
  final CloudMediaService cloudMediaService = CloudMediaService();

  AudioPlayerService(this.storageService);

  Future<void> playTrack(Track track) async {
    _log.info('Attempting to play track: ${track.id} (${track.title})');
    try {
      if (track.localCachePath != null && File(track.localCachePath!).existsSync()) {
        _log.fine('Playing from local cache: ${track.localCachePath}');
        // Play from cache
        await player.setFilePath(track.localCachePath!);
        track.lastAccessed = DateTime.now();
        await storageService.saveTrack(track);
      } else {
        _log.fine('Track not in local cache, requesting download from cloud: ${track.cloudPath}');
        // Use dedicated service to download
        final localPath = await cloudMediaService.downloadAndCacheTrack(track);
        track.localCachePath = localPath;
        track.lastAccessed = DateTime.now();

        try {
           await player.setUrl(track.cloudPath);
           _log.fine('Successfully set URL: ${track.cloudPath}');
        } catch (e, stackTrace) {
           _log.warning('Error setting URL (might be mock): ${track.cloudPath}', e, stackTrace);
           // For mock, just pretend it played
        }
        await storageService.saveTrack(track);
      }
      _log.info('Starting playback for track: ${track.id}');
      player.play();
      storageService.addToHistory(track.id);
    } catch (e, stackTrace) {
      _log.severe('Error playing track: ${track.id}', e, stackTrace);
      // Ignore
    }
  }

  Future<void> pause() async {
    _log.info('Pausing playback');
    await player.pause();
  }

  Future<void> seek(Duration position) async {
    _log.info('Seeking to position: $position');
    await player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    _log.fine('Setting volume to: $volume');
    await player.setVolume(volume);
  }

  Future<void> setLoopMode(LoopMode mode) async {
    _log.info('Setting loop mode to: $mode');
    await player.setLoopMode(mode);
  }

  Future<void> setShuffleModeEnabled(bool enabled) async {
    _log.info('Setting shuffle mode enabled: $enabled');
    await player.setShuffleModeEnabled(enabled);
  }
}
