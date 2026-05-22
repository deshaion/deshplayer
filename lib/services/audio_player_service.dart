import 'dart:io';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'hive_storage_service.dart';
import 'cloud_media_service.dart';

class AudioPlayerService {
  final AudioPlayer player = AudioPlayer();
  final HiveStorageService storageService;
  final CloudMediaService cloudMediaService = CloudMediaService();

  AudioPlayerService(this.storageService);

  Future<void> playTrack(Track track) async {
    try {
      if (track.localCachePath != null && File(track.localCachePath!).existsSync()) {
        // Play from cache
        await player.setFilePath(track.localCachePath!);
        track.lastAccessed = DateTime.now();
        await storageService.saveTrack(track);
      } else {
        // Use dedicated service to download
        final localPath = await cloudMediaService.downloadAndCacheTrack(track);
        track.localCachePath = localPath;
        track.lastAccessed = DateTime.now();

        try {
           await player.setUrl(track.cloudPath);
        } catch (e) {
           // For mock, just pretend it played
        }
        await storageService.saveTrack(track);
      }
      player.play();
      storageService.addToHistory(track.id);
    } catch (e) {
      // Ignore
    }
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await player.setVolume(volume);
  }

  Future<void> setLoopMode(LoopMode mode) async {
    await player.setLoopMode(mode);
  }

  Future<void> setShuffleModeEnabled(bool enabled) async {
    await player.setShuffleModeEnabled(enabled);
  }
}
