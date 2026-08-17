// flutter_soloud 4.1.7 marks its pull-buffer API experimental even though it
// is the only bounded-memory API with native demand-driven backpressure.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

class PullBufferDiskStream {
  static const _decodedBufferSizeBytes = 16 * 1024 * 1024;
  static const _encodedChunkSizeBytes = 64 * 1024;
  static const _durationProbeBytes = 128 * 1024;

  final _log = Logger('PullBufferDiskStream');
  final _client = http.Client();

  StreamIterator<List<int>>? _downloadIterator;
  RandomAccessFile? _writer;
  Future<void>? _downloadTask;
  Future<void> _feedChain = Future<void>.value();
  Completer<void> _dataChanged = Completer<void>();

  late Uri _remoteUri;
  late File _tempFile;
  late File _finalFile;
  File? _readFile;
  AudioSource? _source;

  int _downloadedBytes = 0;
  int _totalBytes = 0;
  int _activeReaders = 0;
  bool _downloadFinished = false;
  bool _durationProbed = false;
  bool _renamingCache = false;
  bool _disposed = false;
  Object? _downloadError;

  void Function(Duration duration)? _onDuration;
  void Function(bool isBuffering, int handle, double time)? _onBuffering;
  void Function(Object error, StackTrace stackTrace)? _onError;

  Future<AudioSource> start({
    required String url,
    required File finalFile,
    void Function(Duration duration)? onDuration,
    void Function(bool isBuffering, int handle, double time)? onBuffering,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    _remoteUri = Uri.parse(url);
    _finalFile = finalFile;
    _tempFile = File('${finalFile.path}.tmp');
    _readFile = _tempFile;
    _onDuration = onDuration;
    _onBuffering = onBuffering;
    _onError = onError;

    if (await _tempFile.exists()) await _tempFile.delete();
    await _tempFile.parent.create(recursive: true);

    final response = await _client.send(http.Request('GET', _remoteUri));
    if (response.statusCode != HttpStatus.ok) {
      _client.close();
      throw HttpException(
        'Audio download failed with HTTP ${response.statusCode}',
        uri: _remoteUri,
      );
    }

    _totalBytes = response.contentLength ?? 0;
    if (_totalBytes <= 0) {
      _client.close();
      throw const FormatException(
        'Pull-buffer playback requires a positive Content-Length',
      );
    }

    _writer = await _tempFile.open(mode: FileMode.write);
    _downloadIterator = StreamIterator<List<int>>(response.stream);

    AudioSource? source;
    source = SoLoud.instance.setPullBufferStream(
      bufferSizeBytes: _decodedBufferSizeBytes,
      bufferTriggerPosition: 0.7,
      format: BufferType.auto,
      audioSizeBytes: _totalBytes,
      onBuffering: (isBuffering, handle, time) {
        if (_disposed || source != _source) return;
        _onBuffering?.call(isBuffering, handle, time);
      },
      onAudioDuration: (seconds) {
        if (_disposed || source != _source || seconds <= 0) return;
        _reportDuration(Duration(milliseconds: (seconds * 1000).round()));
      },
      onMoreDataIsNeeded: (offset) {
        if (_disposed || source == null || source != _source) return;
        _queueFeed(source, offset);
      },
    );
    _source = source;

    _downloadTask = _download();
    return source;
  }

  Future<void> _download() async {
    final iterator = _downloadIterator!;
    final writer = _writer!;
    try {
      while (!_disposed && await iterator.moveNext()) {
        final chunk = iterator.current;
        await writer.writeFrom(chunk);
        _downloadedBytes += chunk.length;
        _signalDataChanged();

        if (!_durationProbed && _downloadedBytes >= _durationProbeBytes) {
          _durationProbed = true;
          await writer.flush();
          await _probeDurationFromPartialFile();
        }
      }

      if (_disposed) return;
      await writer.flush();
      await writer.close();
      _writer = null;
      _downloadFinished = true;
      _signalDataChanged();

      if (!_durationProbed) {
        _durationProbed = true;
        await _probeDurationFromPartialFile();
      }

      _renamingCache = true;
      await _waitForReaders();
      if (await _finalFile.exists()) await _finalFile.delete();
      await _tempFile.rename(_finalFile.path);
      _readFile = _finalFile;
      _renamingCache = false;
      _signalDataChanged();
      _log.info('Track cached at ${_finalFile.path}');
    } catch (error, stackTrace) {
      if (_disposed) return;
      _downloadError = error;
      _downloadFinished = true;
      _signalDataChanged();
      _onError?.call(error, stackTrace);
    } finally {
      try {
        await iterator.cancel();
      } catch (_) {}
      try {
        await _writer?.close();
      } catch (_) {}
      _writer = null;
    }
  }

  void _queueFeed(AudioSource source, int offset) {
    _feedChain = _feedChain.then((_) => _feed(source, offset)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (!_disposed) _onError?.call(error, stackTrace);
    });
  }

  Future<void> _feed(AudioSource source, int offset) async {
    if (_disposed || source != _source || offset < 0 || offset >= _totalBytes) {
      return;
    }

    Uint8List bytes;
    if (offset < _downloadedBytes) {
      bytes = await _readCachedChunk(offset);
    } else if (offset > _downloadedBytes + _encodedChunkSizeBytes) {
      bytes = await _fetchRangeOrWait(offset);
    } else {
      await _waitForOffset(offset);
      if (_disposed || source != _source) return;
      bytes = await _readCachedChunk(offset);
    }

    if (bytes.isEmpty || _disposed || source != _source) return;
    SoLoud.instance.addPullBufferDataStream(source, bytes, offset: offset);
  }

  Future<Uint8List> _readCachedChunk(int offset) async {
    while (_renamingCache && !_disposed) {
      await _dataChanged.future;
    }
    if (_disposed) return Uint8List(0);
    final available = _downloadedBytes - offset;
    if (available <= 0) return Uint8List(0);
    final length = available.clamp(0, _encodedChunkSizeBytes);

    _activeReaders++;
    RandomAccessFile? reader;
    try {
      reader = await _readFile!.open(mode: FileMode.read);
      await reader.setPosition(offset);
      return Uint8List.fromList(await reader.read(length));
    } finally {
      await reader?.close();
      _activeReaders--;
      _signalDataChanged();
    }
  }

  Future<Uint8List> _fetchRangeOrWait(int offset) async {
    final end = (offset + _encodedChunkSizeBytes - 1).clamp(0, _totalBytes - 1);
    final request = http.Request('GET', _remoteUri)
      ..headers[HttpHeaders.rangeHeader] = 'bytes=$offset-$end';
    final response = await _client.send(request);
    if (response.statusCode == HttpStatus.partialContent) {
      return Uint8List.fromList(await response.stream.toBytes());
    }

    // Some signed cloud endpoints ignore Range. Do not duplicate the entire
    // download; wait for the sequential cache writer instead.
    final ignoredResponse = response.stream.listen((_) {});
    await ignoredResponse.cancel();
    await _waitForOffset(offset);
    return _readCachedChunk(offset);
  }

  Future<void> _waitForOffset(int offset) async {
    while (!_disposed && offset >= _downloadedBytes && !_downloadFinished) {
      final changed = _dataChanged.future;
      await changed;
    }
    if (_downloadError != null) throw _downloadError!;
  }

  Future<void> _waitForReaders() async {
    while (_activeReaders > 0 && !_disposed) {
      final changed = _dataChanged.future;
      await changed;
    }
  }

  void _signalDataChanged() {
    if (!_dataChanged.isCompleted) _dataChanged.complete();
    _dataChanged = Completer<void>();
  }

  Future<void> _probeDurationFromPartialFile() async {
    TagLibFile? tagFile;
    try {
      tagFile = await TagLibFile.openAsync(
        _tempFile.path,
        audioPropertiesStyle: TagLibAudioPropertiesStyle.fast,
      );
      if (tagFile == null) return;

      final parsedDuration = tagFile.duration;
      final bitrateKbps = tagFile.bitrate;
      if (bitrateKbps > 0 && _totalBytes > _downloadedBytes) {
        final partialEstimateMs = (_downloadedBytes * 8) ~/ bitrateKbps;
        final looksPartial =
            parsedDuration <= Duration.zero ||
            (parsedDuration.inMilliseconds - partialEstimateMs).abs() <
                partialEstimateMs ~/ 4;
        if (looksPartial) {
          _reportDuration(
            Duration(milliseconds: (_totalBytes * 8) ~/ bitrateKbps),
          );
          return;
        }
      }
      if (parsedDuration > Duration.zero) _reportDuration(parsedDuration);
    } catch (error) {
      _log.fine('Partial-file duration probe is not ready: $error');
    } finally {
      tagFile?.close();
    }
  }

  void _reportDuration(Duration duration) {
    if (!_disposed && duration > Duration.zero) _onDuration?.call(duration);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _signalDataChanged();
    try {
      await _downloadIterator?.cancel();
    } catch (_) {}
    await _downloadTask;
    _client.close();
    if (await _tempFile.exists()) await _tempFile.delete();
  }
}
