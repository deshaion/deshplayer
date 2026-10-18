import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:deshplayer/models/track.dart';
import 'package:deshplayer/services/cache_export_service.dart';

Track track(String id, {String? localPath, String? cloudPath}) => Track(
  id: id,
  cloudPath: cloudPath ?? 'cloud://music/$id.mp3',
  localCachePath: localPath,
  duration: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'lists existing nonempty caches, excluding partial and stale entries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cache_export_test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final complete = await File(
        '${directory.path}/complete',
      ).writeAsBytes([1, 2, 3]);
      await File('${directory.path}/empty').create();
      final partial = await File(
        '${directory.path}/pending.tmp',
      ).writeAsBytes([1]);
      await File('${directory.path}/fallback').writeAsBytes([4, 5]);

      final entries = await CacheExportService().findCachedTracks([
        track('complete', localPath: complete.path),
        track('missing', localPath: '${directory.path}/missing'),
        track('empty', localPath: '${directory.path}/empty'),
        track('pending', localPath: partial.path),
        track('fallback'),
      ], directory);

      expect(entries.map((entry) => entry.track.id), ['complete', 'fallback']);
      expect(entries.map((entry) => entry.size), [3, 2]);
      expect(await complete.readAsBytes(), [1, 2, 3]);
    },
  );

  test('export filenames preserve extension and remove path separators', () {
    expect(
      CacheExportService.fileName(
        track('a', cloudPath: 'cloud://music/01%20Song.flac'),
      ),
      '01 Song.flac',
    );
    expect(
      CacheExportService.fileName(
        track('a', cloudPath: 'cloud://music/a%2Fb%5Cc.mp3'),
      ),
      'a_b_c.mp3',
    );
    expect(
      CacheExportService.fileName(track('a', cloudPath: 'cloud://music/..')),
      'Track',
    );
    expect(
      CacheExportService.fileName(
        track('a', cloudPath: 'cloud://music/100%.mp3'),
      ),
      '100%.mp3',
    );
  });

  const channel = MethodChannel('deshplayer/cache_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends selected files and returns partial copy failures', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return {
        'copied': 1,
        'failed': ['b.mp3'],
      };
    });
    final result = await CacheExportService().exportTracks([
      CachedTrack(track('a'), '/cache/a', 10),
      CachedTrack(track('b'), '/cache/b', 20),
    ]);
    expect(received!.method, 'exportTracks');
    expect(received!.arguments, {
      'files': [
        {'path': '/cache/a', 'name': 'a.mp3'},
        {'path': '/cache/b', 'name': 'b.mp3'},
      ],
    });
    expect(result!.copied, 1);
    expect(result.failed, ['b.mp3']);
  });

  test('dismissing the folder picker cancels without a copy result', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      await CacheExportService().exportTracks([
        CachedTrack(track('a'), '/cache/a', 10),
      ]),
      isNull,
    );
  });

  test('logs missing native handler failures before rethrowing', () async {
    final records = <LogRecord>[];
    final subscription = Logger(
      'CacheExportService',
    ).onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );

    await expectLater(
      CacheExportService().exportTracks([
        CachedTrack(track('a'), '/cache/a', 10),
      ]),
      throwsA(isA<MissingPluginException>()),
    );
    expect(
      records.any(
        (record) =>
            record.level == Level.SEVERE &&
            record.error is MissingPluginException,
      ),
      isTrue,
    );
  });

  test('logs native picker error details', () async {
    final records = <LogRecord>[];
    final subscription = Logger(
      'CacheExportService',
    ).onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'folder_picker',
        message: 'Could not open the folder picker.',
        details: 'ActivityNotFoundException',
      ),
    );

    await expectLater(
      CacheExportService().exportTracks([
        CachedTrack(track('a'), '/cache/a', 10),
      ]),
      throwsA(isA<PlatformException>()),
    );
    expect(
      records.any(
        (record) =>
            record.level == Level.SEVERE &&
            record.message.contains('ActivityNotFoundException'),
      ),
      isTrue,
    );
  });

  test('logs individual copy failure reasons', () async {
    final records = <LogRecord>[];
    final subscription = Logger(
      'CacheExportService',
    ).onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'copied': 0,
        'failed': ['a.mp3'],
        'errors': ['a.mp3: No space left on device'],
      },
    );

    await CacheExportService().exportTracks([
      CachedTrack(track('a'), '/cache/a', 10),
    ]);
    expect(
      records.any(
        (record) =>
            record.level == Level.WARNING &&
            record.message.contains('No space left on device'),
      ),
      isTrue,
    );
  });
}
