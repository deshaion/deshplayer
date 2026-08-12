import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/playback_state.dart' as pstate;
import '../models/settings.dart';
import '../models/exceptions.dart';
import 'dart:async';
import 'hive_storage_service.dart';
import 'audio_player_service.dart';
import 'package:logging/logging.dart';
import 'stats_service.dart';
import 'package:just_audio_background/just_audio_background.dart';

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
  List<Track> _queue = [];
  final List<Track> _history = [];

  // Isolated queue for Book Mode
  List<Track>? _savedRegularQueue;

  List<Track> get _protectedTracks {
    final list = List<Track>.from(_queue);
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

  bool _isBackground = false;

  PlayerProvider(this._storageService) {
    _audioService = AudioPlayerService(_storageService);
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
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
  Track? get currentTrack => _currentTrack;
  AppSettings get settings => _settings;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  List<Track> get queue => _queue;

  AudioPlayer get audioPlayer => _audioService.player; // expose for streams

  Track? getTrack(String id) => _storageService.getTrack(id);

  Future<void> _init() async {
    _settings = _storageService.getSettings();
    _audioService.setVolume(_settings.volume);

    // Restore state
    if (_settings.lastActivePlaylistId != null) {
      final activePlaylist = _storageService.getPlaylist(
        _settings.lastActivePlaylistId!,
      );
      if (activePlaylist != null) {
        _playingPlaylist = activePlaylist;
        _currentPlaylist = activePlaylist;
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
                await _audioService.player.setAudioSource(
                  AudioSource.uri(
                    Uri.file(_currentTrack!.localCachePath!),
                    tag: MediaItem(
                      id: _currentTrack!.id,
                      album: 'DeshPlayer',
                      title: _currentTrack!.title ?? 'Unknown Track',
                      artist: _currentTrack!.artist ?? 'Unknown Artist',
                    ),
                  ),
                );
                await _audioService.seek(_position);
              } else {
                _log.severe('Something wrong with localCachePath of current track ${_currentTrack!.localCachePath}');
                await _audioService.playTrack(_currentTrack!);
              }
            } catch (e) {
              _log.severe('Playback error caught in provider in starting current track: $e');
            }
          }
        }
      }
    }

    _audioService.player.playbackEventStream.listen((event) {},
      onError: (Object e, StackTrace stackTrace) {        
          _handlePlaybackError(e);
      },
    );

    _audioService.player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();

      if (state.playing && state.processingState == ProcessingState.ready) {
        _consecutiveFailures = 0; // Reset failures on successful playback
      }

      if (state.processingState == ProcessingState.completed) {
        playNext();
      }
    });

    Duration lastProcessedPosition = Duration.zero;

    _audioService.player.positionStream.listen((pos) {
      final step = (pos - lastProcessedPosition).inMilliseconds.abs();

      // Throttle updates: Skip if the update is less than 1 second (1000ms)
      if (step < 1000 && step > 0) {
        return;
      }
      lastProcessedPosition = pos;

      _position = pos;
      notifyListeners();

      if (_currentPlaylist != null && _currentTrack != null) {
        // Calculate time delta
        final diff = pos - _lastReportedPosition;
        if (diff > Duration.zero && diff < const Duration(seconds: 5)) {
          _accumulatedTime += diff;

          // Check if we should record a play
          if (!_statsRecorded &&
              _currentTrack!.duration.inSeconds > 0 &&
              _accumulatedTime.inSeconds >=
                  _currentTrack!.duration.inSeconds / 2) {
            if (_playingPlaylist?.excludeFromStatistics != true) {
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
    });

    _audioService.player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    notifyListeners();
  }

  void _fillQueue() {
    Playlist? targetPlaylist = _playingPlaylist;

    if (targetPlaylist == null) return;

    // We want to maintain a queue of upcoming tracks.
    // Let's keep at least 5 tracks in the queue.
    int targetQueueSize = 5;

    if (_queue.length < targetQueueSize) {
      final ids = targetPlaylist.trackIds;
      if (ids.isEmpty) return;

      if (_settings.shuffle && !targetPlaylist.isBookMode) {
        final random = Random();
        while (_queue.length < targetQueueSize) {
          final nextId = ids[random.nextInt(ids.length)];
          final track = _storageService.getTrack(nextId);
          if (track != null) {
            _queue.add(track);
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
          final lastQueueTrackId = _queue.last.id;
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
            _queue.add(track);
          }
        }
      }
    }

    // Pre-cache next 2 tracks
    for (int i = 0; i < min(2, _queue.length); i++) {
      _audioService.preCacheTrack(_queue[i], protectedTracks: _protectedTracks);
    }

    notifyListeners();
  }

  void playNextInQueue(Track track) {
    _queue.insert(0, track);
    notifyListeners();
  }

  void addToQueue(Track track) {
    _queue.add(track);
    notifyListeners();
  }

  void removeFromQueue(Track track) {
    _queue.remove(track);
    _fillQueue();
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

  Future<void> setActivePlaylist(Playlist playlist, {Track? startTrack, bool startPaused = false}) async {
    _settings.lastActivePlaylistId = playlist.id;
    _storageService.saveSettings(_settings);

    final wasBookMode = _playingPlaylist?.isBookMode ?? false;
    final isBookMode = playlist.isBookMode;

    if (isBookMode && !wasBookMode) {
      _savedRegularQueue = List<Track>.from(_queue);
      _queue.clear();
    } else if (!isBookMode && wasBookMode) {
      if (_savedRegularQueue != null) {
        _queue = List<Track>.from(_savedRegularQueue!);
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
        _history.add(_currentTrack!);
        _resetStatsForNewTrack();
      }
      _currentTrack = startTrack;
    }

    _fillQueue();
    notifyListeners();

    if (startTrack != null && _currentTrack != null) {
      try {
        if (startPaused) {
           await _audioService.playTrack(_currentTrack!, protectedTracks: _protectedTracks);
           await pause();
        } else {
           await _audioService.playTrack(_currentTrack!, protectedTracks: _protectedTracks);
        }
      } catch (e) {
        _handlePlaybackError(e);
      }
    }
  }

  void _resetStatsForNewTrack() {
    _accumulatedTime = Duration.zero;
    _statsRecorded = false;
    _lastReportedPosition = Duration.zero;
  }

  Future<void> playTrackDirectly(Track track) async {
    if (_playingPlaylist == null) {
      if (_currentPlaylist != null) {
        await setActivePlaylist(_currentPlaylist!, startTrack: track);
      }
      return;
    }

    if (_currentTrack != null && _currentTrack?.id != track.id) {
      _history.add(_currentTrack!);
      _resetStatsForNewTrack();
    }
    _currentTrack = track;

    notifyListeners();

    try {
      await _audioService.playTrack(track, protectedTracks: _protectedTracks);
    } catch (e) {
      _handlePlaybackError(e);
    }
  }

  Future<void> play() async {
    if (_currentTrack != null && !_isPlaying) {
      _audioService.player.play();
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

  Future<void> playNext() async {
    if (_currentTrack != null) {
      // Repeat One (2) - just replay the current track
      if (_settings.repeatMode == 2) {
        await _audioService.seek(Duration.zero);
        await _audioService.playTrack(_currentTrack!, protectedTracks: _protectedTracks);
        return;
      }
      _history.add(_currentTrack!);
    }

    if (_queue.isNotEmpty) {
      final nextTrack = _queue.removeAt(0);
      if (_currentTrack?.id != nextTrack.id) {
        _resetStatsForNewTrack();
      }
      _currentTrack = nextTrack;
      _fillQueue();
      notifyListeners();
      try {
        await _audioService.playTrack(nextTrack, protectedTracks: _protectedTracks);
      } catch (e) {
        _handlePlaybackError(e);
      }
    } else {
      // reached end, could stop or loop
    }
  }

  Future<void> playPrevious() async {
    if (_history.isNotEmpty) {
      if (_currentTrack != null) {
        _queue.insert(0, _currentTrack!);
      }
      final prevTrack = _history.removeLast();
      if (_currentTrack?.id != prevTrack.id) {
        _resetStatsForNewTrack();
      }
      _currentTrack = prevTrack;
      notifyListeners();
      try {
        await _audioService.playTrack(prevTrack, protectedTracks: _protectedTracks);
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
          _queue.clear();
          _fillQueue();
          notifyListeners();
          try {
            await _audioService.playTrack(prevTrack, protectedTracks: _protectedTracks);
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
    _saveCurrentState(); // Save after seeking
  }

  Future<void> setVolume(double volume) async {
    _settings.volume = volume;
    await _storageService.saveSettings(_settings);
    await _audioService.setVolume(volume);
    notifyListeners();
  }

  void _saveCurrentState() {
    final targetPlaylist = _playingPlaylist;

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
    await _audioService.syncMetadataAsync(track);
    notifyListeners();
  }
}
