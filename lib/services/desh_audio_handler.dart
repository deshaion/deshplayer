import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:audio_service/audio_service.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:audio_session/audio_session.dart';
import 'package:logging/logging.dart';
import '../models/track.dart';

class DeshAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static const _streamBufferSizeBytes = 100 * 1024 * 1024;
  static const _streamBufferHighWaterBytes = _streamBufferSizeBytes ~/ 2;
  static const _streamBufferPollDelay = Duration(milliseconds: 100);

  final _log = Logger('DeshAudioHandler');

  SoundHandle? _currentSoundHandle;
  AudioSource? _currentAudioSource;
  bool _usesReleasedStreamBuffer = false;

  StreamSubscription<List<int>>? _httpSubscription;
  IOSink? _activeSink;
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
            );
            _usesReleasedStreamBuffer = false;
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
        await _progressiveDiskCacheStream(
          downloadUrl,
          finalFile,
          startPaused,
        );
      }

      if (!_isDisposed) {
        _checkCompletion();
      }
    } catch (e) {
      _log.severe('Error playing track: $e');
      if (e.toString().contains('Playback stopped')) return;
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

  Future<void> _progressiveDiskCacheStream(
    String downloadUrl,
    File finalFile,
    bool startPaused,
  ) async {
    final tempFile = File('${finalFile.path}.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
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

    late final IOSink sink;
    try {
      sink = tempFile.openWrite(mode: FileMode.write);
      _activeSink = sink;
    } catch (e) {
      _log.severe('Could not open temp file for writing: $e');
      rethrow;
    }

    late final AudioSource source;
    _log.fine('Allocating a released streaming buffer');
    source = SoLoud.instance.setBufferStream(
      format: BufferType.auto,
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 2,
      maxBufferSizeBytes: _streamBufferSizeBytes,
      onBuffering: (isBuffering, handle, time) {
        if (_isDisposed || _currentAudioSource != source) return;
        playbackState.add(
          playbackState.value.copyWith(
            processingState: isBuffering
                ? AudioProcessingState.buffering
                : AudioProcessingState.ready,
          ),
        );
      },
    );

    if (_isDisposed) {
      await SoLoud.instance.disposeSource(source);
      return;
    }

    _currentAudioSource = source;
    _usesReleasedStreamBuffer = true;
    _currentSoundHandle = SoLoud.instance.play(source, paused: startPaused);
    _setPlayingState(!startPaused);

    var audioDataRejected = false;
    late final StreamSubscription<List<int>> subscription;
    subscription = response.stream.listen(
      (chunk) async {
        if (_isDisposed || _currentAudioSource != source) return;
        sink.add(chunk);
        if (audioDataRejected) return;

        // Keep chunks in order while SoLoud applies backpressure. In
        // particular, do not allow onDone to mark the stream as ended while
        // this chunk is still waiting to be accepted.
        subscription.pause();
        try {
          final audioData = Uint8List.fromList(chunk);
          while (!_isDisposed && _currentAudioSource == source) {
            if (SoLoud.instance.getBufferSize(source) <
                _streamBufferHighWaterBytes) {
              SoLoud.instance.addAudioDataStream(source, audioData);
              break;
            }
            await Future<void>.delayed(_streamBufferPollDelay);
          }
        } catch (e) {
          audioDataRejected = true;
          _log.severe('Could not add audio data to the SoLoud stream: $e');
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorMessage: e.toString(),
            ),
          );
        } finally {
          subscription.resume();
        }
      },
      onDone: () async {
        _log.info('Download stream finished');
        try {
          await sink.flush();
          await sink.close();
          if (_activeSink == sink) _activeSink = null;

          if (!audioDataRejected &&
              !_isDisposed &&
              _currentAudioSource == source) {
            SoLoud.instance.setDataIsEnded(source);
          }
          if (!_isDisposed &&
              _currentAudioSource == source &&
              await tempFile.exists()) {
            await tempFile.rename(finalFile.path);
            _log.info('Track successfully cached to: ${finalFile.path}');
          }
        } catch (e) {
          _log.warning('Stream finalizing error: $e');
        }
      },
      onError: (e) async {
        _log.warning('Stream interrupted: $e');
        try {
          await sink.close();
          if (_activeSink == sink) _activeSink = null;
        } catch (_) {}

        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (!_isDisposed && _currentAudioSource == source) {
          playbackState.add(
            playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorMessage: e.toString(),
            ),
          );
        }
      },
      cancelOnError: true,
    );
    _httpSubscription = subscription;
  }

  Future<void> _stopCurrentPlayback() async {
    _isDisposed = true;
    _completionTimer?.cancel();

    await _httpSubscription?.cancel();
    _httpSubscription = null;

    try {
      await _activeSink?.close();
    } catch (_) {}
    _activeSink = null;

    if (_currentSoundHandle != null) {
      SoLoud.instance.stop(_currentSoundHandle!);
      _currentSoundHandle = null;
    }

    if (_currentAudioSource != null) {
      try {
        await SoLoud.instance.disposeSource(_currentAudioSource!);
      } catch (_) {}
      _currentAudioSource = null;
      _usesReleasedStreamBuffer = false;
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
      if (_usesReleasedStreamBuffer) {
        _log.fine('Seeking is unavailable until the track is fully cached');
        return;
      }
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
      currentPosition = _usesReleasedStreamBuffer && _currentAudioSource != null
          ? SoLoud.instance.getStreamTimeConsumed(_currentAudioSource!)
          : SoLoud.instance.getPosition(_currentSoundHandle!);
    }

    playbackState.add(
      playbackState.value.copyWith(
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
