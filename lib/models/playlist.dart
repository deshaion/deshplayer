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

  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
  });
}
