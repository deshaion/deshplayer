import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cloud_node.dart';
import 'cloud_provider.dart';
import 'secure_storage_service.dart';

class YandexDiskProvider implements CloudProvider {
  final SecureStorageService _secureStorage;
  static const String _baseUrl = 'https://cloud-api.yandex.net/v1/disk/resources';

  YandexDiskProvider(this._secureStorage);

  @override
  String get id => 'yandex_disk';

  @override
  String get name => 'Yandex Disk';

  Future<String?> _getToken() async {
    return await _secureStorage.getToken(id);
  }

  @override
  Future<bool> isConnected() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return false;
    // Verify token
    try {
      final response = await http.get(
        Uri.parse('https://cloud-api.yandex.net/v1/disk'),
        headers: {'Authorization': 'OAuth $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> connect(String token) async {
    await _secureStorage.saveToken(id, token);
  }

  @override
  Future<void> disconnect() async {
    await _secureStorage.deleteToken(id);
  }

  @override
  Future<List<CloudNode>> listPath(String path, {int limit = 100, int offset = 0}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not connected');

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'path': path.isEmpty ? 'disk:/' : path,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });

    final response = await http.get(
      uri,
      headers: {'Authorization': 'OAuth $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final embedded = data['_embedded'];
      if (embedded == null || embedded['items'] == null) {
        return [];
      }

      final items = embedded['items'] as List;
      return items.map((item) {
        return CloudNode(
          path: item['path'],
          name: item['name'],
          isDir: item['type'] == 'dir',
          mimeType: item['mime_type'],
          size: item['size'],
          md5: item['md5'],
        );
      }).toList();
    } else {
      throw Exception('Failed to list path: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Future<String?> getDownloadUrl(String path) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not connected');

    final uri = Uri.parse('$_baseUrl/download').replace(queryParameters: {
      'path': path,
    });

    final response = await http.get(
      uri,
      headers: {'Authorization': 'OAuth $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['href'];
    } else {
      throw Exception('Failed to get download URL: ${response.statusCode} - ${response.body}');
    }
  }
}
