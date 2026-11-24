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
  Future<void>? playbackGate;
  final playbackStarted = Completer<void>();
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
    if (!playbackStarted.isCompleted) playbackStarted.complete();
    await playbackGate;
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
    storage.historyBox = await Hive.openBox<String>('history');
    storage.queuesBox = await Hive.openBox<String>(
      HiveStorageService.queuesBoxName,
    );
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

  Future<Track> saveTrack(String id) async {
    final track = Track(id: id, cloudPath: '/$id.mp3', duration: Duration.zero);
    await storage.saveTrack(track);
    return track;
  }

  Future<void> reopenQueues() async {
    await storage.queuesBox.close();
    storage.queuesBox = await Hive.openBox<String>(
      HiveStorageService.queuesBoxName,
    );
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
      await reopenQueues();
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

  test(
    'each book and the shared regular queue survive switches and restart',
    () async {
      final nextChapter = await saveTrack('chapter-2');
      book.trackIds.add(nextChapter.id);
      await storage.savePlaylist(book);
      final otherBookTrack = await saveTrack('other-chapter');
      final otherBook = Playlist(
        id: 'other-book',
        name: 'Other book',
        trackIds: [otherBookTrack.id],
        isBookMode: true,
      );
      await storage.savePlaylist(otherBook);
      final otherMusic = Playlist(
        id: 'other-music',
        name: 'Other music',
        trackIds: [],
      );
      await storage.savePlaylist(otherMusic);
      final musicExtra = await saveTrack('music-extra');
      var player = await createPlayer();
      await player.setActivePlaylist(music, startTrack: track);
      player.addToQueue(musicExtra, playlist: music);
      await player.setActivePlaylist(otherMusic);
      expect(player.queue.map((t) => t.id), [musicExtra.id]);

      await player.setActivePlaylist(book, startTrack: track);
      player.addToQueue(otherBookTrack, playlist: otherBook);
      player.reorderQueue(1, 0);
      await player.seek(const Duration(seconds: 42));

      await player.setActivePlaylist(otherBook, startTrack: otherBookTrack);
      player.addToQueue(musicExtra, playlist: music);
      await player.seek(const Duration(seconds: 11));
      await player.resumePlaylist(book);
      expect(player.queue.map((t) => t.id), [
        otherBookTrack.id,
        nextChapter.id,
      ]);
      expect(player.position, const Duration(seconds: 42));
      await player.resumePlaylist(otherBook);
      expect(player.queue.map((t) => t.id), [musicExtra.id]);
      player.dispose();
      await reopenQueues();

      player = await createPlayer();
      expect(player.playingPlaylist?.id, otherBook.id);
      expect(player.queue.map((t) => t.id), [musicExtra.id]);
      await player.setActivePlaylist(otherMusic);
      expect(player.queue.map((t) => t.id), [musicExtra.id]);
      await player.resumePlaylist(book);
      expect(player.queue.map((t) => t.id), [
        otherBookTrack.id,
        nextChapter.id,
      ]);
      await player.playNext();
      expect(player.currentTrackPlaylist?.id, otherBook.id);
      player.removeFromQueueAt(0);
      expect(player.queue, isEmpty);
      await player.resumePlaylist(otherBook);
      expect(player.position, const Duration(seconds: 11));
      expect(player.queue.map((t) => t.id), [musicExtra.id]);
      await player.resumePlaylist(book);
      expect(player.queue, isEmpty);
      player.dispose();
    },
  );

  test(
    'upgrades existing active book and regular queues independently',
    () async {
      final regularTrack = await saveTrack('regular-queued');
      await storage.saveQueueSession({
        'playlistId': book.id,
        'currentTrackId': track.id,
        'currentTrackPlaylistId': book.id,
        'queue': <Map<String, dynamic>>[],
        'savedRegularQueue': [
          {'trackId': regularTrack.id, 'playlistId': music.id},
        ],
      });
      var player = await createPlayer();
      expect(player.playingPlaylist?.id, book.id);
      expect(player.queue, isEmpty);
      player.addToQueue(track, playlist: book);
      await player.setActivePlaylist(music);
      expect(player.queue.map((t) => t.id), [regularTrack.id]);
      player.dispose();
      await reopenQueues();

      player = await createPlayer();
      await player.resumePlaylist(book);
      expect(player.queue.map((t) => t.id), [track.id]);
      player.dispose();
    },
  );

  test('queue additions are saved while startup waits for audio', () async {
    final queued = await saveTrack('queued');
    final first = await saveTrack('first');
    final last = await saveTrack('last');
    await storage.saveQueueSession({
      'playlistId': music.id,
      'currentTrackId': track.id,
      'currentTrackPlaylistId': music.id,
      'queue': [
        {'trackId': queued.id, 'playlistId': music.id},
      ],
    });
    final gate = Completer<void>();
    final audio = TestAudio(storage)..playbackGate = gate.future;
    var player = PlayerProvider(storage, audioService: audio);
    final prepend = player.playNextInQueue(first, playlist: music);
    await audio.playbackStarted.future;
    await player.addToQueue(last, playlist: music);
    await prepend;
    expect(player.queue.map((t) => t.id), [first.id, queued.id, last.id]);
    gate.complete();
    await player.initialized;
    player.dispose();
    await reopenQueues();

    player = await createPlayer();
    expect(player.queue.map((t) => t.id), [first.id, queued.id, last.id]);
    player.dispose();
  });

  test('History retains its source and resolves older entries', () async {
    var player = await createPlayer();
    await player.setActivePlaylist(book, startTrack: track);
    await storage.historyBox.add(track.id);
    expect(player.playbackHistory.first.playlistId, book.id);
    await player.setActivePlaylist(music, startTrack: track);
    player.dispose();
    await storage.historyBox.close();
    storage.historyBox = await Hive.openBox<String>('history');

    player = await createPlayer();
    final bookEntry = player.playbackHistory.firstWhere(
      (entry) => entry.playlistId == book.id,
    );
    await player.playHistoryEntry(bookEntry);
    expect(player.currentTrackPlaylist?.excludeFromStatistics, isTrue);
    expect(player.playingPlaylist?.id, music.id);
    await player.enqueue(bookEntry);
    await player.enqueue(
      player.playbackHistory.firstWhere(
        (entry) => entry.playlistId == music.id,
      ),
      playNext: true,
    );
    await player.playNext();
    expect(player.currentTrackPlaylist?.id, music.id);
    await player.playNext();
    expect(player.currentTrackPlaylist?.id, book.id);
    player.dispose();
  });

  test(
    'a book restart refills the sequence, while resume honors an empty queue',
    () async {
      final last = await saveTrack('last-chapter');
      book.trackIds.add(last.id);
      await storage.savePlaylist(book);
      final player = await createPlayer();
      await player.setActivePlaylist(book, startTrack: track);
      await player.playNext();
      expect(player.currentTrack?.id, last.id);
      expect(player.queue, isEmpty);
      await player.setActivePlaylist(music, startTrack: track);
      await player.resumePlaylist(book);
      expect(player.currentTrack?.id, last.id);
      expect(player.queue, isEmpty);
      await player.playTrackDirectly(track, playlist: book);
      expect(player.queue.map((t) => t.id), [last.id]);
      await player.playNext();
      await player.setActivePlaylist(music, startTrack: track);
      await player.playTrackDirectly(track, playlist: book);
      expect(player.queue.map((t) => t.id), [last.id]);
      player.dispose();
    },
  );

  test(
    'foreign occurrences leave the book sequence at its last chapter',
    () async {
      final last = await saveTrack('last-chapter');
      book.trackIds.add(last.id);
      music.trackIds.add(last.id);
      await storage.savePlaylist(book);
      await storage.savePlaylist(music);
      var player = await createPlayer();
      await player.setActivePlaylist(book, startTrack: last);
      await player.playNextInQueue(last, playlist: music);
      await player.playNext();
      expect(player.currentTrackPlaylist?.id, music.id);
      expect(player.queue, isEmpty);
      player.dispose();

      player = await createPlayer();
      await player.playNextInQueue(last, playlist: music);
      await player.playNext();
      expect(player.queue, isEmpty);
      player.dispose();
    },
  );

  test(
    'changing the active playlist mode switches queues immediately',
    () async {
      final regularEntry = await saveTrack('regular-entry');
      final bookEntry = await saveTrack('book-entry');
      var player = await createPlayer();
      await player.setActivePlaylist(music, startTrack: track);
      await player.addToQueue(regularEntry, playlist: music);
      await player.setBookMode(music, true);
      expect(player.queue, isEmpty);
      await player.addToQueue(bookEntry, playlist: music);
      player.dispose();
      await reopenQueues();

      player = await createPlayer();
      expect(player.queue.map((t) => t.id), [bookEntry.id]);
      await player.setBookMode(music, false);
      expect(player.queue.map((t) => t.id), [regularEntry.id]);
      await player.setBookMode(music, true);
      expect(player.queue.map((t) => t.id), [bookEntry.id]);
      player.dispose();
    },
  );

  test('Previous retains only the 100 most recent occurrences', () async {
    final oldest = await saveTrack('oldest-previous');
    final newest = await saveTrack('newest-previous');
    await storage.saveQueueSession({
      'playlistId': music.id,
      'currentTrackId': track.id,
      'currentTrackPlaylistId': music.id,
      'history': [
        {'trackId': oldest.id, 'playlistId': music.id},
        for (var i = 0; i < 99; i++)
          {'trackId': track.id, 'playlistId': music.id},
        {'trackId': newest.id, 'playlistId': book.id},
      ],
    });
    var player = await createPlayer();
    await player.playHistoryEntry(player.playbackHistory.first);
    final session = storage.getQueueSession()!;
    final previous = session['previousStack'] as List<dynamic>;
    expect(session, isNot(contains('history')));
    expect(previous.length, 100);
    expect(previous.first['trackId'], track.id);
    expect(previous[98]['trackId'], newest.id);
    player.dispose();

    player = await createPlayer();
    await player.playPrevious();
    await player.playPrevious();
    expect(player.currentTrack?.id, newest.id);
    expect(player.currentTrackPlaylist?.id, book.id);
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
      await player.playPrevious();
      expect(player.currentTrackPlaylist?.id, music.id);
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
