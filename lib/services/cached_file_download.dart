import 'dart:io';

import 'package:http/http.dart' as http;

/// Only exposes a cache file after a complete download; failed copies are removed.
Future<void> downloadCacheFile({
  required http.Client client,
  required Uri url,
  required File destination,
  required Map<String, String> headers,
}) async {
  final temporary = File('${destination.path}.precache.tmp');
  IOSink? sink;
  try {
    final response = await client.send(
      http.Request('GET', url)..headers.addAll(headers),
    );
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw HttpException(
        'Cache download failed: HTTP ${response.statusCode}',
        uri: url,
      );
    }
    sink = temporary.openWrite();
    var received = 0;
    await sink.addStream(
      response.stream.map((chunk) {
        received += chunk.length;
        return chunk;
      }),
    );
    await sink.close();
    sink = null;
    if (received == 0 ||
        (response.contentLength != null &&
            received != response.contentLength)) {
      throw HttpException('Cache download was incomplete', uri: url);
    }
    await temporary.rename(destination.path);
  } finally {
    try {
      await sink?.close();
    } catch (_) {
      // addStream can close the sink after an error; preserve that original error.
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
