import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/hive_storage_service.dart';
import 'services/player_provider.dart';
import 'ui/app.dart';
import 'package:logging/logging.dart';

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] (${record.loggerName}): ${record.message}');
    if (record.error != null) print('Error: ${record.error}');
  });

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
