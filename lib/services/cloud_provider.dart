import 'dart:io';
import '../models/cloud_node.dart';

abstract class CloudProvider {
  String get id;
  String get name;

  Future<bool> isConnected();
  Future<void> connect(String token);
  Future<void> disconnect();

  Future<List<CloudNode>> listPath(String path, {int limit = 100, int offset = 0});
  Future<String?> getDownloadUrl(String path);
  Future<void> uploadFile(String path, File file);
}
