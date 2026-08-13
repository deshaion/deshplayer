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
  final _log = Logger('DeshAudioHandler');

  SoundHandle? _currentSoundHandle;
  AudioSource? _currentAudioSource;

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

  Future<void> playTrack(Track track, {required String downloadUrl, required String localPath}) async {
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
        if (_currentAudioSource != null) {
          _currentSoundHandle = SoLoud.instance.play(_currentAudioSource!);
          _setPlayingState(true);
        }
      } else {
        _log.info('Streaming and caching to: ${finalFile.path}');

        final tempFile = File('${finalFile.path}.tmp');

        _currentAudioSource = SoLoud.instance.setBufferStream(
          maxBufferSizeBytes: 1024 * 1024 * 20,
          bufferingTimeNeeds: 1.5,
          bufferingType: BufferingType.preserved,
          onBuffering: (isBuffering, handle, time) {
            _log.info('Buffering status: $isBuffering');
            playbackState.add(playbackState.value.copyWith(
              processingState: isBuffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
            ));
          },
        );

        if (_currentAudioSource != null) {
          _currentSoundHandle = SoLoud.instance.play(_currentAudioSource!);
          _setPlayingState(true);

          _streamAndCache(
            downloadUrl: downloadUrl,
            sound: _currentAudioSource!,
            tempFile: tempFile,
            finalFile: finalFile,
          );
        }
      }

      _checkCompletion();

    } catch (e) {
      _log.severe('Error playing track: $e');
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

  Future<void> _streamAndCache({
    required String downloadUrl,
    required AudioSource sound,
    required File tempFile,
    required File finalFile,
  }) async {
    final request = http.Request('GET', Uri.parse(downloadUrl));
    http.StreamedResponse response;
    try {
      response = await request.send();
      if (response.statusCode != 200) {
        throw Exception('Failed to download track: ${response.statusCode}');
      }
    } catch (e) {
      _log.severe('Failed to send HTTP request for streaming: $e');
      return;
    }

    IOSink sink;
    try {
       sink = tempFile.openWrite();
    } catch (e) {
       _log.severe('Could not open temp file for writing: $e');
       return;
    }

    try {
      await for (final chunk in response.stream) {
        final bytes = Uint8List.fromList(chunk);
        sink.add(bytes);

        try {
          SoLoud.instance.addAudioDataStream(sound, bytes);
        } catch (e) {
           _log.warning('SoLoud stream error (may be stopped): $e');
           throw Exception('Stream aborted by SoLoud'); // Throw to cleanup .tmp
        }
      }

      await sink.flush();
      await sink.close();

      if (await tempFile.exists()) {
        await tempFile.rename(finalFile.path);
        _log.info('Track successfully cached to: ${finalFile.path}');
      }
    } catch (e) {
      _log.warning('Stream interrupted, cleaning up temp file: $e');
      await sink.close();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<void> _stopCurrentPlayback() async {
    _completionTimer?.cancel();
    if (_currentSoundHandle != null) {
      SoLoud.instance.stop(_currentSoundHandle!);
      _currentSoundHandle = null;
    }
    if (_currentAudioSource != null) {
      await SoLoud.instance.disposeSource(_currentAudioSource!);
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
