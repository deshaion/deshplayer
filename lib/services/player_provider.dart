import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/playback_state.dart' as pstate;
import '../models/settings.dart';
import 'dart:async';
import 'hive_storage_service.dart';
import 'audio_player_service.dart';
import 'package:logging/logging.dart';

class PlayerProvider extends ChangeNotifier {
  final _log = Logger('PlayerProvider');
  final HiveStorageService _storageService;
  late AudioPlayerService _audioService;

  Playlist? _currentPlaylist;
  Track? _currentTrack;
  AppSettings _settings = AppSettings();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Queue
  final List<Track> _queue = [];
  final List<Track> _history = [];

  DateTime _lastSaveTime = DateTime.now();

  // Error handling
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 20;

  PlayerProvider(this._storageService) {
    _audioService = AudioPlayerService(_storageService);
    _init();
  }

  Playlist? get currentPlaylist => _currentPlaylist;
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
      _currentPlaylist = _storageService.getPlaylist(
        _settings.lastActivePlaylistId!,
      );
      if (_currentPlaylist != null) {
        final state = _storageService.getPlaybackState(_currentPlaylist!.id);
        if (state != null && state.currentTrackId != null) {
          _currentTrack = _storageService.getTrack(state.currentTrackId!);
          _position = state.position;

          _fillQueue();

          if (_currentTrack != null) {
            try {
              if (_currentTrack!.localCachePath != null &&
                  await _audioService.player.setFilePath(
                        _currentTrack!.localCachePath!,
                      ) !=
                      null) {
                await _audioService.seek(_position);
              } else {
                await _audioService.player.setUrl(_currentTrack!.cloudPath);
                await _audioService.seek(_position);
              }
            } catch (e) {
              // ignore
            }
          }
        }
      }
    }

    _audioService.player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace stackTrace) {
        // If it throws an error but we are at the very end of the file, treat it as EOF.
        // This commonly happens with FLAC trailing garbage where ffmpeg expects another frame.
        if (_duration.inMilliseconds > 0 &&
            _position.inMilliseconds >= _duration.inMilliseconds - 1500) {
          _log.info('Caught terminal decoding error near EOF. Treating as successful completion. Error: $e');
          _consecutiveFailures = 0; // Reset failures

          // Add a small delay to give media_kit/just_audio time to dispose the bad native instance gracefully
          Future.delayed(const Duration(milliseconds: 500), () {
            playNext();
          });
        } else {
          _handlePlaybackError(e);
        }
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

    _audioService.player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();

      // Throttle database writes to every 5 seconds
      if (DateTime.now().difference(_lastSaveTime).inSeconds >= 5) {
        _saveCurrentState();
        _lastSaveTime = DateTime.now();
      }
    });

    _audioService.player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        _log.info('Duration listen: $dur');
        notifyListeners();
      }
    });

    notifyListeners();
  }

  void _fillQueue() {
    if (_currentPlaylist == null) return;

    // We want to maintain a queue of upcoming tracks.
    // Let's keep at least 5 tracks in the queue.
    int targetQueueSize = 5;

    if (_queue.length < targetQueueSize) {
      final ids = _currentPlaylist!.trackIds;
      if (ids.isEmpty) return;

      if (_settings.shuffle) {
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
            if (_settings.repeatMode == 1) {
              // repeat all
              startIdx = 0;
            } else {
              break; // Reached end of playlist without repeat
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
      _audioService.preCacheTrack(_queue[i]);
    }

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

  Future<void> playPlaylist(Playlist playlist, {Track? startTrack}) async {
    _currentPlaylist = playlist;
    _settings.lastActivePlaylistId = playlist.id;
    _storageService.saveSettings(_settings);

    if (startTrack != null) {
      _currentTrack = startTrack;
    } else {
      if (playlist.trackIds.isNotEmpty) {
        final state = _storageService.getPlaybackState(playlist.id);
        if (state != null && state.currentTrackId != null) {
          _currentTrack = _storageService.getTrack(state.currentTrackId!);
        } else {
          _currentTrack = _storageService.getTrack(playlist.trackIds.first);
        }
      } else {
        _currentTrack = null;
      }
    }

    _queue.clear();
    _fillQueue();
    notifyListeners();

    if (_currentTrack != null) {
      try {
        await _audioService.playTrack(_currentTrack!);
        final state = _storageService.getPlaybackState(playlist.id);
        if (state != null) {
          await _audioService.seek(state.position);
        }
      } catch (e) {
        _handlePlaybackError(e);
      }
    }
  }

  Future<void> playTrackDirectly(Track track) async {
    if (_currentTrack != null) {
      _history.add(_currentTrack!);
    }
    _currentTrack = track;
    _queue.clear();
    _fillQueue();
    notifyListeners();
    try {
      await _audioService.playTrack(track);
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
        await _audioService.playTrack(_currentTrack!);
        return;
      }
      _history.add(_currentTrack!);
    }

    if (_queue.isNotEmpty) {
      final nextTrack = _queue.removeAt(0);
      _currentTrack = nextTrack;
      _fillQueue();
      notifyListeners();
      try {
        await _audioService.playTrack(nextTrack);
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
      _currentTrack = prevTrack;
      notifyListeners();
      try {
        await _audioService.playTrack(prevTrack);
      } catch (e) {
        _handlePlaybackError(e);
      }
    } else {
      // Fallback to legacy behaviour if history is empty (e.g. initial launch)
      if (_currentPlaylist == null || _currentTrack == null) return;
      final ids = _currentPlaylist!.trackIds;
      final index = ids.indexOf(_currentTrack!.id);
      if (index > 0) {
        final prevTrack = _storageService.getTrack(ids[index - 1]);
        if (prevTrack != null) {
          _currentTrack = prevTrack;
          _queue.clear();
          _fillQueue();
          notifyListeners();
          try {
            await _audioService.playTrack(prevTrack);
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
    final errorMessage = 'Failed to play "$trackName". Error: $e';
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
    if (_currentPlaylist != null && _currentTrack != null) {
      final state = pstate.PlaybackState(
        playlistId: _currentPlaylist!.id,
        currentTrackId: _currentTrack!.id,
        position: _position,
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
}
