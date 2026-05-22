import '../models/playlist.dart';
import '../models/track.dart';

class MockMediaService {
  static List<Playlist> playlists = [
    Playlist(
      id: 'p1',
      name: 'Chill Vibes',
      trackIds: ['t1', 't2', 't3', 't4'],
    ),
    Playlist(
      id: 'p2',
      name: 'Workout Mix',
      trackIds: ['t5', 't6', 't7'],
    ),
    Playlist(
      id: 'p3',
      name: 'Classical Focus',
      trackIds: ['t8', 't9', 't10'],
    ),
  ];

  static List<Track> tracks = [
    Track(id: 't1', title: 'Ocean Breeze', artist: 'Lofi Maker', duration: const Duration(minutes: 3, seconds: 12), cloudPath: 'https://example.com/t1.mp3'),
    Track(id: 't2', title: 'Sunset Dreams', artist: 'Chill Guy', duration: const Duration(minutes: 2, seconds: 45), cloudPath: 'https://example.com/t2.mp3'),
    Track(id: 't3', title: 'Night City', artist: 'Synth Wave', duration: const Duration(minutes: 4, seconds: 5), cloudPath: 'https://example.com/t3.mp3'),
    Track(id: 't4', title: 'Coffee Shop', artist: 'Lofi Maker', duration: const Duration(minutes: 2, seconds: 10), cloudPath: 'https://example.com/t4.mp3'),
    Track(id: 't5', title: 'Pump It Up', artist: 'DJ Energy', duration: const Duration(minutes: 3, seconds: 30), cloudPath: 'https://example.com/t5.mp3'),
    Track(id: 't6', title: 'Run Fast', artist: 'Beat Master', duration: const Duration(minutes: 3, seconds: 0), cloudPath: 'https://example.com/t6.mp3'),
    Track(id: 't7', title: 'Heavy Lifting', artist: 'Rock Solid', duration: const Duration(minutes: 4, seconds: 15), cloudPath: 'https://example.com/t7.mp3'),
    Track(id: 't8', title: 'Piano Sonata', artist: 'Composer A', duration: const Duration(minutes: 5, seconds: 20), cloudPath: 'https://example.com/t8.mp3'),
    Track(id: 't9', title: 'Violin Concerto', artist: 'Composer B', duration: const Duration(minutes: 6, seconds: 0), cloudPath: 'https://example.com/t9.mp3'),
    Track(id: 't10', title: 'Cello Suite', artist: 'Composer C', duration: const Duration(minutes: 4, seconds: 40), cloudPath: 'https://example.com/t10.mp3'),
  ];

  Future<List<Playlist>> fetchPlaylists() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    return playlists;
  }
}
