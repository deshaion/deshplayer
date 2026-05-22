import 'package:hive/hive.dart';

part 'track.g.dart';

@HiveType(typeId: 0)
class Track {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String cloudPath;

  @HiveField(2)
  String? localCachePath;

  @HiveField(3)
  String? title;

  @HiveField(4)
  String? artist;

  @HiveField(5)
  Duration duration;

  @HiveField(6)
  int? fileSize;

  @HiveField(7)
  DateTime? lastAccessed;

  Track({
    required this.id,
    required this.cloudPath,
    this.localCachePath,
    this.title,
    this.artist,
    required this.duration,
    this.fileSize,
    this.lastAccessed,
  });
}
