import 'dart:io';
import '../models/duration_adapter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/playback_state.dart';
import '../models/settings.dart';
import '../models/app_log_record.dart';
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
  static const String logsBoxName = 'logs';

  late Box<Playlist> playlistsBox;
  late Box<Track> tracksBox;
  late Box<PlaybackState> playbackStateBox;
  late Box<AppSettings> settingsBox;
  late Box<String> historyBox;
  late Box<AppLogRecord> logsBox;

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
    Hive.registerAdapter(AppLogRecordAdapter());

    _log.fine('Opening Hive boxes');
    playlistsBox = await Hive.openBox<Playlist>(playlistsBoxName);
    tracksBox = await Hive.openBox<Track>(tracksBoxName);
    playbackStateBox = await Hive.openBox<PlaybackState>(playbackStateBoxName);
    settingsBox = await Hive.openBox<AppSettings>(settingsBoxName);
    historyBox = await Hive.openBox<String>(historyBoxName);
    logsBox = await Hive.openBox<AppLogRecord>(logsBoxName);

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
  List<Track> getAllTracks() => tracksBox.values.toList();
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

  // Logs
  List<AppLogRecord> getLogs() => logsBox.values.toList();

  Future<void> addLog(AppLogRecord log) async {
    await logsBox.add(log);
    // Keep max 10000 records
    if (logsBox.length > 10000) {
      // Remove the oldest 1000 to avoid deleting one by one on every log if at limit
      final int amountToRemove = logsBox.length - 9000;
      final keysToRemove = logsBox.keys.take(amountToRemove);
      await logsBox.deleteAll(keysToRemove);
    }
  }

  Future<void> clearLogs() => logsBox.clear();
  
  void checkTrackDb() async {
    _log.info('Starting Track DB Check...');
    final allTracks = getAllTracks();
    for (final t in allTracks) {
      if (t.duration.inSeconds > 0 && ((t.title?.contains(".mp3") ?? false) || (t.title?.contains(".flac") ?? false))) {
        _log.warning('Track representation warning: Title: ${t.title} Artist: ${t.artist} Duration: ${t.duration} file: ${t.cloudPath}');
      }
    }
    _log.fine('Track DB Check has been completed');
  }
}
