import 'dart:io';

import 'package:deshplayer/services/network_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

void main() {
  final uri = Uri.parse(
    'https://www.googleapis.com/drive/v3/files/test?alt=media',
  );

  test(
    'recovers from DNS errors, preserving authentication and Range',
    () async {
      var attempts = 0;
      final logs = <LogRecord>[];
      final subscription = Logger(
        'NetworkHttpClient',
      ).onRecord.listen(logs.add);
      addTearDown(subscription.cancel);
      final client = NetworkHttpClient(
        retryDelay: (_) => Duration.zero,
        inner: MockClient((request) async {
          attempts++;
          expect(request.headers['Authorization'], 'Bearer private-token');
          expect(request.headers['Range'], 'bytes=100-199');
          if (attempts == 1) throw const SocketException('Failed host lookup');
          if (attempts == 2) {
            throw http.ClientException(
              'SocketException: Failed host lookup',
              uri,
            );
          }
          return http.Response('audio', 206);
        }),
      );
      addTearDown(client.close);
      final response = await client.get(
        uri,
        headers: {
          'Authorization': 'Bearer private-token',
          'Range': 'bytes=100-199',
        },
      );
      expect(response.statusCode, 206);
      expect(attempts, 3);
      expect(logs.where((r) => r.message.startsWith('Retry')).length, 2);
      expect(logs.any((r) => r.message.contains('private-token')), isFalse);
    },
  );

  test('persistent network failure stops after four attempts', () async {
    var attempts = 0;
    final client = NetworkHttpClient(
      retryDelay: (_) => Duration.zero,
      inner: MockClient((_) async {
        attempts++;
        throw const SocketException('offline');
      }),
    );
    addTearDown(client.close);
    await expectLater(client.get(uri), throwsA(isA<SocketException>()));
    expect(attempts, 4);
  });

  test(
    'temporary server errors are retried, permissions and missing files are not',
    () async {
      for (final code in [408, 429, 500, 502, 503, 504, 401, 403, 404]) {
        var attempts = 0;
        final client = NetworkHttpClient(
          retryDelay: (_) => Duration.zero,
          inner: MockClient((_) async {
            attempts++;
            return http.Response('', code);
          }),
        );
        addTearDown(client.close);
        expect((await client.get(uri)).statusCode, code);
        expect(attempts, [401, 403, 404].contains(code) ? 1 : 4);
      }
    },
  );

  test('token refresh retries retain the form body', () async {
    var attempts = 0;
    final client = NetworkHttpClient(
      retryDelay: (_) => Duration.zero,
      inner: MockClient((request) async {
        attempts++;
        expect(request.bodyFields['refresh_token'], 'refresh');
        if (attempts == 1) throw const SocketException('DNS');
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    await client.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {'refresh_token': 'refresh'},
    );
    expect(attempts, 2);
  });

  test('upload creation is not replayed on network failure', () async {
    var attempts = 0;
    final client = NetworkHttpClient(
      retryDelay: (_) => Duration.zero,
      inner: MockClient((_) async {
        attempts++;
        throw const SocketException('DNS');
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.post(
        Uri.parse('https://www.googleapis.com/upload/drive/v3/files'),
        body: '{}',
      ),
      throwsA(isA<SocketException>()),
    );
    expect(attempts, 1);
  });

  test('closing during a request prevents more retries', () async {
    var attempts = 0;
    late NetworkHttpClient client;
    client = NetworkHttpClient(
      retryDelay: (_) => Duration.zero,
      inner: MockClient((_) async {
        attempts++;
        client.close();
        throw const SocketException('closed');
      }),
    );
    await expectLater(client.get(uri), throwsA(isA<SocketException>()));
    expect(attempts, 1);
  });
}
