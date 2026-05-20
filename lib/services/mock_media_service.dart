import '../models/playlist.dart';
import '../models/track.dart';

class MockMediaService {
  static const List<Playlist> playlists = [
    Playlist(
      id: 'p1',
      name: 'Chill Vibes',
      tracks: [
        Track(id: 't1', title: 'Ocean Breeze', artist: 'Lofi Maker', duration: Duration(minutes: 3, seconds: 12)),
        Track(id: 't2', title: 'Sunset Dreams', artist: 'Chill Guy', duration: Duration(minutes: 2, seconds: 45)),
        Track(id: 't3', title: 'Night City', artist: 'Synth Wave', duration: Duration(minutes: 4, seconds: 5)),
        Track(id: 't4', title: 'Coffee Shop', artist: 'Lofi Maker', duration: Duration(minutes: 2, seconds: 10)),
      ],
    ),
    Playlist(
      id: 'p2',
      name: 'Workout Mix',
      tracks: [
        Track(id: 't5', title: 'Pump It Up', artist: 'DJ Energy', duration: Duration(minutes: 3, seconds: 30)),
        Track(id: 't6', title: 'Run Fast', artist: 'Beat Master', duration: Duration(minutes: 3, seconds: 0)),
        Track(id: 't7', title: 'Heavy Lifting', artist: 'Rock Solid', duration: Duration(minutes: 4, seconds: 15)),
      ],
    ),
    Playlist(
      id: 'p3',
      name: 'Classical Focus',
      tracks: [
        Track(id: 't8', title: 'Piano Sonata', artist: 'Composer A', duration: Duration(minutes: 5, seconds: 20)),
        Track(id: 't9', title: 'Violin Concerto', artist: 'Composer B', duration: Duration(minutes: 6, seconds: 0)),
        Track(id: 't10', title: 'Cello Suite', artist: 'Composer C', duration: Duration(minutes: 4, seconds: 40)),
      ],
    ),
  ];

  Future<List<Playlist>> fetchPlaylists() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    return playlists;
  }
}
