import 'package:hive/hive.dart';


part 'playlist.g.dart';

@HiveType(typeId: 1)
class Playlist {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<String> trackIds;

  @HiveField(3, defaultValue: 0)
  int order;

  @HiveField(4, defaultValue: false)
  bool excludeFromStatistics;

  @HiveField(5, defaultValue: false)
  bool isBookMode;

  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    this.order = 0,
    this.excludeFromStatistics = false,
    this.isBookMode = false,
  });
}
