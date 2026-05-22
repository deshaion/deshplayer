import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/hive_storage_service.dart';
import 'services/player_provider.dart';
import 'ui/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = HiveStorageService();
  await storageService.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => PlayerProvider(storageService),
      child: DeshPlayerApp(storageService: storageService),
    ),
  );
}
