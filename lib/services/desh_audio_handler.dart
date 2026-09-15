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
  final Future<void> Function()? onSkipToPrevious;
  final Future<void> Function()? onSkipToNext;

  SoundHandle? _currentSoundHandle;
  AudioSource? _currentAudioSource;
  PullBufferDiskStream? _pullBufferStream;
  bool _isDisposed = false;
  bool _isCurrentFileDownloaded = false;
  bool _resumeAfterInterruption = false;

  Duration? _lastCompletionPosition;
  int _unchangedCompletionTicks = 0;
  String? _currentTrackId;
  bool _reportedCurrentStall = false;

  static const _completionPollInterval = Duration(milliseconds: 500);
  static const _completionStallTime = Duration(seconds: 3);
  static const _completionPositionTolerance = Duration(milliseconds: 20);
  static const _completionOverrunGrace = Duration(seconds: 1);
  static const _minimumCompletionEndTolerance = Duration(seconds: 2);
  static const _maximumCompletionEndTolerance = Duration(seconds: 10);

  DeshAudioHandler({this.onSkipToPrevious, this.onSkipToNext}) {
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
            _resumeAfterInterruption = playbackState.value.playing;
            pause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            break;
          case AudioInterruptionType.pause:
            if (_resumeAfterInterruption) play();
            _resumeAfterInterruption = false;
            break;
          case AudioInterruptionType.unknown:
            _resumeAfterInterruption = false;
            break;
        }
      }
    });

    session.becomingNoisyEventStream.listen((_) {
      // A route change such as wireless headphones disconnecting must never
      // resume onto the device speaker when the interruption subsequently ends.
      _resumeAfterInterruption = false;
      pause();
    });
  }

  Future<void> playTrack(
    Track track, {
    required String? downloadUrl,
    required Future<String> Function() getDownloadUrl,
    required String localPath,
    bool startPaused = false,
    void Function()? onMetadataChanged,
    void Function()? onCacheCompleted,
  }) async {
    await _stopCurrentPlayback();

    _isDisposed = false;
    _currentTrackId = track.id;
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
        final fileLength = await finalFile.length();
        if (fileLength == 0) {
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
              _isCurrentFileDownloaded = true;
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
        final resolvedDownloadUrl = downloadUrl ?? await getDownloadUrl();
        _log.info('Streaming and caching to: ${finalFile.path}');
        await _playPullBufferStream(
          resolvedDownloadUrl,
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
    _lastCompletionPosition = null;
    _unchangedCompletionTicks = 0;
    _reportedCurrentStall = false;
    _completionTimer = Timer.periodic(_completionPollInterval, (timer) {
      try {
        if (_currentSoundHandle != null) {
          if (!SoLoud.instance.getIsValidVoiceHandle(_currentSoundHandle!)) {
            _markPlaybackCompleted(timer);
            return;
          }

          _checkForMissedCompletion(timer);
        } else {
          _log.warning(
            'Completion monitor stopped without a voice handle: '
            'track=$_currentTrackId',
          );
          timer.cancel();
        }
      } catch (error, stackTrace) {
        _log.severe(
          'Completion monitor failed: track=$_currentTrackId',
          error,
          stackTrace,
        );
        timer.cancel();
      }
    });
  }

  void _checkForMissedCompletion(Timer timer) {
    // On some Android devices SoLoud occasionally keeps the voice handle valid
    // after playback has reached EOF. Only compensate when playback is active,
    // the complete file is cached, and the voice is stalled very near its end.
    final state = playbackState.value;
    final canMonitorState =
        state.processingState == AudioProcessingState.ready ||
        state.processingState == AudioProcessingState.buffering;
    if (!_isCurrentFileDownloaded || !state.playing || !canMonitorState) {
      _lastCompletionPosition = null;
      _unchangedCompletionTicks = 0;
      _reportedCurrentStall = false;
      return;
    }

    final handle = _currentSoundHandle!;
    final position = SoLoud.instance.getPosition(handle);
    final previousPosition = _lastCompletionPosition;
    _lastCompletionPosition = position;

    final source = _currentAudioSource;
    var duration = source == null
        ? Duration.zero
        : SoLoud.instance.getLength(source);
    if (duration <= Duration.zero) {
      duration = mediaItem.value?.duration ?? Duration.zero;
    }

    // Affected Android devices may keep both the voice handle and SoLoud's
    // playback clock alive after decoded audio has ended. In that case the UI
    // is clamped at the end, but a stall-based watchdog never fires because
    // getPosition() continues to increase.
    if (duration > Duration.zero &&
        position >= duration + _completionOverrunGrace) {
      _log.warning(
        'SoLoud position passed decoded EOF; forcing completion: '
        'track=$_currentTrackId, position=$position, duration=$duration, '
        'overrun=${position - duration}, state=${state.processingState}, '
        'handle=$handle',
      );
      _markPlaybackCompleted(timer);
      return;
    }

    if (previousPosition == null ||
        (position - previousPosition).abs() > _completionPositionTolerance) {
      _unchangedCompletionTicks = 0;
      _reportedCurrentStall = false;
      return;
    }

    final remaining = duration - position;
    final proportionalTolerance = Duration(
      milliseconds: duration.inMilliseconds ~/ 100,
    );
    final endTolerance = proportionalTolerance < _minimumCompletionEndTolerance
        ? _minimumCompletionEndTolerance
        : proportionalTolerance > _maximumCompletionEndTolerance
        ? _maximumCompletionEndTolerance
        : proportionalTolerance;
    final isNearEnd =
        duration > Duration.zero &&
        remaining <= endTolerance &&
        remaining >= -endTolerance;

    _unchangedCompletionTicks++;
    if (!_reportedCurrentStall &&
        _unchangedCompletionTicks * _completionPollInterval.inMilliseconds >=
            const Duration(seconds: 1).inMilliseconds) {
      _reportedCurrentStall = true;
      _log.warning(
        'Playback position stopped changing: track=$_currentTrackId, '
        'position=$position, duration=$duration, remaining=$remaining, '
        'endTolerance=$endTolerance, nearEnd=$isNearEnd, '
        'downloaded=$_isCurrentFileDownloaded, '
        'state=${state.processingState}, playing=${state.playing}, '
        'handle=$handle',
      );
    }
    if (!isNearEnd) {
      return;
    }

    final requiredTicks =
        _completionStallTime.inMilliseconds ~/
        _completionPollInterval.inMilliseconds;
    if (_unchangedCompletionTicks >= requiredTicks) {
      _log.warning(
        'Playback stalled near EOF; forcing completion: '
        'track=$_currentTrackId, position=$position, duration=$duration, '
        'remaining=$remaining, state=${state.processingState}, handle=$handle',
      );
      _markPlaybackCompleted(timer);
    }
  }

  void _markPlaybackCompleted(Timer timer) {
    _setPlayingState(false);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.completed,
      ),
    );
    timer.cancel();
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
          _isCurrentFileDownloaded = true;
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
    _isCurrentFileDownloaded = false;
    _lastCompletionPosition = null;
    _unchangedCompletionTicks = 0;
    _reportedCurrentStall = false;

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
    _currentTrackId = null;
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
  Future<void> skipToPrevious() async {
    await onSkipToPrevious?.call();
  }

  @override
  Future<void> skipToNext() async {
    await onSkipToNext?.call();
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
