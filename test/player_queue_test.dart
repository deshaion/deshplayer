import 'dart:io';
import 'dart:async';
import 'package:deshplayer/services/stats_service.dart';

import 'package:audio_service/audio_service.dart';
import 'package:deshplayer/models/playlist.dart';
import 'package:deshplayer/models/duration_adapter.dart';
import 'package:deshplayer/models/playback_state.dart' as saved;
import 'package:deshplayer/models/settings.dart';
import 'package:deshplayer/models/track.dart';
import 'package:deshplayer/services/audio_player_service.dart';
import 'package:deshplayer/services/desh_audio_handler.dart';
import 'package:deshplayer/services/hive_storage_service.dart';
import 'package:deshplayer/services/player_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class TestHandler extends BaseAudioHandler implements DeshAudioHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAudio extends AudioPlayerService {
  TestAudio(super.storageService);
  bool? restoredPaused;
  final positions = StreamController<Duration>.broadcast();

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Future<void> init({
    required Future<void> Function() onSkipToPrevious,
    required Future<void> Function() onSkipToNext,
  }) async {
    audioHandler = TestHandler();
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> preCacheTrack(
    Track track, {
    List<Track>? protectedTracks,
  }) async {}

  @override
  Future<void> playTrack(
    Track track, {
    List<Track>? protectedTracks,
    bool startPaused = false,
  }) async {
    restoredPaused = startPaused;
  }

  @override
  Future<void> seek(Duration position) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Hive.registerAdapter(TrackAdapter());
  Hive.registerAdapter(PlaylistAdapter());
  Hive.registerAdapter(AppSettingsAdapter());
  Hive.registerAdapter(saved.PlaybackStateAdapter());
  Hive.registerAdapter(DurationAdapter());
  final storage = HiveStorageService();
  late Directory directory;
  late Playlist music;
  late Playlist book;
  late Track track;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('player_queue_test');
    Hive.init(directory.path);
    storage.queueSessionBox = await Hive.openBox<String>('session');
    storage.playlistsBox = await Hive.openBox<Playlist>('playlists');
    storage.tracksBox = await Hive.openBox<Track>('tracks');
    storage.settingsBox = await Hive.openBox<AppSettings>('settings');
    storage.playbackStateBox = await Hive.openBox<saved.PlaybackState>(
      'states',
    );
    track = Track(
      id: 'shared',
      cloudPath: '/shared.mp3',
      duration: const Duration(minutes: 3),
    );
    music = Playlist(id: 'music', name: 'Music', trackIds: [track.id]);
    book = Playlist(
      id: 'book',
      name: 'Book',
      trackIds: [track.id],
      isBookMode: true,
      excludeFromStatistics: true,
    );
    await storage.saveTrack(track);
    await storage.savePlaylist(music);
    await storage.savePlaylist(book);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<PlayerProvider> createPlayer() async {
    final player = PlayerProvider(storage, audioService: TestAudio(storage));
    await player.initialized;
    return player;
  }

  test(
    'duplicate occurrences retain their own playlist through reorder and previous',
    () async {
      final player = await createPlayer();
      await player.setActivePlaylist(music, startTrack: track);
      player.addToQueue(track, playlist: music);
      player.addToQueue(track, playlist: book);
      player.reorderQueue(1, 0);
      await player.playNext();
      expect(player.currentTrackPlaylist?.excludeFromStatistics, isTrue);
      await player.playNext();
      expect(player.currentTrackPlaylist?.id, music.id);
      await player.playPrevious();
      expect(player.currentTrackPlaylist?.id, book.id);
      player.dispose();
    },
  );

  test(
    'restart preserves order, duplicates, attribution and position, paused',
    () async {
      var player = await createPlayer();
      await player.setActivePlaylist(music, startTrack: track);
      player.addToQueue(track, playlist: music);
      player.addToQueue(track, playlist: book);
      player.addToQueue(track, playlist: music);
      player.removeFromQueueAt(0);
      await player.seek(const Duration(seconds: 42));
      player.dispose();
      await storage.queueSessionBox.close();
      storage.queueSessionBox = await Hive.openBox<String>('session');
      final audio = TestAudio(storage);
      player = PlayerProvider(storage, audioService: audio);
      await player.initialized;
      expect(player.queue.map((t) => t.id), [track.id, track.id]);
      expect(player.position, const Duration(seconds: 42));
      expect(audio.restoredPaused, isTrue);
      await player.playNext();
      expect(player.currentTrackPlaylist?.id, book.id);
      player.dispose();
    },
  );

  test('book mode retains the regular queue across restart', () async {
    var player = await createPlayer();
    await player.setActivePlaylist(music, startTrack: track);
    player.addToQueue(track, playlist: music);
    await player.setActivePlaylist(book, startTrack: track);
    player.dispose();
    player = await createPlayer();
    await player.setActivePlaylist(music, startTrack: track);
    expect(player.queue.length, 1);
    await player.playNext();
    expect(player.currentTrackPlaylist?.id, music.id);
    player.dispose();
  });

  test(
    'statistics follow the queued source playlist, including shared tracks',
    () async {
      final statsBox = await Hive.openBox<String>('statistics');
      await statsBox.put('device_id', 'test_device');
      await StatsService().init();
      final audio = TestAudio(storage);
      final player = PlayerProvider(storage, audioService: audio);
      await player.initialized;
      await player.setActivePlaylist(music, startTrack: track);
      track.artist = 'Artist';
      track.title = 'Song';
      track.duration = const Duration(seconds: 4);
      player.addToQueue(track, playlist: book);
      player.addToQueue(track, playlist: music);
      await player.playNext();
      audio.audioHandler.playbackState.add(PlaybackState(playing: true));
      await Future<void>.delayed(Duration.zero);
      audio.positions.add(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      final now = DateTime.now();
      expect(StatsService().getStatsForPeriod(now, now), isEmpty);
      await player.playNext();
      audio.positions.add(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      expect(StatsService().getStatsForPeriod(now, now), {'Artist - Song': 1});
      player.dispose();
      await audio.positions.close();
    },
  );

  test('restoring a queue skips deleted tracks', () async {
    var player = await createPlayer();
    player.addToQueue(track, playlist: music);
    player.dispose();
    await storage.tracksBox.delete(track.id);
    player = await createPlayer();
    expect(player.queue, isEmpty);
    player.dispose();
  });
}
