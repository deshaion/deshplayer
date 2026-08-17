import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:audio_session/audio_session.dart';
import 'package:logging/logging.dart';
import '../models/track.dart';
import 'pull_buffer_disk_stream.dart';

class DeshAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _log = Logger('DeshAudioHandler');

  SoundHandle? _currentSoundHandle;
  AudioSource? _currentAudioSource;
  PullBufferDiskStream? _pullBufferStream;
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

  Future<void> playTrack(
    Track track, {
    required String downloadUrl,
    required String localPath,
    bool startPaused = false,
    void Function()? onMetadataChanged,
    void Function()? onCacheCompleted,
  }) async {
    await _stopCurrentPlayback();

    _isDisposed = false;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: false,
      ),
    );

    mediaItem.add(
      MediaItem(
        id: track.id,
        album: 'DeshPlayer',
        title: track.title ?? 'Unknown Track',
        artist: track.artist ?? 'Unknown Artist',
        duration: track.duration.inSeconds > 0 ? track.duration : null,
      ),
    );

    final finalFile = File(localPath);

    try {
      bool loadedFromCache = false;

      // 1. Try playing from local cache if valid
      if (await finalFile.exists()) {
        if (await finalFile.length() == 0) {
          _log.warning(
            'Cache file is empty (0 bytes). Deleting: ${finalFile.path}',
          );
          await finalFile.delete();
        } else {
          try {
            _currentAudioSource = await SoLoud.instance.loadFile(
              finalFile.path,
              mode: LoadMode.disk,
            );
            _log.info('Playing from local cache: ${finalFile.path}');
            if (_currentAudioSource != null && !_isDisposed) {
              _currentSoundHandle = SoLoud.instance.play(
                _currentAudioSource!,
                paused: startPaused,
              );
              _setPlayingState(!startPaused);
              loadedFromCache = true;
            }
          } catch (e) {
            _log.severe(
              'Cache file appears corrupted ($e). Deleting and re-downloading...',
            );
            if (await finalFile.exists()) {
              await finalFile.delete();
            }
          }
        }
      }

      // 2. Stream and cache if not loaded from cache
      if (!loadedFromCache && !_isDisposed) {
        _log.info('Streaming and caching to: ${finalFile.path}');
        await _playPullBufferStream(
          downloadUrl,
          finalFile,
          startPaused,
          track,
          onMetadataChanged,
          onCacheCompleted,
        );
      }

      if (!_isDisposed) {
        _checkCompletion();
      }
    } catch (e) {
      _log.severe('Error playing track: $e');
      if (_isDisposed || e.toString().contains('Playback stopped')) return;
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Timer? _completionTimer;
  void _checkCompletion() {
    _completionTimer?.cancel();
    _completionTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (_currentSoundHandle != null) {
        if (!SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
          _setPlayingState(false);
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.completed,
            ),
          );
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _playPullBufferStream(
    String downloadUrl,
    File finalFile,
    bool startPaused,
    Track track,
    void Function()? onMetadataChanged,
    void Function()? onCacheCompleted,
  ) async {
    final streamer = PullBufferDiskStream();
    _pullBufferStream = streamer;

    late final AudioSource source;
    try {
      source = await streamer.start(
        url: downloadUrl,
        finalFile: finalFile,
        onDuration: (duration) {
          if (_isDisposed || _pullBufferStream != streamer) return;
          track.duration = duration;
          final item = mediaItem.value;
          if (item != null) mediaItem.add(item.copyWith(duration: duration));
        },
        onTags: (tags) {
          if (_isDisposed || _pullBufferStream != streamer) return;
          if (tags.title != null) track.title = tags.title;
          if (tags.artist != null) track.artist = tags.artist;
          if (tags.duration != null) track.duration = tags.duration!;

          final item = mediaItem.value;
          if (item != null) {
            mediaItem.add(
              item.copyWith(
                title: tags.title ?? item.title,
                artist: tags.artist ?? item.artist,
                duration: tags.duration ?? item.duration,
              ),
            );
          }
          onMetadataChanged?.call();
        },
        onCacheCompleted: () {
          if (_isDisposed || _pullBufferStream != streamer) return;
          onCacheCompleted?.call();
        },
        onBuffering: (isBuffering, handle, time) {
          if (_isDisposed || _pullBufferStream != streamer) return;
          playbackState.add(
            playbackState.value.copyWith(
              processingState: isBuffering
                  ? AudioProcessingState.buffering
                  : AudioProcessingState.ready,
            ),
          );
        },
        onError: (error, stackTrace) {
          if (_isDisposed || _pullBufferStream != streamer) return;
          _log.severe('Pull-buffer stream failed', error, stackTrace);
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorMessage: error.toString(),
            ),
          );
        },
      );
    } catch (_) {
      try {
        await streamer.dispose();
      } catch (_) {}
      if (_pullBufferStream == streamer) _pullBufferStream = null;
      rethrow;
    }

    if (_isDisposed || _pullBufferStream != streamer) {
      await SoLoud.instance.disposeSource(source);
      return;
    }
    _currentAudioSource = source;
    _currentSoundHandle = SoLoud.instance.play(source, paused: startPaused);
    _setPlayingState(!startPaused);
  }

  Future<void> _stopCurrentPlayback() async {
    _isDisposed = true;
    _completionTimer?.cancel();

    await _pullBufferStream?.dispose();
    _pullBufferStream = null;

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
    if (_currentSoundHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
      SoLoud.instance.setPause(_currentSoundHandle!, false);
      _setPlayingState(true);
    }
  }

  @override
  Future<void> pause() async {
    if (_currentSoundHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
      SoLoud.instance.setPause(_currentSoundHandle!, true);
      _setPlayingState(false);
    }
  }

  @override
  Future<void> stop() async {
    await _stopCurrentPlayback();
    _setPlayingState(false);
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.idle),
    );
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_currentSoundHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
      SoLoud.instance.seek(_currentSoundHandle!, position);
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    }
  }

  void setVolume(double volume) {
    if (_currentSoundHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
      SoLoud.instance.setVolume(_currentSoundHandle!, volume);
    }
  }

  void _setPlayingState(bool isPlaying) {
    Duration currentPosition = Duration.zero;
    if (_currentSoundHandle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
      currentPosition = SoLoud.instance.getPosition(_currentSoundHandle!);
    }

    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
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
      ),
    );
  }
}
