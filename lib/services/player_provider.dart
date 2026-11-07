import 'dart:math';
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
  String? _currentTrackPlaylistId;
  bool _sessionReady = false;
  final List<QueueEntry> _history = [];

  // Isolated queue for Book Mode
  List<QueueEntry>? _savedRegularQueue;

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

  PlayerProvider(this._storageService, {AudioPlayerService? audioService}) {
    _audioService = audioService ?? AudioPlayerService(_storageService);
    WidgetsBinding.instance.addObserver(this);
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
  List<Track> get playbackHistory => _storageService
      .getHistory()
      .reversed
      .map(_storageService.getTrack)
      .whereType<Track>()
      .toList(growable: false);

  Track? getTrack(String id) => _storageService.getTrack(id);

  Future<void> _init() async {
    await _audioService.init(
      onSkipToPrevious: playPrevious,
      onSkipToNext: () => playNext(reason: 'media control'),
    );
    _settings = _storageService.getSettings();
    _audioService.setVolume(_settings.volume);

    final session = _storageService.getQueueSession();
    if (session != null) {
      _playingPlaylist = _storageService.getPlaylist(
        session['playlistId'] as String? ?? '',
      );
      _currentPlaylist = _playingPlaylist;
      _queue = _restoreEntries(session['queue']);
      _savedRegularQueue = session['savedRegularQueue'] == null
          ? null
          : _restoreEntries(session['savedRegularQueue']);
      _history.addAll(_restoreEntries(session['history']));
      _currentTrack = _storageService.getTrack(
        session['currentTrackId'] as String? ?? '',
      );
      _currentTrackPlaylistId = session['currentTrackPlaylistId'] as String?;
      _position = Duration(milliseconds: session['position'] as int? ?? 0);
      _accumulatedTime = Duration(
        milliseconds: session['accumulatedTime'] as int? ?? 0,
      );
      _statsRecorded = session['statsRecorded'] as bool? ?? false;
      _lastReportedPosition = _position;
      if (_currentTrack != null) {
        try {
          await _audioService.playTrack(_currentTrack!, startPaused: true);
          await _audioService.seek(_position);
        } catch (e) {
          _log.warning('Could not restore queued playback', e);
        }
      }
    }

    // Restore legacy state when no queue snapshot exists.
    if (session == null && _settings.lastActivePlaylistId != null) {
      final activePlaylist = _storageService.getPlaylist(
        _settings.lastActivePlaylistId!,
      );
      if (activePlaylist != null) {
        _playingPlaylist = activePlaylist;
        _currentPlaylist = activePlaylist;
        _currentTrackPlaylistId = activePlaylist.id;
        final state = _storageService.getPlaybackState(activePlaylist.id);
        if (state != null && state.currentTrackId != null) {
          _currentTrack = _storageService.getTrack(state.currentTrackId!);
          _position = state.position;
          _accumulatedTime = state.accumulatedTime;
          _statsRecorded = state.statsRecorded;

          _fillQueue();

          if (_currentTrack != null) {
            try {
              if (_currentTrack!.localCachePath != null) {
                await _audioService.playTrack(
                  _currentTrack!,
                  startPaused: true,
                );
                await _audioService.seek(_position);
              } else {
                _log.severe(
                  'Something wrong with localCachePath of current track ${_currentTrack!.localCachePath}',
                );
                await _audioService.playTrack(
                  _currentTrack!,
                  startPaused: true,
                );
              }
            } catch (e) {
              _log.severe(
                'Playback error caught in provider in starting current track: $e',
              );
            }
          }
        }
      }
    }

    _sessionReady = true;

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
      _persistSession();
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
        _persistSession();
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
        int startIdx = 0;
        if (_currentTrack != null) {
          startIdx = ids.indexOf(_currentTrack!.id);
        }

        // Start searching for next tracks
        // if queue is not empty, start from the last track in the queue
        if (_queue.isNotEmpty) {
          final lastQueueTrackId = _queue.last.track.id;
          final idx = ids.indexOf(lastQueueTrackId);
          if (idx != -1) {
            startIdx = idx;
          }
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

    // Pre-cache next 2 tracks
    for (int i = 0; i < min(2, _queue.length); i++) {
      _audioService.preCacheTrack(
        _queue[i].track,
        protectedTracks: _protectedTracks,
      );
    }

    _persistSession();
    notifyListeners();
  }

  void playNextInQueue(Track track, {Playlist? playlist}) {
    _queue.insert(0, QueueEntry(track, playlistId: playlist?.id));
    _audioService.preCacheTrack(track, protectedTracks: _protectedTracks);
    _persistSession();
    notifyListeners();
  }

  void addToQueue(Track track, {Playlist? playlist}) {
    _queue.add(QueueEntry(track, playlistId: playlist?.id));
    _persistSession();
    notifyListeners();
  }

  void removeFromQueue(Track track) {
    final index = _queue.indexWhere((entry) => identical(entry.track, track));
    if (index != -1) removeFromQueueAt(index);
  }

  void removeFromQueueAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    _fillQueue();
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length || oldIndex == newIndex) {
      return;
    }

    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);

    for (int i = 0; i < min(2, _queue.length); i++) {
      _audioService.preCacheTrack(
        _queue[i].track,
        protectedTracks: _protectedTracks,
      );
    }
    _persistSession();
    notifyListeners();
  }

  Future<void> resumePlaylist(Playlist playlist) async {
    final state = _storageService.getPlaybackState(playlist.id);
    if (state != null && state.currentTrackId != null) {
      final track = _storageService.getTrack(state.currentTrackId!);
      if (track != null) {
        _position = state.position;
        _accumulatedTime = state.accumulatedTime;
        _statsRecorded = state.statsRecorded;

        // Start track but keep it paused initially? No, the requirement says:
        // "When I click on the playlist with book view... resume block appears... play or go back"
        // Wait, "if I select the playlist the last saved point is restored and playing is stopped."

        // When clicking resume, it should start playing.
        await setActivePlaylist(playlist, startTrack: track);
        _accumulatedTime = state.accumulatedTime;
        _statsRecorded = state.statsRecorded;
        await seek(state.position);
      }
    } else if (playlist.trackIds.isNotEmpty) {
      final track = _storageService.getTrack(playlist.trackIds.first);
      if (track != null) {
        await setActivePlaylist(playlist, startTrack: track);
      }
    }
  }

  void selectPlaylist(Playlist playlist) {
    _currentPlaylist = playlist;
    notifyListeners();
  }

  Future<void> setActivePlaylist(
    Playlist playlist, {
    Track? startTrack,
    bool startPaused = false,
  }) async {
    _saveCurrentState();
    _settings.lastActivePlaylistId = playlist.id;
    _storageService.saveSettings(_settings);

    final wasBookMode = _playingPlaylist?.isBookMode ?? false;
    final isBookMode = playlist.isBookMode;

    if (isBookMode && !wasBookMode) {
      _savedRegularQueue = List<QueueEntry>.from(_queue);
      _queue.clear();
    } else if (!isBookMode && wasBookMode) {
      if (_savedRegularQueue != null) {
        _queue = List<QueueEntry>.from(_savedRegularQueue!);
        _savedRegularQueue = null;
      } else {
        _queue.clear();
      }
    } else {
      _queue.clear();
    }

    _playingPlaylist = playlist;

    if (startTrack != null) {
      if (_currentTrack != null && _currentTrack?.id != startTrack.id) {
        _history.add(
          QueueEntry(_currentTrack!, playlistId: _currentTrackPlaylistId),
        );
        _resetStatsForNewTrack();
      }
      _currentTrack = startTrack;
      _currentTrackPlaylistId = playlist.id;
      _resetStatsForNewTrack();
      _position = Duration.zero;
    }

    _fillQueue();
    _saveCurrentState();
    notifyListeners();

    if (startTrack != null && _currentTrack != null) {
      try {
        if (startPaused) {
          await _audioService.playTrack(
            _currentTrack!,
            protectedTracks: _protectedTracks,
          );
          await pause();
        } else {
          await _audioService.playTrack(
            _currentTrack!,
            protectedTracks: _protectedTracks,
          );
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

  Future<void> playTrackDirectly(Track track, {Playlist? playlist}) async {
    if (playlist != null && playlist.id != _playingPlaylist?.id) {
      await setActivePlaylist(playlist, startTrack: track);
      return;
    }
    if (_playingPlaylist == null) {
      if (_currentPlaylist != null) {
        await setActivePlaylist(_currentPlaylist!, startTrack: track);
      }
      return;
    }

    if (_currentTrack != null && _currentTrack?.id != track.id) {
      _history.add(
        QueueEntry(_currentTrack!, playlistId: _currentTrackPlaylistId),
      );
      _resetStatsForNewTrack();
    }
    _currentTrack = track;
    _currentTrackPlaylistId = playlist?.id;
    _position = Duration.zero;
    _saveCurrentState();

    notifyListeners();

    try {
      await _audioService.playTrack(track, protectedTracks: _protectedTracks);
    } catch (e) {
      _handlePlaybackError(e);
    }
  }

  Future<void> play() async {
    if (_currentTrack != null && !_isPlaying) {
      await _audioService.play();
    }
  }

  Future<void> pause() async {
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
          await _audioService.playTrack(
            _currentTrack!,
            protectedTracks: _protectedTracks,
          );
          return;
        }
        _history.add(
          QueueEntry(_currentTrack!, playlistId: _currentTrackPlaylistId),
        );
      }

      if (_queue.isNotEmpty) {
        final nextEntry = _queue.removeAt(0);
        final nextTrack = nextEntry.track;
        _resetStatsForNewTrack();
        _currentTrack = nextTrack;
        _currentTrackPlaylistId = nextEntry.playlistId;
        _position = Duration.zero;
        _fillQueue();
        notifyListeners();
        try {
          await _audioService.playTrack(
            nextTrack,
            protectedTracks: _protectedTracks,
          );
        } catch (e, stackTrace) {
          _log.severe(
            'Next track handoff failed: from=$previousTrackId, '
            'to=${nextTrack.id}',
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
    if (_history.isNotEmpty) {
      if (_currentTrack != null) {
        _queue.insert(
          0,
          QueueEntry(_currentTrack!, playlistId: _currentTrackPlaylistId),
        );
      }
      final prevEntry = _history.removeLast();
      final prevTrack = prevEntry.track;
      _currentTrackPlaylistId = prevEntry.playlistId;
      _position = Duration.zero;
      if (_currentTrack?.id != prevTrack.id) {
        _resetStatsForNewTrack();
      }
      _currentTrack = prevTrack;
      _saveCurrentState();
      notifyListeners();
      try {
        await _audioService.playTrack(
          prevTrack,
          protectedTracks: _protectedTracks,
        );
      } catch (e) {
        _handlePlaybackError(e);
      }
    } else {
      // Fallback to legacy behaviour if history is empty (e.g. initial launch)
      if (_playingPlaylist == null || _currentTrack == null) return;
      final ids = _playingPlaylist!.trackIds;
      final index = ids.indexOf(_currentTrack!.id);
      if (index > 0) {
        final prevTrack = _storageService.getTrack(ids[index - 1]);
        if (prevTrack != null) {
          if (_currentTrack?.id != prevTrack.id) {
            _resetStatsForNewTrack();
          }
          _currentTrack = prevTrack;
          _currentTrackPlaylistId = _playingPlaylist!.id;
          _queue.clear();
          _fillQueue();
          notifyListeners();
          try {
            await _audioService.playTrack(
              prevTrack,
              protectedTracks: _protectedTracks,
            );
          } catch (e) {
            _handlePlaybackError(e);
          }
        }
      }
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
    await _audioService.seek(position);
    _position = position;
    _lastReportedPosition = position;
    _saveCurrentState(); // Save after seeking
  }

  Future<void> setVolume(double volume) async {
    _settings.volume = volume;
    await _storageService.saveSettings(_settings);
    await _audioService.setVolume(volume);
    notifyListeners();
  }

  List<QueueEntry> _restoreEntries(dynamic data) =>
      (data as List<dynamic>? ?? [])
          .map(
            (value) => QueueEntry.fromJson(
              Map<String, dynamic>.from(value as Map),
              _storageService.getTrack,
            ),
          )
          .whereType<QueueEntry>()
          .toList();

  void _persistSession() {
    if (!_sessionReady) return;
    unawaited(
      _storageService.saveQueueSession({
        'playlistId': _playingPlaylist?.id,
        'currentTrackId': _currentTrack?.id,
        'currentTrackPlaylistId': _currentTrackPlaylistId,
        'position': _position.inMilliseconds,
        'accumulatedTime': _accumulatedTime.inMilliseconds,
        'statsRecorded': _statsRecorded,
        'queue': _queue.map((entry) => entry.toJson()).toList(),
        'savedRegularQueue': _savedRegularQueue
            ?.map((entry) => entry.toJson())
            .toList(),
        'history': _history.map((entry) => entry.toJson()).toList(),
      }),
    );
  }

  void _saveCurrentState() {
    _persistSession();
    final targetPlaylist = currentTrackPlaylist;

    if (targetPlaylist != null && _currentTrack != null) {
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
    _settings.shuffle = !_settings.shuffle;
    await _storageService.saveSettings(_settings);

    _queue.clear();
    _fillQueue();

    notifyListeners();
  }

  Future<void> toggleRepeat() async {
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
