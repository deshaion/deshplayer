import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/playback_state.dart' as pstate;
import '../models/settings.dart';
import 'hive_storage_service.dart';
import 'audio_player_service.dart';

class PlayerProvider extends ChangeNotifier {
  final HiveStorageService _storageService;
  late AudioPlayerService _audioService;

  Playlist? _currentPlaylist;
  Track? _currentTrack;
  AppSettings _settings = AppSettings();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  DateTime _lastSaveTime = DateTime.now();

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

  AudioPlayer get audioPlayer => _audioService.player; // expose for streams

  Track? getTrack(String id) => _storageService.getTrack(id);

  Future<void> _init() async {
    _settings = _storageService.getSettings();
    _audioService.setVolume(_settings.volume);

    // Restore state
    if (_settings.lastActivePlaylistId != null) {
      _currentPlaylist = _storageService.getPlaylist(_settings.lastActivePlaylistId!);
      if (_currentPlaylist != null) {
        final state = _storageService.getPlaybackState(_currentPlaylist!.id);
        if (state != null && state.currentTrackId != null) {
          _currentTrack = _storageService.getTrack(state.currentTrackId!);
          _position = state.position;

          if (_currentTrack != null) {
            try {
               if (_currentTrack!.localCachePath != null && await _audioService.player.setFilePath(_currentTrack!.localCachePath!) != null) {
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

    _audioService.player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();

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
        notifyListeners();
      }
    });

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

    notifyListeners();

    if (_currentTrack != null) {
      await _audioService.playTrack(_currentTrack!);
      final state = _storageService.getPlaybackState(playlist.id);
      if (state != null) {
        await _audioService.seek(state.position);
      }
    }
  }

  Future<void> playTrackDirectly(Track track) async {
    _currentTrack = track;
    notifyListeners();
    await _audioService.playTrack(track);
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
    if (_currentPlaylist == null || _currentTrack == null) return;
    final ids = _currentPlaylist!.trackIds;
    final index = ids.indexOf(_currentTrack!.id);
    if (index >= 0 && index < ids.length - 1) {
      final nextTrack = _storageService.getTrack(ids[index + 1]);
      if (nextTrack != null) {
        _currentTrack = nextTrack;
        notifyListeners();
        await _audioService.playTrack(nextTrack);
      }
    } else {
      // reached end, could stop or loop
    }
  }

  Future<void> playPrevious() async {
    if (_currentPlaylist == null || _currentTrack == null) return;
    // If we are more than 3 seconds in, just restart track
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final ids = _currentPlaylist!.trackIds;
    final index = ids.indexOf(_currentTrack!.id);
    if (index > 0) {
      final prevTrack = _storageService.getTrack(ids[index - 1]);
      if (prevTrack != null) {
        _currentTrack = prevTrack;
        notifyListeners();
        await _audioService.playTrack(prevTrack);
      }
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
    await _audioService.setShuffleModeEnabled(_settings.shuffle);
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    _settings.repeatMode = (_settings.repeatMode + 1) % 3;
    await _storageService.saveSettings(_settings);

    LoopMode mode = LoopMode.off;
    if (_settings.repeatMode == 1) mode = LoopMode.all;
    if (_settings.repeatMode == 2) mode = LoopMode.one;

    await _audioService.setLoopMode(mode);
    notifyListeners();
  }
}
