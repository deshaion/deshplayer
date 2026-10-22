import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/retry.dart';
import 'package:logging/logging.dart';

/// Retries safe reads and Google's token refresh, without buffering file uploads.
class NetworkHttpClient extends http.BaseClient {
  NetworkHttpClient({http.Client? inner, Duration Function(int)? retryDelay}) {
    _inner =
        inner ??
        IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 15));
    _retry = RetryClient(
      _inner,
      retries: 3,
      delay:
          retryDelay ??
          (attempt) =>
              Duration(milliseconds: (1000 << attempt) + _random.nextInt(250)),
      when: (response) =>
          !_closed &&
          const {408, 429, 500, 502, 503, 504}.contains(response.statusCode),
      whenError: (error, _) =>
          !_closed &&
          error is! http.RequestAbortedException &&
          (error is SocketException ||
              error is http.ClientException ||
              error is TimeoutException),
      onRetry: (request, response, attempt) {
        if (_closed) throw http.ClientException('HTTP client closed');
        _log.info(
          'Retry ${attempt + 1}/3: ${request.method} ${request.url.host} '
          'after ${response == null ? 'a network error' : 'HTTP ${response.statusCode}'}',
        );
      },
    );
  }

  static final _random = Random();
  final _log = Logger('NetworkHttpClient');
  late final http.Client _inner;
  late final RetryClient _retry;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) throw http.ClientException('HTTP client closed');
    final safe =
        request.method == 'GET' ||
        request.method == 'HEAD' ||
        (request.method == 'POST' &&
            request.url.host == 'oauth2.googleapis.com' &&
            request.url.path == '/token');
    return (safe ? _retry : _inner).send(request);
  }

  @override
  void close() {
    _closed = true;
    _retry.close();
  }
}
