import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/duration_adapter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/playback_state.dart';
import '../models/settings.dart';
import 'mock_media_service.dart';
import 'package:logging/logging.dart';

class HiveStorageService {
  final _log = Logger('HiveStorageService');

  // Singleton pattern
  static final HiveStorageService _instance = HiveStorageService._internal();
  factory HiveStorageService() => _instance;
  HiveStorageService._internal();

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
    _log.info('Initializing Hive storage');

    String? path;
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      final dir = Directory('$home/.deshplayer');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      path = dir.path;
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }

    _log.fine('Registering Hive adapters');
    Hive.registerAdapter(DurationAdapter());
    Hive.registerAdapter(TrackAdapter());
    Hive.registerAdapter(PlaylistAdapter());
    Hive.registerAdapter(PlaybackStateAdapter());
    Hive.registerAdapter(AppSettingsAdapter());

    _log.fine('Opening Hive boxes');
    playlistsBox = await Hive.openBox<Playlist>(playlistsBoxName);
    tracksBox = await Hive.openBox<Track>(tracksBoxName);
    playbackStateBox = await Hive.openBox<PlaybackState>(playbackStateBoxName);
    settingsBox = await Hive.openBox<AppSettings>(settingsBoxName);
    historyBox = await Hive.openBox<String>(historyBoxName);

    // Seed mock data if empty
    if (playlistsBox.isEmpty && tracksBox.isEmpty) {
      _log.info('Hive boxes are empty, seeding mock data');
      for (var t in MockMediaService.tracks) {
        await tracksBox.put(t.id, t);
      }
      for (var p in MockMediaService.playlists) {
        await playlistsBox.put(p.id, p);
      }
      _log.info('Mock data seeded successfully');
    } else {
      _log.fine('Hive boxes initialized successfully');
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
