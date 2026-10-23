import 'dart:io';

import 'package:deshplayer/services/cached_file_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  late File destination;
  final url = Uri.parse(
    'https://www.googleapis.com/drive/v3/files/test?alt=media',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atomic_cache');
    destination = File('${directory.path}/track');
  });
  tearDown(() => directory.delete(recursive: true));

  test('only publishes the completed download', () async {
    final client = MockClient.streaming((request, body) async {
      expect(request.headers['Authorization'], 'Bearer test');
      return http.StreamedResponse(
        Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
        200,
        contentLength: 4,
      );
    });
    addTearDown(client.close);
    await downloadCacheFile(
      client: client,
      url: url,
      destination: destination,
      headers: {'Authorization': 'Bearer test'},
    );
    expect(await destination.readAsBytes(), [1, 2, 3, 4]);
    expect(await File('${destination.path}.precache.tmp').exists(), isFalse);
  });

  test(
    'mid-download connection loss does not leave a partial cache file',
    () async {
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          (() async* {
            yield [1, 2];
            throw const SocketException('Connection reset');
          })(),
          200,
          contentLength: 4,
        ),
      );
      addTearDown(client.close);
      await expectLater(
        downloadCacheFile(
          client: client,
          url: url,
          destination: destination,
          headers: {},
        ),
        throwsA(isA<SocketException>()),
      );
      expect(await destination.exists(), isFalse);
      expect(await File('${destination.path}.precache.tmp').exists(), isFalse);
    },
  );

  test('a truncated response preserves the existing cache', () async {
    await destination.writeAsBytes([9, 9]);
    final client = MockClient.streaming(
      (_, _) async =>
          http.StreamedResponse(Stream.value([1, 2]), 200, contentLength: 4),
    );
    addTearDown(client.close);
    await expectLater(
      downloadCacheFile(
        client: client,
        url: url,
        destination: destination,
        headers: {},
      ),
      throwsA(isA<HttpException>()),
    );
    expect(await destination.readAsBytes(), [9, 9]);
    expect(await File('${destination.path}.precache.tmp').exists(), isFalse);
  });
}
