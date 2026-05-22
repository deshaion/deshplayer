import '../models/duration_adapter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/playback_state.dart';
import '../models/settings.dart';
import 'mock_media_service.dart';

class HiveStorageService {
  static const String playlistsBoxName = 'playlists';
  static const String tracksBoxName = 'tracks';
  static const String playbackStateBoxName = 'playback_states';
  static const String settingsBoxName = 'settings';
  static const String historyBoxName = 'history';

  late Box<Playlist> playlistsBox;
  late Box<Track> tracksBox;
  late Box<PlaybackState> playbackStateBox;
  late Box<AppSettings> settingsBox;
  late Box<String> historyBox;

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(DurationAdapter());

    Hive.registerAdapter(TrackAdapter());
    Hive.registerAdapter(PlaylistAdapter());
    Hive.registerAdapter(PlaybackStateAdapter());
    Hive.registerAdapter(AppSettingsAdapter());

    playlistsBox = await Hive.openBox<Playlist>(playlistsBoxName);
    tracksBox = await Hive.openBox<Track>(tracksBoxName);
    playbackStateBox = await Hive.openBox<PlaybackState>(playbackStateBoxName);
    settingsBox = await Hive.openBox<AppSettings>(settingsBoxName);
    historyBox = await Hive.openBox<String>(historyBoxName);

    // Seed mock data if empty
    if (playlistsBox.isEmpty && tracksBox.isEmpty) {
      for (var t in MockMediaService.tracks) {
        await tracksBox.put(t.id, t);
      }
      for (var p in MockMediaService.playlists) {
        await playlistsBox.put(p.id, p);
      }
    }
  }

  // Playlists
  List<Playlist> getPlaylists() => playlistsBox.values.toList();
  Playlist? getPlaylist(String id) => playlistsBox.get(id);
  Future<void> savePlaylist(Playlist playlist) => playlistsBox.put(playlist.id, playlist);
  Future<void> deletePlaylist(String id) => playlistsBox.delete(id);

  // Tracks
  Track? getTrack(String id) => tracksBox.get(id);
  List<Track> getTracksByIds(List<String> ids) => ids.map((id) => tracksBox.get(id)).whereType<Track>().toList();
  Future<void> saveTrack(Track track) => tracksBox.put(track.id, track);

  // Playback State
  PlaybackState? getPlaybackState(String playlistId) => playbackStateBox.get(playlistId);
  Future<void> savePlaybackState(PlaybackState state) => playbackStateBox.put(state.playlistId, state);

  // Settings
  AppSettings getSettings() => settingsBox.get('app_settings') ?? AppSettings();
  Future<void> saveSettings(AppSettings settings) => settingsBox.put('app_settings', settings);

  // History (Storing Track IDs for simplicity)
  List<String> getHistory() => historyBox.values.toList();
  Future<void> addToHistory(String trackId) async {
    // Basic history: append to end.
    // You could limit the size here.
    await historyBox.add(trackId);
    if (historyBox.length > 100) {
      await historyBox.deleteAt(0); // keep history bounded
    }
  }
}
