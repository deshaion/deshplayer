import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'services/hive_storage_service.dart';
import 'services/stats_service.dart';
import 'services/player_provider.dart';
import 'ui/app.dart';
import 'package:logging/logging.dart';
import 'models/app_log_record.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = HiveStorageService();
  await storageService.init();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] (${record.loggerName}): ${record.message}');
    if (record.error != null) print('Error: ${record.error}');

    // Save to Hive
    storageService.addLog(AppLogRecord(
      level: record.level.name,
      loggerName: record.loggerName,
      message: record.message,
      error: record.error?.toString(),
      time: record.time,
    ));
  });

  storageService.checkTrackDb();

  await SoLoud.instance.init();
  SoLoud.instance.setVisualizationEnabled(true);

  final statsService = StatsService();
  await statsService.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => PlayerProvider(storageService),
      child: DeshPlayerApp(storageService: storageService),
    ),
  );
}
