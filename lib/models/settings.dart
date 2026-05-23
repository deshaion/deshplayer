import 'package:hive/hive.dart';

part 'settings.g.dart';

@HiveType(typeId: 3)
class AppSettings {
  @HiveField(0)
  int maxCacheSizeBytes;

  @HiveField(1)
  String? localMusicCacheFolder;

  @HiveField(2)
  bool shuffle;

  @HiveField(3)
  int repeatMode; // 0 = none, 1 = all, 2 = one

  @HiveField(4)
  double volume;

  @HiveField(5)
  String? lastActivePlaylistId;

  @HiveField(6)
  String? cloudStatsFolder;

  AppSettings({
    this.maxCacheSizeBytes = 1024 * 1024 * 1024, // 1GB default
    this.localMusicCacheFolder,
    this.shuffle = false,
    this.repeatMode = 0,
    this.volume = 1.0,
    this.lastActivePlaylistId,
    this.cloudStatsFolder = '/Statistics',
  });
}
