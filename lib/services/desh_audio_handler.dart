import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:audio_service/audio_service.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:audio_session/audio_session.dart';
import 'package:logging/logging.dart';
import '../models/track.dart';

class DeshAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _log = Logger('DeshAudioHandler');

  SoundHandle? _currentSoundHandle;
  AudioSource? _currentAudioSource;

  // Need to hold onto a subscription to cancel it if skipped
  StreamSubscription<List<int>>? _httpSubscription;
  Completer<void>? _streamCompleter;
  bool _isDisposed = false;

  DeshAudioHandler() {
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            pause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            break;
          case AudioInterruptionType.pause:
            play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    session.becomingNoisyEventStream.listen((_) {
      pause();
    });
  }

  Future<void> playTrack(Track track, {required String downloadUrl, required String localPath, bool startPaused = false}) async {
    _isDisposed = false;
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.loading,
      playing: false,
    ));

    mediaItem.add(MediaItem(
      id: track.id,
      album: 'DeshPlayer',
      title: track.title ?? 'Unknown Track',
      artist: track.artist ?? 'Unknown Artist',
      duration: track.duration.inSeconds > 0 ? track.duration : null,
    ));

    await _stopCurrentPlayback();

    final finalFile = File(localPath);

    try {
      if (finalFile.existsSync()) {
        _log.info('Playing from local cache: ${finalFile.path}');
        _currentAudioSource = await SoLoud.instance.loadFile(finalFile.path);
        if (_currentAudioSource != null && !_isDisposed) {
          _currentSoundHandle = SoLoud.instance.play(
            _currentAudioSource!,
            paused: startPaused,
          );
          _setPlayingState(!startPaused);
        }
      } else {
        _log.info('Streaming and caching to: ${finalFile.path}');
        await _progressiveDiskCacheStream(downloadUrl, finalFile, startPaused);
      }

      if (!_isDisposed) {
        _checkCompletion();
      }

    } catch (e) {
      _log.severe('Error playing track: $e');
      if (e.toString().contains('Playback stopped')) return; // Ignore cancellation
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Timer? _completionTimer;
  void _checkCompletion() {
    _completionTimer?.cancel();
    _completionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_currentSoundHandle != null) {
        if (!SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
           _setPlayingState(false);
           playbackState.add(playbackState.value.copyWith(
             processingState: AudioProcessingState.completed,
           ));
           timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _progressiveDiskCacheStream(String downloadUrl, File finalFile, bool startPaused) async {
    final tempFile = File('${finalFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete(); // clear dirty state
    }

    final request = http.Request('GET', Uri.parse(downloadUrl));
    http.StreamedResponse response;
    try {
      response = await request.send();
      if (response.statusCode != 200) {
        throw Exception('Failed to download track: ${response.statusCode}');
      }
    } catch (e) {
      _log.severe('Failed to send HTTP request for streaming: $e');
      rethrow;
    }

    IOSink sink;
    try {
       sink = tempFile.openWrite();
    } catch (e) {
       _log.severe('Could not open temp file for writing: $e');
       rethrow;
    }

    int bytesDownloaded = 0;
    bool hasStartedPlayback = false;

    // Use a completer to block playTrack until initial buffer is ready or stream completes
    _streamCompleter = Completer<void>();

    _httpSubscription = response.stream.listen((chunk) async {
      sink.add(chunk);
      bytesDownloaded += chunk.length;

      // Once we have ~256 KB, start playback from disk
      if (!hasStartedPlayback && bytesDownloaded >= 256 * 1024) {
        hasStartedPlayback = true;
        await sink.flush();

        try {
          if (!_isDisposed) {
            _currentAudioSource = await SoLoud.instance.loadFile(
              tempFile.path,
              mode: LoadMode.disk,
            );

            if (_currentAudioSource != null && !_isDisposed) {
              _currentSoundHandle = SoLoud.instance.play(
                _currentAudioSource!,
                paused: startPaused,
              );
              _setPlayingState(!startPaused);
            }
          }
          if (_streamCompleter != null && !_streamCompleter!.isCompleted) _streamCompleter!.complete();
        } catch (e) {
           _log.warning('SoLoud loadFile error: $e');
           if (_streamCompleter != null && !_streamCompleter!.isCompleted) _streamCompleter!.completeError(e);
        }
      }
    }, onDone: () async {
      _log.info('Download stream finished');
      try {
        await sink.flush();
        await sink.close();
        if (await tempFile.exists()) {
          // If we never started playback because file was < 256KB, do it now
          if (!hasStartedPlayback && !_isDisposed) {
             _currentAudioSource = await SoLoud.instance.loadFile(tempFile.path);
             if (_currentAudioSource != null) {
               _currentSoundHandle = SoLoud.instance.play(
                 _currentAudioSource!,
                 paused: startPaused,
               );
               _setPlayingState(!startPaused);
             }
          }
          await tempFile.rename(finalFile.path);
          _log.info('Track successfully cached to: ${finalFile.path}');
        }
        if (_streamCompleter != null && !_streamCompleter!.isCompleted) _streamCompleter!.complete();
      } catch (e) {
        _log.warning('Stream finalizing error: $e');
        if (_streamCompleter != null && !_streamCompleter!.isCompleted) _streamCompleter!.completeError(e);
      }
    }, onError: (e) async {
      _log.warning('Stream interrupted: $e');
      try { await sink.close(); } catch (_) {}
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (_streamCompleter != null && !_streamCompleter!.isCompleted) _streamCompleter!.completeError(e);
    });

    // Wait for the stream to either reach 256kb or finish (or error)
    await _streamCompleter!.future;
  }

  Future<void> _stopCurrentPlayback() async {
    _isDisposed = true;
    _completionTimer?.cancel();
    _httpSubscription?.cancel();
    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
        _streamCompleter!.completeError(Exception("Playback stopped"));
    }
    if (_currentSoundHandle != null) {
      SoLoud.instance.stop(_currentSoundHandle!);
      _currentSoundHandle = null;
    }
    if (_currentAudioSource != null) {
      try {
         await SoLoud.instance.disposeSource(_currentAudioSource!);
      } catch (_) {}
      _currentAudioSource = null;
    }
  }

  @override
  Future<void> play() async {
    if (_currentSoundHandle != null) {
      SoLoud.instance.setPause(_currentSoundHandle!, false);
      _setPlayingState(true);
    }
  }

  @override
  Future<void> pause() async {
    if (_currentSoundHandle != null) {
      SoLoud.instance.setPause(_currentSoundHandle!, true);
      _setPlayingState(false);
    }
  }

  @override
  Future<void> stop() async {
    await _stopCurrentPlayback();
    _setPlayingState(false);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
    ));
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_currentSoundHandle != null) {
      SoLoud.instance.seek(_currentSoundHandle!, position);
      playbackState.add(playbackState.value.copyWith(
        updatePosition: position,
      ));
    }
  }

  void setVolume(double volume) {
    if (_currentSoundHandle != null) {
      SoLoud.instance.setVolume(_currentSoundHandle!, volume);
    }
  }

  void _setPlayingState(bool isPlaying) {
    // We provide current position along with the playing state when it changes
    Duration currentPosition = Duration.zero;
    if (_currentSoundHandle != null && SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
      currentPosition = SoLoud.instance.getPosition(_currentSoundHandle!);
    }

    playbackState.add(playbackState.value.copyWith(
      playing: isPlaying,
      updatePosition: currentPosition,
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
    ));
  }
}
