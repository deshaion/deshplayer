import 'dart:convert';
import 'dart:io';

import 'package:deshplayer/models/exceptions.dart';
import 'package:deshplayer/services/google_drive_provider.dart';
import 'package:deshplayer/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryStorage extends SecureStorageService {
  final values = <String, String>{};
  @override
  Future<String?> getToken(String providerId) async => values[providerId];
  @override
  Future<void> saveToken(String providerId, String token) async =>
      values[providerId] = token;
  @override
  Future<void> deleteToken(String providerId) async {
    values.remove(providerId);
  }
}

http.Response data(
  Object body, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(jsonEncode(body), status, headers: headers ?? {});

void main() {
  late MemoryStorage storage;
  setUp(() {
    storage = MemoryStorage();
    storage.values['google_drive'] = jsonEncode({
      'access_token': 'test-access',
    });
  });

  test(
    'verifies credentials before saving them and removes them on disconnect',
    () async {
      final provider = GoogleDriveProvider(
        storage,
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer new-access');
          expect(request.url.path, '/drive/v3/about');
          return data({
            'user': {'displayName': 'Listener'},
          });
        }),
      );
      await provider.connect(jsonEncode({'access_token': 'new-access'}));
      expect(
        jsonDecode(storage.values['google_drive']!)['access_token'],
        'new-access',
      );
      expect(await provider.hasCredentials(), isTrue);
      await provider.disconnect();
      expect(await provider.hasCredentials(), isFalse);
    },
  );

  test('invalid credentials do not replace a saved connection', () async {
    final provider = GoogleDriveProvider(
      storage,
      client: MockClient((_) async => data({}, status: 401)),
    );
    await expectLater(
      provider.connect(jsonEncode({'access_token': 'invalid'})),
      throwsA(isA<HttpException>()),
    );
    expect(
      jsonDecode(storage.values['google_drive']!)['access_token'],
      'test-access',
    );
  });

  test(
    'refreshes expired credentials once for simultaneous requests',
    () async {
      storage.values['google_drive'] = jsonEncode({
        'client_id': 'client-id',
        'client_secret': 'client-secret',
        'refresh_token': 'refresh',
        'access_token': 'expired',
        'expires_at': 0,
      });
      var refreshes = 0;
      final provider = GoogleDriveProvider(
        storage,
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://oauth2.googleapis.com/token');
          expect(request.bodyFields['refresh_token'], 'refresh');
          expect(request.bodyFields['client_secret'], 'client-secret');
          refreshes++;
          return data({'access_token': 'renewed', 'expires_in': 3600});
        }),
      );
      final headers = await Future.wait([
        provider.getDownloadHeaders(),
        provider.getDownloadHeaders(),
      ]);
      expect(
        headers.every((h) => h['Authorization'] == 'Bearer renewed'),
        isTrue,
      );
      expect(
        (await provider.getDownloadHeaders())['Authorization'],
        'Bearer renewed',
      );
      expect(refreshes, 1);
      expect(
        jsonDecode(storage.values['google_drive']!)['access_token'],
        'renewed',
      );
    },
  );

  test(
    'lists across Drive page tokens, preserving IDs, names, and checksums',
    () async {
      final requests = <http.Request>[];
      final provider = GoogleDriveProvider(
        storage,
        client: MockClient((request) async {
          requests.add(request);
          expect(request.headers['Authorization'], 'Bearer test-access');
          expect(
            request.url.queryParameters['q'],
            contains("'folder' in parents"),
          );
          if (request.url.queryParameters['pageToken'] == null) {
            return data({
              'nextPageToken': 'next',
              'files': [
                {
                  'id': 'one',
                  'name': 'Song.mp3',
                  'mimeType': 'audio/mpeg',
                  'size': '123',
                  'md5Checksum': 'md5',
                  'sha1Checksum': 'sha1',
                  'sha256Checksum': 'sha256',
                },
              ],
            });
          }
          return data({
            'files': [
              {'id': 'two', 'name': 'Song.mp3', 'mimeType': 'audio/mpeg'},
            ],
          });
        }),
      );
      final nodes = await provider.listPath('/@folder~Music', limit: 2);
      expect(requests.length, 2);
      expect(nodes.map((n) => n.path), [
        '/@folder~Music/@one~Song.mp3',
        '/@folder~Music/@two~Song.mp3',
      ]);
      expect(nodes.first.md5, 'md5');
      expect(nodes.first.sha1, 'sha1');
      expect(nodes.first.sha256, 'sha256');
      expect(nodes.first.size, 123);
      final page = await provider.listPath(
        '/@folder~Music',
        limit: 1,
        offset: 1,
      );
      expect(page.single.path, '/@folder~Music/@two~Song.mp3');
    },
  );

  test(
    'download URLs use stable file IDs without exposing OAuth tokens',
    () async {
      final provider = GoogleDriveProvider(
        storage,
        client: MockClient((request) async {
          expect(request.url.path, '/drive/v3/files/song-id');
          expect(request.headers['Authorization'], 'Bearer test-access');
          return data({
            'id': 'song-id',
            'mimeType': 'audio/mpeg',
            'capabilities': {'canDownload': true},
          });
        }),
      );
      final url = await provider.getDownloadUrl(
        '/@folder~Music/@song-id~Song.mp3',
      );
      expect(Uri.parse(url!).queryParameters['alt'], 'media');
      expect(url, isNot(contains('test-access')));
    },
  );

  test('missing or trashed files report CloudFileNotFoundException', () async {
    for (final response in [
      data({}, status: 404),
      data({'trashed': true}),
    ]) {
      final provider = GoogleDriveProvider(
        storage,
        client: MockClient((_) async => response),
      );
      await expectLater(
        provider.getDownloadUrl('/@gone~Missing.mp3'),
        throwsA(isA<CloudFileNotFoundException>()),
      );
    }
  });

  test(
    'uploads existing files with PATCH and streams original bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp('drive_upload');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/metadata.json',
      ).writeAsString('{"title":"Song"}');
      final requests = <http.Request>[];
      final provider = GoogleDriveProvider(
        storage,
        client: MockClient((request) async {
          requests.add(request);
          expect(request.headers['Authorization'], 'Bearer test-access');
          if (request.method == 'PATCH') {
            expect(request.url.path, '/upload/drive/v3/files/existing');
            expect(request.url.queryParameters['uploadType'], 'resumable');
            return data(
              {},
              headers: {
                'location': 'https://www.googleapis.com/upload/session',
              },
            );
          }
          expect(request.method, 'PUT');
          expect(request.body, '{"title":"Song"}');
          return data({'id': 'existing'});
        }),
      );
      await provider.uploadFile('/@folder~Music/@existing~metadata.json', file);
      expect(requests.map((r) => r.method), ['PATCH', 'PUT']);
    },
  );

  test('new uploads create missing parent folders', () async {
    final directory = await Directory.systemTemp.createTemp('drive_create');
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/stats.json').writeAsString('{}');
    var folderCreated = false;
    final provider = GoogleDriveProvider(
      storage,
      client: MockClient((request) async {
        if (request.method == 'GET') return data({'files': []});
        if (request.method == 'POST' && request.url.path == '/drive/v3/files') {
          expect(jsonDecode(request.body)['name'], 'Statistics');
          folderCreated = true;
          return data({'id': 'stats-folder'});
        }
        if (request.method == 'POST') {
          expect(jsonDecode(request.body)['parents'], ['stats-folder']);
          expect(jsonDecode(request.body)['name'], 'stats.json');
          return data(
            {},
            headers: {'location': 'https://www.googleapis.com/upload/session'},
          );
        }
        expect(request.method, 'PUT');
        return data({'id': 'new-file'});
      }),
    );
    await provider.uploadFile('/Statistics/stats.json', file);
    expect(folderCreated, isTrue);
  });

  test(
    'duplicate metadata uses a stable ID for reads and PATCH updates',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'drive_duplicates',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/metadata.json',
      ).writeAsString('{}');
      var lists = 0;
      var patches = 0;
      final provider = GoogleDriveProvider(
        storage,
        client: MockClient((request) async {
          if (request.url.path == '/drive/v3/files') {
            lists++;
            expect(
              request.url.queryParameters['q'],
              contains("mimeType != 'application/vnd.google-apps.folder'"),
            );
            // Change order between lookup and upload; the chosen ID must not change.
            return data({
              'files': lists == 1
                  ? [
                      {'id': 'z-copy'},
                      {'id': 'a-copy'},
                    ]
                  : [
                      {'id': 'a-copy'},
                      {'id': 'z-copy'},
                    ],
            });
          }
          if (request.method == 'GET') {
            expect(request.url.path, '/drive/v3/files/a-copy');
            return data({'mimeType': 'application/json'});
          }
          if (request.method == 'PATCH') {
            patches++;
            expect(request.url.path, '/upload/drive/v3/files/a-copy');
            return data(
              {},
              headers: {
                'location': 'https://www.googleapis.com/upload/session',
              },
            );
          }
          expect(request.method, 'PUT');
          return data({'id': 'a-copy'});
        }),
      );
      final url = await provider.getDownloadUrl('/@folder~Music/metadata.json');
      expect(Uri.parse(url!).path, '/drive/v3/files/a-copy');
      await provider.uploadFile('/@folder~Music/metadata.json', file);
      expect(patches, 1);
    },
  );

  test('duplicate audio filenames still require explicit Drive IDs', () async {
    final provider = GoogleDriveProvider(
      storage,
      client: MockClient((request) async {
        return data({
          'files': [
            {'id': 'one'},
            {'id': 'two'},
          ],
        });
      }),
    );
    await expectLater(
      provider.getDownloadUrl('/@folder~Music/Song.mp3'),
      throwsA(isA<StateError>()),
    );
  });

  test('metadata copies are collected across all result pages', () async {
    final provider = GoogleDriveProvider(
      storage,
      client: MockClient((request) async {
        if (request.url.queryParameters['pageToken'] == null) {
          return data({
            'files': [
              {'id': 'new', 'modifiedTime': '2026-10-19T02:00:00Z'},
            ],
            'nextPageToken': 'next',
          });
        }
        return data({
          'files': [
            {'id': 'old', 'modifiedTime': '2026-10-19T01:00:00Z'},
          ],
        });
      }),
    );
    expect(await provider.metadataFilePaths('/@folder~Music'), [
      '/@folder~folder/@old~metadata.json',
      '/@folder~folder/@new~metadata.json',
    ]);
  });

  test('OAuth failures do not disclose tokens or client secrets', () async {
    storage.values['google_drive'] = jsonEncode({
      'refresh_token': 'secret-refresh',
      'client_id': 'client',
      'client_secret': 'secret-client',
    });
    final provider = GoogleDriveProvider(
      storage,
      client: MockClient(
        (_) async => data({
          'error_description': 'secret-refresh secret-client',
        }, status: 400),
      ),
    );
    await expectLater(
      provider.getDownloadHeaders(),
      throwsA(
        predicate(
          (error) =>
              !error.toString().contains('secret-refresh') &&
              !error.toString().contains('secret-client'),
        ),
      ),
    );
  });
}
