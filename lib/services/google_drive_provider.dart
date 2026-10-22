import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../models/cloud_node.dart';
import '../models/exceptions.dart';
import 'cloud_provider.dart';
import 'network_http_client.dart';
import 'secure_storage_service.dart';

class GoogleDriveProvider implements CloudProvider {
  GoogleDriveProvider(this._storage, {http.Client? client})
    : _client = NetworkHttpClient(inner: client);

  final SecureStorageService _storage;
  final http.Client _client;
  final _log = Logger('GoogleDriveProvider');
  Future<Map<String, String>>? _refreshing;
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _folderType = 'application/vnd.google-apps.folder';
  static const _fields =
      'id,name,mimeType,size,md5Checksum,sha1Checksum,sha256Checksum,modifiedTime';

  @override
  String get id => 'google_drive';
  @override
  String get name => 'Google Drive';

  @override
  Future<bool> hasCredentials() async =>
      (await _storage.getToken(id))?.isNotEmpty ?? false;

  Map<String, dynamic> _parseCredentials(String value) {
    final data = Map<String, dynamic>.from(jsonDecode(value) as Map);
    final refresh = (data['refresh_token'] as String? ?? '').trim();
    final clientId = (data['client_id'] as String? ?? '').trim();
    final access = (data['access_token'] as String? ?? '').trim();
    if (access.isEmpty && (refresh.isEmpty || clientId.isEmpty)) {
      throw const FormatException(
        'Enter an access token, or a client ID and refresh token.',
      );
    }
    if (refresh.isNotEmpty && clientId.isEmpty) {
      throw const FormatException(
        'A client ID is required with a refresh token.',
      );
    }
    return data;
  }

  @override
  Future<void> connect(String token) async {
    final credentials = _parseCredentials(token);
    final headers = await _headers(credentials);
    final response = await _client.get(
      Uri.parse(
        '$_api/about',
      ).replace(queryParameters: {'fields': 'user(displayName)'}),
      headers: headers,
    );
    _check(response, 'Connect to Google Drive');
    await _storage.saveToken(id, jsonEncode(credentials));
    _log.info('Google Drive connected');
  }

  @override
  Future<void> disconnect() async {
    await _storage.deleteToken(id);
    _log.info('Google Drive credentials removed');
  }

  @override
  Future<bool> isConnected() async {
    if (!await hasCredentials()) return false;
    final response = await _client.get(
      Uri.parse(
        '$_api/about',
      ).replace(queryParameters: {'fields': 'user(displayName)'}),
      headers: await getDownloadHeaders(),
    );
    _check(response, 'Check Google Drive connection');
    return true;
  }

  Future<Map<String, String>> _headers(Map<String, dynamic> credentials) async {
    var token = credentials['access_token'] as String? ?? '';
    final expires = credentials['expires_at'] as int?;
    // Refresh credentials without an expiry are renewed on first use.
    final canRefresh =
        (credentials['refresh_token'] as String? ?? '').isNotEmpty;
    if (token.isEmpty ||
        (canRefresh &&
            (expires == null ||
                DateTime.now().millisecondsSinceEpoch >= expires - 60000))) {
      if (!canRefresh) {
        throw StateError(
          'Google Drive access token expired. Reconnect in Settings.',
        );
      }
      final response = await _client.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'grant_type': 'refresh_token',
          'client_id': credentials['client_id'] as String,
          'refresh_token': credentials['refresh_token'] as String,
          if ((credentials['client_secret'] as String? ?? '').isNotEmpty)
            'client_secret': credentials['client_secret'] as String,
        },
      );
      if (response.statusCode != 200) {
        // Never include token responses or supplied credentials in logs/errors.
        throw StateError(
          'Google OAuth token refresh failed (${response.statusCode}). Check your credentials and reconnect.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      token = data['access_token'] as String;
      credentials['access_token'] = token;
      credentials['expires_at'] =
          DateTime.now().millisecondsSinceEpoch +
          (data['expires_in'] as int? ?? 3600) * 1000;
    }
    return {'Authorization': 'Bearer $token'};
  }

  @override
  Future<Map<String, String>> getDownloadHeaders() async {
    if (_refreshing != null) return _refreshing!;
    final task = _storedHeaders();
    _refreshing = task;
    try {
      return await task;
    } finally {
      _refreshing = null;
    }
  }

  Future<Map<String, String>> _storedHeaders() async {
    final stored = await _storage.getToken(id);
    if (stored == null) {
      throw StateError('Connect to Google Drive in Settings.');
    }
    final credentials = _parseCredentials(stored);
    final headers = await _headers(credentials);
    if (jsonEncode(credentials) != stored) {
      await _storage.saveToken(id, jsonEncode(credentials));
    }
    return headers;
  }

  void _check(http.Response response, String operation) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 404) {
      throw CloudFileNotFoundException(
        'Google Drive file or folder not found, or access was removed.',
      );
    }
    final message = response.statusCode == 401
        ? 'Credentials expired or are invalid. Reconnect in Settings.'
        : response.statusCode == 403
        ? 'Check Drive API is enabled, OAuth scopes, and file permissions.'
        : 'Please try again.';
    _log.warning('$operation failed: HTTP ${response.statusCode}');
    throw HttpException('$operation failed (${response.statusCode}). $message');
  }

  String _quote(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  // Listed paths retain Drive IDs so duplicate filenames remain distinct.
  String? _embeddedId(String segment) {
    final match = RegExp(r'^@([A-Za-z0-9_-]+)~').firstMatch(segment);
    return match?.group(1);
  }

  Future<List<Map<String, dynamic>>> _list(
    String query, {
    int? maxItems,
  }) async {
    final files = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final response = await _client.get(
        Uri.parse('$_api/files').replace(
          queryParameters: {
            'q': 'trashed = false and ($query)',
            'fields': 'nextPageToken,files($_fields)',
            'pageSize': '1000',
            'orderBy': 'folder,name_natural',
            'supportsAllDrives': 'true',
            'includeItemsFromAllDrives': 'true',
            'pageToken': ?pageToken,
          },
        ),
        headers: await getDownloadHeaders(),
      );
      _check(response, 'List Google Drive files');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      files.addAll(
        (data['files'] as List).map((f) => Map<String, dynamic>.from(f as Map)),
      );
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null &&
        (maxItems == null || files.length < maxItems));
    return files;
  }

  Future<String> _resolve(String path, {bool createFolders = false}) async {
    var parent = 'root';
    final segments = _segments(path);
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final embedded = _embeddedId(segment);
      if (embedded != null) {
        parent = embedded;
        continue;
      }
      final isMetadata =
          !createFolders &&
          index == segments.length - 1 &&
          Uri.decodeComponent(segment) == 'metadata.json';
      final matches = isMetadata
          ? await _metadataMatches(parent)
          : await _list(
              "'${_quote(parent)}' in parents and name = '${_quote(Uri.decodeComponent(segment))}'",
              maxItems: 2,
            );
      if (matches.length > 1 && !isMetadata) {
        throw StateError(
          'More than one Drive item has this name. Choose the folder from the cloud browser.',
        );
      }
      if (matches.isEmpty) {
        if (!createFolders) {
          throw CloudFileNotFoundException('Google Drive path not found.');
        }
        final response = await _client.post(
          Uri.parse('$_api/files').replace(
            queryParameters: {'fields': 'id', 'supportsAllDrives': 'true'},
          ),
          headers: {
            ...await getDownloadHeaders(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'name': Uri.decodeComponent(segment),
            'mimeType': _folderType,
            'parents': [parent],
          }),
        );
        _check(response, 'Create Google Drive folder');
        parent = (jsonDecode(response.body) as Map)['id'] as String;
      } else {
        // Drive permits duplicate names. Keep one stable metadata file across
        // reads and writes, independent of list order and modification times.
        parent = isMetadata
            ? (matches.map((file) => file['id'] as String).toList()..sort())
                  .first
            : matches.single['id'] as String;
      }
    }
    return parent;
  }

  Future<List<Map<String, dynamic>>> _metadataMatches(String parent) => _list(
    "'${_quote(parent)}' in parents and name = 'metadata.json' and mimeType != '$_folderType'",
  );

  /// All metadata copies, oldest first so newer entries win when merged.
  Future<List<String>> metadataFilePaths(String directory) async {
    final parent = await _resolve(directory);
    final matches = await _metadataMatches(parent);
    matches.sort((a, b) {
      final byTime = (a['modifiedTime'] as String? ?? '').compareTo(
        b['modifiedTime'] as String? ?? '',
      );
      return byTime != 0
          ? byTime
          : (a['id'] as String).compareTo(b['id'] as String);
    });
    // Use the parent ID too, avoiding repeated resolution of named ancestors.
    return matches
        .map((file) => '/@$parent~folder/@${file['id']}~metadata.json')
        .toList();
  }

  @override
  Future<List<CloudNode>> listPath(
    String path, {
    int limit = 100,
    int offset = 0,
  }) async {
    if (limit <= 0 || offset < 0) throw ArgumentError('Invalid pagination');
    final folder = await _resolve(path);
    final files = await _list(
      "'${_quote(folder)}' in parents",
      maxItems: offset + limit,
    );
    final prefix = path.replaceAll(RegExp(r'/+$'), '');
    return files
        .skip(offset)
        .take(limit)
        .map(
          (file) => CloudNode(
            path:
                '$prefix/@${file['id']}~${Uri.encodeComponent(file['name'] as String)}',
            name: file['name'] as String,
            isDir: file['mimeType'] == _folderType,
            mimeType: file['mimeType'] as String?,
            size: int.tryParse('${file['size'] ?? ''}'),
            md5: file['md5Checksum'] as String?,
            sha1: file['sha1Checksum'] as String?,
            sha256: file['sha256Checksum'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<String?> getDownloadUrl(String path) async {
    final fileId = await _resolve(path);
    final uri = Uri.parse('$_api/files/${Uri.encodeComponent(fileId)}');
    final response = await _client.get(
      uri.replace(
        queryParameters: {
          'fields': 'id,mimeType,trashed,capabilities(canDownload)',
          'supportsAllDrives': 'true',
        },
      ),
      headers: await getDownloadHeaders(),
    );
    _check(response, 'Get Google Drive file');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['trashed'] == true) {
      throw CloudFileNotFoundException('Google Drive file is in the trash.');
    }
    if ((data['mimeType'] as String).startsWith(
      'application/vnd.google-apps.',
    )) {
      throw StateError(
        'This Google Drive item is not a downloadable audio or data file.',
      );
    }
    if ((data['capabilities'] as Map?)?['canDownload'] == false) {
      throw StateError('Downloading this file is disabled by its owner.');
    }
    return uri
        .replace(queryParameters: {'alt': 'media', 'supportsAllDrives': 'true'})
        .toString();
  }

  @override
  Future<void> uploadFile(String path, File file) async {
    final segments = _segments(path);
    if (segments.isEmpty) throw ArgumentError('An upload filename is required');
    String? fileId;
    try {
      fileId = await _resolve(path);
    } on CloudFileNotFoundException {
      // A new file needs metadata and a parent; existing files keep their ID.
    }
    final metadata = <String, dynamic>{};
    if (fileId == null) {
      metadata['name'] = Uri.decodeComponent(segments.last);
      metadata['parents'] = [
        await _resolve(
          segments.take(segments.length - 1).join('/'),
          createFolders: true,
        ),
      ];
    }
    final endpoint =
        'https://www.googleapis.com/upload/drive/v3/files${fileId == null ? '' : '/${Uri.encodeComponent(fileId)}'}';
    final response = await _client.send(
      http.Request(
          fileId == null ? 'POST' : 'PATCH',
          Uri.parse(endpoint).replace(
            queryParameters: {
              'uploadType': 'resumable',
              'supportsAllDrives': 'true',
            },
          ),
        )
        ..headers.addAll({
          ...await getDownloadHeaders(),
          'Content-Type': 'application/json',
          'X-Upload-Content-Length': '${await file.length()}',
          'X-Upload-Content-Type': 'application/octet-stream',
        })
        ..body = jsonEncode(metadata),
    );
    final sessionResponse = await http.Response.fromStream(response);
    _check(sessionResponse, 'Start Google Drive upload');
    final location = sessionResponse.headers['location'];
    if (location == null) {
      throw StateError('Google Drive did not return an upload session.');
    }
    final session = Uri.parse(location);
    if (session.scheme != 'https' || session.host != 'www.googleapis.com') {
      throw StateError('Google Drive returned an unexpected upload session.');
    }
    final request = http.StreamedRequest('PUT', session)
      ..headers.addAll({
        ...await getDownloadHeaders(),
        'Content-Type': 'application/octet-stream',
      })
      ..contentLength = await file.length();
    final upload = _client.send(request);
    await file.openRead().pipe(request.sink);
    final result = await http.Response.fromStream(await upload);
    _check(result, 'Upload Google Drive file');
    _log.info('Google Drive upload completed');
  }
}
