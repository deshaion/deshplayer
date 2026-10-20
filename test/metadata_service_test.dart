import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:deshplayer/models/duration_adapter.dart';
import 'package:deshplayer/models/track.dart';
import 'package:deshplayer/services/google_drive_provider.dart';
import 'package:deshplayer/services/hive_storage_service.dart';
import 'package:deshplayer/services/metadata_service.dart';
import 'package:deshplayer/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Storage extends SecureStorageService {
  @override
  Future<String?> getToken(String providerId) async =>
      '{"access_token":"test-token"}';
}

http.Response _json(
  Object value, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(jsonEncode(value), status, headers: headers ?? {});

Future<File> _wave(Directory directory) async {
  final bytes = Uint8List(8044)..fillRange(44, 8044, 128);
  final header = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  header.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 8000, Endian.little);
  header.setUint32(28, 8000, Endian.little);
  header.setUint16(32, 1, Endian.little);
  header.setUint16(34, 8, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  header.setUint32(40, 8000, Endian.little);
  return File('${directory.path}/audio.wav').writeAsBytes(bytes);
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('metadata_test');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(200)) Hive.registerAdapter(DurationAdapter());
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(TrackAdapter());
    HiveStorageService().tracksBox = await Hive.openBox<Track>('tracks');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'merges duplicate metadata copies, with newer track values winning',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/drive/v3/files') {
          expect(
            request.url.queryParameters['q'],
            contains("'folder' in parents"),
          );
          return _json({
            'files': [
              {'id': 'new', 'modifiedTime': '2026-10-19T02:00:00Z'},
              {'id': 'old', 'modifiedTime': '2026-10-19T01:00:00Z'},
            ],
          });
        }
        final id = request.url.pathSegments.last;
        if (request.url.queryParameters['alt'] == 'media') {
          expect(request.headers['Authorization'], 'Bearer test-token');
          return _json({
            id: {'title': id},
            'shared': {'title': id},
          });
        }
        return _json({'id': id, 'mimeType': 'application/json'});
      });
      final provider = GoogleDriveProvider(_Storage(), client: client);
      final metadata = await MetadataService(
        client: client,
      ).getCloudMetadata(provider, '/@folder~Music', directory);
      expect(metadata, {
        'old': {'title': 'old'},
        'new': {'title': 'new'},
        'shared': {'title': 'new'},
      });
    },
  );

  test(
    'creates missing metadata once and serializes concurrent track updates',
    () async {
      final audio = await _wave(directory);
      final tracks = [
        for (var index = 1; index <= 2; index++)
          Track(
            id: '$index',
            cloudPath:
                'google_drive:///@folder~Music/@track$index~song$index.wav',
            localCachePath: audio.path,
            title: 'Song $index',
            artist: 'Artist',
            duration: Duration.zero,
          ),
      ];
      Map<String, dynamic>? contents;
      var creates = 0;
      var updates = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/drive/v3/files') {
          return _json({
            'files': [
              if (contents != null)
                {'id': 'metadata', 'mimeType': 'application/json'},
            ],
          });
        }
        if (request.method == 'GET') {
          return request.url.queryParameters['alt'] == 'media'
              ? _json(contents!)
              : _json({'id': 'metadata', 'mimeType': 'application/json'});
        }
        if (request.method == 'POST' || request.method == 'PATCH') {
          if (request.method == 'POST') {
            creates++;
            expect(jsonDecode(request.body)['parents'], ['folder']);
            expect(jsonDecode(request.body)['name'], 'metadata.json');
          } else {
            updates++;
            expect(request.url.path, '/upload/drive/v3/files/metadata');
          }
          return _json(
            {},
            headers: {'location': 'https://www.googleapis.com/upload/session'},
          );
        }
        expect(request.method, 'PUT');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        contents = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({'id': 'metadata'});
      });
      final provider = GoogleDriveProvider(_Storage(), client: client);
      final service = MetadataService(client: client);
      await Future.wait([
        for (final track in tracks)
          service.updateMetadataInCloud(
            provider,
            track.cloudPath,
            track,
            directory,
          ),
      ]);
      expect(creates, 1);
      expect(updates, 1);
      expect(
        contents!.keys,
        unorderedEquals(['@track1~song1.wav', '@track2~song2.wav']),
      );
      expect(contents!['@track1~song1.wav']['durationMs'], 1000);
      expect(
        directory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('_metadata.json'),
        ),
        isEmpty,
      );
    },
  );

  for (final status in [403, 500]) {
    test('read HTTP $status does not overwrite existing metadata', () async {
      final audio = await _wave(directory);
      var writes = 0;
      final client = MockClient((request) async {
        if (request.method != 'GET') writes++;
        if (request.url.path == '/drive/v3/files') {
          return _json({
            'files': [
              {'id': 'existing'},
            ],
          });
        }
        return request.url.queryParameters['alt'] == 'media'
            ? _json({}, status: status)
            : _json({'mimeType': 'application/json'});
      });
      final provider = GoogleDriveProvider(_Storage(), client: client);
      final service = MetadataService(client: client);
      final track = Track(
        id: 'track',
        cloudPath: 'google_drive:///@folder~Music/@track~song.wav',
        localCachePath: audio.path,
        duration: Duration.zero,
      );
      await service.updateMetadataInCloud(
        provider,
        track.cloudPath,
        track,
        directory,
      );
      expect(writes, 0);
      await expectLater(
        service.getCloudMetadata(
          provider,
          '/@folder~Music',
          directory,
          throwOnError: true,
        ),
        throwsA(isA<HttpException>()),
      );
    });
  }

  test('malformed metadata is not treated as a missing file', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/drive/v3/files') {
        return _json({
          'files': [
            {'id': 'existing'},
          ],
        });
      }
      return request.url.queryParameters['alt'] == 'media'
          ? http.Response('broken json', 200)
          : _json({'mimeType': 'application/json'});
    });
    final provider = GoogleDriveProvider(_Storage(), client: client);
    await expectLater(
      MetadataService(client: client).getCloudMetadata(
        provider,
        '/@folder~Music',
        directory,
        throwOnError: true,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
