import 'dart:math';
import 'dart:collection';
import 'package:flutter/widgets.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/queue_entry.dart';
import '../models/playback_state.dart' as pstate;
import '../models/settings.dart';
import '../models/exceptions.dart';
import 'dart:async';
import 'hive_storage_service.dart';
import 'audio_player_service.dart';
import 'package:logging/logging.dart';
import 'stats_service.dart';
import 'package:audio_service/audio_service.dart';

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final _log = Logger('PlayerProvider');
  final HiveStorageService _storageService;
  late AudioPlayerService _audioService;

  Playlist? _currentPlaylist;
  Playlist? _playingPlaylist;
  Track? _currentTrack;
  AppSettings _settings = AppSettings();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Queue
  List<QueueEntry> _queue = [];
  String? _bookQueuePlaylistId;
  String? _currentTrackPlaylistId;
  String? _sequenceTrackId;
  bool _sessionReady = false;
  bool _audioReady = false;
  static const int _previousLimit = 100;
  final _history = ListQueue<QueueEntry>();

  List<Track> get _protectedTracks {
    final list = _queue.map((entry) => entry.track).toList();
    if (_currentTrack != null) list.add(_currentTrack!);
    return list;
  }

  DateTime _lastSaveTime = DateTime.now();

  // Stats tracking
  Duration _lastReportedPosition = Duration.zero;
  Duration _accumulatedTime = Duration.zero;
  bool _statsRecorded = false;

  // Error handling
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 20;
  bool _isAdvancingToNextTrack = false;

  bool _isBackground = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  late final Future<void> initialized;
  late final Future<void> _restoredSession;

  PlayerProvider(this._storageService, {AudioPlayerService? audioService}) {
    _audioService = audioService ?? AudioPlayerService(_storageService);
    WidgetsBinding.instance.addObserver(this);
    _restoredSession = _restoreSession();
    initialized = _init();
  }

  @override
  void dispose() {
    _saveCurrentState();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_errorController.close());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveCurrentState();
      _isBackground = true;
    } else if (state == AppLifecycleState.resumed) {
      _isBackground = false;
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    if (!_isBackground) {
      super.notifyListeners();
    }
  }

  Playlist? get currentPlaylist => _currentPlaylist;
  Playlist? get playingPlaylist => _playingPlaylist;
  Playlist? get currentTrackPlaylist =>
      _storageService.getPlaylist(_currentTrackPlaylistId ?? '');
  Track? get currentTrack => _currentTrack;
  AppSettings get settings => _settings;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  List<Track> get queue =>
      List.unmodifiable(_queue.map((entry) => entry.track));
  List<QueueEntry> get playbackHistory =>
      _storageService.getHistory(activePlaylist: _playingPlaylist);

  Track? getTrack(String id) => _storageService.getTrack(id);

  Future<void> _restoreSession() async {
    _settings = _storageService.getSettings();
    final session = _storageService.getQueueSession();
    final playlistId = session == null
        ? _settings.lastActivePlaylistId
        : session['playlistId'] as String?;
    _playingPlaylist = _storageService.getPlaylist(playlistId ?? '');
    _currentPlaylist = _playingPlaylist;
    _bookQueuePlaylistId = _bookQueueId(_playingPlaylist);

    if (session != null) {
      await _migrateQueues(session);
      final history = session['history'] as List<dynamic>? ?? [];
      _history.addAll(
        _restoreEntries(history.skip(max(0, history.length - _previousLimit))),
      );
      _currentTrack = _storageService.getTrack(
        session['currentTrackId'] as String? ?? '',
      );
      _currentTrackPlaylistId = session['currentTrackPlaylistId'] as String?;
      _position = Duration(milliseconds: session['position'] as int? ?? 0);
      _accumulatedTime = Duration(
        milliseconds: session['accumulatedTime'] as int? ?? 0,
      );
      _statsRecorded = session['statsRecorded'] as bool? ?? false;
    } else if (_playingPlaylist != null) {
      final state = _storageService.getPlaybackState(_playingPlaylist!.id);
      if (state != null) {
        _currentTrack = _storageService.getTrack(state.currentTrackId ?? '');
        _currentTrackPlaylistId = state.playlistId;
        _position = state.position;
        _accumulatedTime = state.accumulatedTime;
        _statsRecorded = state.statsRecorded;
      }
    }

    if (session?.containsKey('sequenceTrackId') == true) {
      _sequenceTrackId = session!['sequenceTrackId'] as String?;
    } else if (_playingPlaylist case final active?) {
      _sequenceTrackId = _currentTrackPlaylistId == active.id
          ? _currentTrack?.id
          : _history
                    .where((entry) => entry.playlistId == active.id)
                    .lastOrNull
                    ?.track
                    .id ??
                _storageService.getPlaybackState(active.id)?.currentTrackId;
    }
    _lastReportedPosition = _position;

    final savedQueue = _storageService.getQueue(_bookQueuePlaylistId);
    _queue = _restoreEntries(savedQueue);
    _sessionReady = true;
    if (savedQueue == null && _currentTrack != null) {
      _fillQueue();
    }
  }

  Future<void> _init() async {
    await _restoredSession;
    await _audioService.init(
      onSkipToPrevious: playPrevious,
      onSkipToNext: () => playNext(reason: 'media control'),
    );
    _audioService.setVolume(_settings.volume);
    if (_currentTrack != null) {
      try {
        await _playCurrentTrack(startPaused: true);
        await _audioService.seek(_position);
      } catch (e) {
        _log.warning('Could not restore queued playback', e);
      }
    }
    _audioReady = true;
    _preCacheQueue();

    _subscriptions.add(
      _audioService.audioHandler.playbackState.listen((state) {
        _isPlaying = state.playing;
        notifyListeners();

        if (state.playing &&
            state.processingState == AudioProcessingState.ready) {
          _consecutiveFailures = 0; // Reset failures on successful playback
        }

        if (state.processingState == AudioProcessingState.completed) {
          unawaited(playNext(reason: 'playback completed'));
        }

        if (state.processingState == AudioProcessingState.error) {
          _handlePlaybackError(state.errorMessage ?? "Unknown error");
        }
      }),
    );

    Duration lastProcessedPosition = Duration.zero;

    _subscriptions.add(
      _audioService.positionStream.listen((pos) {
        final step = (pos - lastProcessedPosition).inMilliseconds.abs();

        // Throttle updates: Skip if the update is less than 1 second (1000ms)
        if (step < 1000 && step > 0) {
          return;
        }
        lastProcessedPosition = pos;

        _position = pos;
        notifyListeners();

        if (_currentTrack != null && _isPlaying) {
          // Calculate time delta
          final diff = pos - _lastReportedPosition;
          if (diff > Duration.zero && diff < const Duration(seconds: 5)) {
            _accumulatedTime += diff;

            // Check if we should record a play
            if (!_statsRecorded &&
                _currentTrack!.duration.inSeconds > 0 &&
                _accumulatedTime.inSeconds >=
                    _currentTrack!.duration.inSeconds / 2) {
              if (currentTrackPlaylist?.excludeFromStatistics != true) {
                StatsService().recordPlay(_currentTrack!);
              }
              _statsRecorded = true;
            }
          }
        }

        _lastReportedPosition = pos;

        // Throttle database writes to every 20 seconds
        if (DateTime.now().difference(_lastSaveTime).inSeconds >= 20) {
          _saveCurrentState();
          _lastSaveTime = DateTime.now();
        }
      }),
    );

    _subscriptions.add(
      _audioService.audioHandler.mediaItem.listen((item) {
        if (item != null && item.duration != null) {
          _duration = item.duration!;
          notifyListeners();
        }
      }),
    );

    notifyListeners();
  }

  void _fillQueue() {
    Playlist? targetPlaylist = _playingPlaylist;

    if (targetPlaylist == null) {
      _persistQueue();
      return;
    }

    // We want to maintain a queue of upcoming tracks.
    // Let's keep at least 5 tracks in the queue.
    int targetQueueSize = 5;

    if (_queue.length < targetQueueSize) {
      final ids = targetPlaylist.trackIds
          .where((id) => _storageService.getTrack(id) != null)
          .toList();
      if (ids.isEmpty) {
        _persistQueue();
        return;
      }

      if (_settings.shuffle && !targetPlaylist.isBookMode) {
        final random = Random();
        while (_queue.length < targetQueueSize) {
          final nextId = ids[random.nextInt(ids.length)];
          final track = _storageService.getTrack(nextId);
          if (track != null) {
            _queue.add(QueueEntry(track, playlistId: targetPlaylist.id));
          }
        }
      } else {
        // Add next tracks in order
        var startIdx = ids.indexOf(_sequenceTrackId ?? '');
        for (final entry in _queue.reversed) {
          if (entry.playlistId != targetPlaylist.id) continue;
          final index = ids.indexOf(entry.track.id);
          if (index == -1) continue;
          startIdx = index;
          break;
        }

        while (_queue.length < targetQueueSize) {
          startIdx++;
          if (startIdx >= ids.length) {
            if (_settings.repeatMode == 1 && !targetPlaylist.isBookMode) {
              // repeat all
              startIdx = 0;
            } else {
              break; // Reached end of playlist without repeat or in book mode
            }
          }
          final track = _storageService.getTrack(ids[startIdx]);
          if (track != null) {
            _queue.add(QueueEntry(track, playlistId: targetPlaylist.id));
          }
        }
      }
    }

    _preCacheQueue();
    _persistQueue();
    notifyListeners();
  }

  void _preCacheQueue() {
    if (!_audioReady) return;
    for (int i = 0; i < min(2, _queue.length); i++) {
      _audioService.preCacheTrack(
        _queue[i].track,
        protectedTracks: _protectedTracks,
      );
    }
  }

  Future<void> playNextInQueue(Track track, {Playlist? playlist}) =>
      enqueue(QueueEntry(track, playlistId: playlist?.id), playNext: true);

  Future<void> addToQueue(Track track, {Playlist? playlist}) =>
      enqueue(QueueEntry(track, playlistId: playlist?.id));

  Future<void> enqueue(QueueEntry entry, {bool playNext = false}) async {
    if (!_sessionReady) await _restoredSession;
    if (playNext) {
      _queue.insert(0, entry);
      _preCacheQueue();
    } else {
      _queue.add(entry);
    }
    _persistQueue();
    notifyListeners();
  }

  void removeFromQueue(Track track) {
    final index = _queue.indexWhere((entry) => identical(entry.track, track));
    if (index != -1) removeFromQueueAt(index);
  }

  void removeFromQueueAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    _preCacheQueue();
    _persistQueue();
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length || oldIndex == newIndex) {
      return;
    }

    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);

    _preCacheQueue();
    _persistQueue();
    notifyListeners();
  }

  Future<void> resumePlaylist(Playlist playlist) async {
    if (!_audioReady) await initialized;
    _saveCurrentState();
    final state = _storageService.getPlaybackState(playlist.id);
    final bookmarkedTrack = _storageService.getTrack(
      state?.currentTrackId ?? '',
    );
    final startTrack =
        bookmarkedTrack ??
        playlist.trackIds
            .map(_storageService.getTrack)
            .whereType<Track>()
            .firstOrNull;
    if (startTrack == null) return;
    await _startPlaylist(
      playlist,
      startTrack: startTrack,
      preserveQueue: true,
      resumeState: bookmarkedTrack == null ? null : state,
    );
  }

  void selectPlaylist(Playlist playlist) {
    _currentPlaylist = playlist;
    notifyListeners();
  }

  Future<void> setActivePlaylist(
    Playlist playlist, {
    Track? startTrack,
    bool startPaused = false,
  }) => _startPlaylist(
    playlist,
    startTrack: startTrack,
    startPaused: startPaused,
  );

  bool _switchQueue(Playlist playlist) {
    final bookId = _bookQueueId(playlist);
    if (bookId == _bookQueuePlaylistId) return false;
    _bookQueuePlaylistId = bookId;
    _queue = _restoreEntries(_storageService.getQueue(bookId));
    _history.clear();
    return true;
  }

  Future<void> setBookMode(Playlist playlist, bool enabled) async {
    if (!_sessionReady) await _restoredSession;
    final isActive = _playingPlaylist?.id == playlist.id;
    if (isActive) _saveCurrentState();
    playlist.isBookMode = enabled;
    final saved = _storageService.savePlaylist(playlist);
    if (isActive) {
      _playingPlaylist = playlist;
      if (_switchQueue(playlist)) {
        if (_storageService.getQueue(_bookQueuePlaylistId) == null) {
          _fillQueue();
        } else {
          _preCacheQueue();
        }
        _saveCurrentState();
        notifyListeners();
      }
    }
    await saved;
  }

  Future<void> _startPlaylist(
    Playlist playlist, {
    Track? startTrack,
    bool startPaused = false,
    bool preserveQueue = false,
    pstate.PlaybackState? resumeState,
  }) async {
    if (!_audioReady) await initialized;
    _saveCurrentState();
    _settings.lastActivePlaylistId = playlist.id;
    _storageService.saveSettings(_settings);

    final switchedQueue = _switchQueue(playlist);
    final changedPlaylist = _playingPlaylist?.id != playlist.id;
    if (changedPlaylist) {
      _sequenceTrackId = playlist.isBookMode
          ? _storageService.getPlaybackState(playlist.id)?.currentTrackId
          : null;
    }

    _playingPlaylist = playlist;

    if (startTrack != null) {
      if (!switchedQueue && _currentTrack?.id != startTrack.id) {
        _rememberCurrentEntry();
      }
      _setCurrentEntry(QueueEntry(startTrack, playlistId: playlist.id));
      if (resumeState != null) {
        _accumulatedTime = resumeState.accumulatedTime;
        _statsRecorded = resumeState.statsRecorded;
        _position = resumeState.position;
        _lastReportedPosition = _position;
      }
    }

    final restartEmptyBook =
        playlist.isBookMode &&
        startTrack != null &&
        !preserveQueue &&
        _queue.isEmpty;
    if (_storageService.getQueue(_bookQueuePlaylistId) == null ||
        restartEmptyBook ||
        (!switchedQueue &&
            !playlist.isBookMode &&
            changedPlaylist &&
            _queue.isEmpty)) {
      _fillQueue();
    } else {
      _preCacheQueue();
    }
    _saveCurrentState();
    notifyListeners();

    if (startTrack != null) {
      try {
        await _playCurrentTrack(startPaused: startPaused);
        if (resumeState != null &&
            identical(_currentTrack, startTrack) &&
            _playingPlaylist?.id == playlist.id) {
          await seek(resumeState.position);
        }
      } catch (e) {
        _handlePlaybackError(e);
      }
    }
  }

  void _resetStatsForNewTrack() {
    _accumulatedTime = Duration.zero;
    _statsRecorded = false;
    _position = Duration.zero;
    _lastReportedPosition = Duration.zero;
  }

  void _setCurrentEntry(QueueEntry entry) {
    _resetStatsForNewTrack();
    _currentTrack = entry.track;
    _currentTrackPlaylistId = entry.playlistId;
    final active = _playingPlaylist;
    if (active != null &&
        entry.playlistId == active.id &&
        active.trackIds.contains(entry.track.id)) {
      _sequenceTrackId = entry.track.id;
    }
  }

  void _rememberCurrentEntry() {
    final track = _currentTrack;
    if (track == null) return;
    _history.addLast(QueueEntry(track, playlistId: _currentTrackPlaylistId));
    if (_history.length > _previousLimit) _history.removeFirst();
  }

  Future<void> _playCurrentTrack({bool startPaused = false}) async {
    final entry = QueueEntry(
      _currentTrack!,
      playlistId: _currentTrackPlaylistId,
    );
    await _audioService.playTrack(
      entry.track,
      protectedTracks: _protectedTracks,
      startPaused: startPaused,
    );
    try {
      await _storageService.addToHistory(entry);
    } catch (e) {
      _log.warning('Could not save playback history', e);
    }
  }

  Future<void> playTrackDirectly(Track track, {Playlist? playlist}) async {
    if (!_audioReady) await initialized;
    final source = playlist ?? _playingPlaylist ?? _currentPlaylist;
    if (source != null) {
      await setActivePlaylist(source, startTrack: track);
      return;
    }
    await playHistoryEntry(QueueEntry(track));
  }

  Future<void> playHistoryEntry(QueueEntry entry) async {
    if (!_audioReady) await initialized;
    _saveCurrentState();
    _rememberCurrentEntry();
    _setCurrentEntry(entry);
    _saveCurrentState();

    notifyListeners();

    try {
      await _playCurrentTrack();
    } catch (e) {
      _handlePlaybackError(e);
    }
  }

  Future<void> play() async {
    if (!_audioReady) await initialized;
    if (_currentTrack != null && !_isPlaying) {
      await _audioService.play();
    }
  }

  Future<void> pause() async {
    if (!_audioReady) await initialized;
    if (_isPlaying) {
      await _audioService.pause();
      _saveCurrentState(); // Always save on pause
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> playNext({String reason = 'user request'}) async {
    if (!_audioReady) await initialized;
    if (_isAdvancingToNextTrack) {
      _log.warning(
        'Ignoring overlapping playNext: reason=$reason, '
        'current=${_currentTrack?.id}',
      );
      return;
    }

    _isAdvancingToNextTrack = true;
    final previousTrackId = _currentTrack?.id;
    try {
      if (_currentTrack != null) {
        // Repeat One (2) - just replay the current track
        if (_settings.repeatMode == 2) {
          _resetStatsForNewTrack();
          _saveCurrentState();
          await _audioService.seek(Duration.zero);
          await _playCurrentTrack();
          return;
        }
      }

      if (_queue.isNotEmpty) {
        _rememberCurrentEntry();
        final nextEntry = _queue.removeAt(0);
        _setCurrentEntry(nextEntry);
        _fillQueue();
        _saveCurrentState();
        notifyListeners();
        try {
          await _playCurrentTrack();
        } catch (e, stackTrace) {
          _log.severe(
            'Next track handoff failed: from=$previousTrackId, '
            'to=${nextEntry.track.id}',
            e,
            stackTrace,
          );
          _handlePlaybackError(e);
        }
      } else {
        _log.warning(
          'playNext found an empty queue: current=$previousTrackId, '
          'playlist=${_playingPlaylist?.id}, '
          'playlistTracks=${_playingPlaylist?.trackIds.length ?? 0}',
        );
      }
    } finally {
      _isAdvancingToNextTrack = false;
    }
  }

  Future<void> playPrevious() async {
    if (!_audioReady) await initialized;
    final QueueEntry entry;
    if (_history.isNotEmpty) {
      entry = _history.removeLast();
    } else {
      final active = _playingPlaylist;
      if (active == null || _currentTrack == null) return;
      final index = active.trackIds.indexOf(_sequenceTrackId ?? '');
      if (index <= 0) return;
      final track = _storageService.getTrack(active.trackIds[index - 1]);
      if (track == null) return;
      entry = QueueEntry(track, playlistId: active.id);
    }
    final current = _currentTrack;
    if (current != null) {
      _queue.insert(
        0,
        QueueEntry(current, playlistId: _currentTrackPlaylistId),
      );
    }
    _setCurrentEntry(entry);
    _preCacheQueue();
    _persistQueue();
    _saveCurrentState();
    notifyListeners();
    try {
      await _playCurrentTrack();
    } catch (e) {
      _handlePlaybackError(e);
    }
  }

  void _handlePlaybackError(Object e) {
    _log.severe('Playback error caught in provider: $e');
    _consecutiveFailures++;

    final trackName = _currentTrack?.title ?? 'Unknown Track';
    String errorMessage;
    if (e is TrackRemovedException) {
      errorMessage = e.toString();
    } else {
      errorMessage = 'Failed to play "$trackName". Error: $e';
    }

    _errorController.add(errorMessage);

    if (_consecutiveFailures < _maxConsecutiveFailures) {
      _log.info(
        'Skipping to next track due to error. Failure $_consecutiveFailures/$_maxConsecutiveFailures',
      );
      // Wait for player state to reset before trying to play the next track
      Future.delayed(const Duration(milliseconds: 500), () {
        playNext();
      });
    } else {
      _log.severe(
        'Too many consecutive failures ($_maxConsecutiveFailures). Stopping playback.',
      );
      _errorController.add('Too many errors. Stopping playback.');
      pause();
    }
  }

  Future<void> seek(Duration position) async {
    if (!_audioReady) await initialized;
    await _audioService.seek(position);
    _position = position;
    _lastReportedPosition = position;
    _saveCurrentState(); // Save after seeking
  }

  Future<void> setVolume(double volume) async {
    if (!_audioReady) await initialized;
    _settings.volume = volume;
    await _storageService.saveSettings(_settings);
    await _audioService.setVolume(volume);
    notifyListeners();
  }

  List<QueueEntry> _restoreEntries(Iterable<dynamic>? data) => (data ?? [])
      .map(
        (value) => QueueEntry.fromJson(
          Map<String, dynamic>.from(value as Map),
          _storageService.getTrack,
        ),
      )
      .whereType<QueueEntry>()
      .toList();

  String? _bookQueueId(Playlist? playlist) =>
      playlist?.isBookMode == true ? playlist!.id : null;

  Future<void> _migrateQueues(Map<String, dynamic> session) async {
    // The first queue format stored the active queue and a suspended regular
    // queue in the playback session. Import each only if it has no own record.
    final regularQueue = session['savedRegularQueue'] as List<dynamic>?;
    final activeQueue = session['queue'] as List<dynamic>?;
    final activeBookId = regularQueue != null
        ? session['playlistId'] as String?
        : _bookQueuePlaylistId;

    Future<void> importQueue(String? bookId, List<dynamic>? entries) async {
      if (entries == null || _storageService.getQueue(bookId) != null) return;
      await _storageService.saveQueue(
        bookId,
        _restoreEntries(entries).map((entry) => entry.toJson()).toList(),
      );
    }

    await importQueue(null, regularQueue);
    await importQueue(activeBookId, activeQueue);
  }

  void _persistQueue() {
    if (!_sessionReady) return;
    unawaited(
      _storageService.saveQueue(
        _bookQueuePlaylistId,
        _queue.map((entry) => entry.toJson()).toList(),
      ),
    );
  }

  void _persistSession() {
    if (!_sessionReady) return;
    unawaited(
      _storageService.saveQueueSession({
        'playlistId': _playingPlaylist?.id,
        'currentTrackId': _currentTrack?.id,
        'currentTrackPlaylistId': _currentTrackPlaylistId,
        'sequenceTrackId': _sequenceTrackId,
        'position': _position.inMilliseconds,
        'accumulatedTime': _accumulatedTime.inMilliseconds,
        'statsRecorded': _statsRecorded,
        'history': _history.map((entry) => entry.toJson()).toList(),
      }),
    );
  }

  void _saveCurrentState() {
    _persistSession();
    final targetPlaylist = currentTrackPlaylist;

    // Playing a chapter from another queue should keep that book's bookmark.
    if (targetPlaylist != null &&
        _currentTrack != null &&
        (!targetPlaylist.isBookMode ||
            _bookQueuePlaylistId == targetPlaylist.id)) {
      final state = pstate.PlaybackState(
        playlistId: targetPlaylist.id,
        currentTrackId: _currentTrack!.id,
        position: _position,
        accumulatedTime: _accumulatedTime,
        statsRecorded: _statsRecorded,
      );
      _storageService.savePlaybackState(state);
    }
  }

  Future<void> toggleShuffle() async {
    if (!_sessionReady) await _restoredSession;
    _settings.shuffle = !_settings.shuffle;
    await _storageService.saveSettings(_settings);

    _queue.clear();
    _fillQueue();

    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    if (!_sessionReady) await _restoredSession;
    _settings.repeatMode = (_settings.repeatMode + 1) % 3;
    await _storageService.saveSettings(_settings);

    if (_queue.isEmpty) {
      _fillQueue();
    }

    notifyListeners();
  }

  Future<void> syncTrackMetadata(Track track) async {
    await _audioService.syncMetadataAsync(track, force: true);
    notifyListeners();
  }
}
