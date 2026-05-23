import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/hive_storage_service.dart';
import 'services/stats_service.dart';
import 'services/player_provider.dart';
import 'ui/app.dart';
import 'package:logging/logging.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] (${record.loggerName}): ${record.message}');
    if (record.error != null) print('Error: ${record.error}');
  });

  WidgetsFlutterBinding.ensureInitialized();

  JustAudioMediaKit.ensureInitialized(
    linux: true,
    windows: false,
    android: false,
    iOS: false,
    macOS: false,
  );

  final storageService = HiveStorageService();
  await storageService.init();

  final statsService = StatsService();
  await statsService.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => PlayerProvider(storageService),
      child: DeshPlayerApp(storageService: storageService),
    ),
  );
}
