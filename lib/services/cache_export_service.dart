import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../models/track.dart';

class CachedTrack {
  const CachedTrack(this.track, this.path, this.size);

  final Track track;
  final String path;
  final int size;
}

class CacheExportResult {
  const CacheExportResult(this.copied, this.failed);

  final int copied;
  final List<String> failed;
}

class CacheExportService {
  final _log = Logger('CacheExportService');
  static const _channel = MethodChannel('deshplayer/cache_export');

  Future<List<CachedTrack>> findCachedTracks(
    Iterable<Track> tracks,
    Directory cacheDirectory,
  ) async {
    final cached = <CachedTrack>[];
    for (final track in tracks) {
      final path = track.localCachePath ?? '${cacheDirectory.path}/${track.id}';
      // Streaming downloads use .tmp until the complete file is available.
      if (path.endsWith('.tmp')) continue;
      try {
        final stat = await File(path).stat();
        if (stat.type == FileSystemEntityType.file && stat.size > 0) {
          cached.add(CachedTrack(track, path, stat.size));
        }
      } on FileSystemException {
        // Cache cleanup can remove a track while this list is being loaded.
      }
    }
    cached.sort(
      (a, b) => fileName(
        a.track,
      ).toLowerCase().compareTo(fileName(b.track).toLowerCase()),
    );
    return cached;
  }

  static String fileName(Track track) {
    var name = track.cloudPath.split('/').last;
    try {
      name = Uri.decodeComponent(name);
    } on FormatException {
      // Keep literal names that contain an unescaped percent sign.
    } on ArgumentError {
      // decodeComponent also throws for incomplete percent escapes.
    }
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
    name = name.replaceAll(RegExp(r'[. ]+$'), '');
    return name.isEmpty ? 'Track' : name;
  }

  /// Null means that the user dismissed the system folder picker.
  Future<CacheExportResult?> exportTracks(List<CachedTrack> tracks) async {
    if (tracks.isEmpty) return null;
    _log.info('Opening folder picker to export ${tracks.length} cached tracks');
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'exportTracks',
        {
          'files': tracks
              .map(
                (entry) => {'path': entry.path, 'name': fileName(entry.track)},
              )
              .toList(),
        },
      );
      if (result == null) {
        _log.info('Cache export cancelled in folder picker');
        return null;
      }
      final exported = CacheExportResult(
        result['copied'] as int,
        List<String>.from(result['failed'] as List),
      );
      _log.info(
        'Cache export finished: ${exported.copied} copied, '
        '${exported.failed.length} failed',
      );
      if (exported.failed.isNotEmpty) {
        final errors = List<String>.from(
          result['errors'] as List? ?? exported.failed,
        );
        _log.warning('Could not copy cached tracks: ${errors.join('; ')}');
      }
      return exported;
    } on PlatformException catch (error, stackTrace) {
      _log.severe(
        'Cache export failed (${error.code}): ${error.message}; '
        'details: ${error.details}',
        error,
        stackTrace,
      );
      rethrow;
    } catch (error, stackTrace) {
      _log.severe('Cache export failed', error, stackTrace);
      rethrow;
    }
  }
}
