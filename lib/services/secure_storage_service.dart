import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveToken(String providerId, String token) async {
    await _storage.write(key: '${providerId}_token', value: token);
  }

  Future<String?> getToken(String providerId) async {
    return await _storage.read(key: '${providerId}_token');
  }

  Future<void> deleteToken(String providerId) async {
    await _storage.delete(key: '${providerId}_token');
  }
}
