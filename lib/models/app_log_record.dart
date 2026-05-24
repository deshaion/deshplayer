import 'package:hive/hive.dart';

part 'app_log_record.g.dart';

@HiveType(typeId: 4)
class AppLogRecord extends HiveObject {
  @HiveField(0)
  final String level;

  @HiveField(1)
  final String loggerName;

  @HiveField(2)
  final String message;

  @HiveField(3)
  final String? error;

  @HiveField(4)
  final DateTime time;

  AppLogRecord({
    required this.level,
    required this.loggerName,
    required this.message,
    this.error,
    required this.time,
  });
}
