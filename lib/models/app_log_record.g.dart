// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_log_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppLogRecordAdapter extends TypeAdapter<AppLogRecord> {
  @override
  final int typeId = 4;

  @override
  AppLogRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppLogRecord(
      level: fields[0] as String,
      loggerName: fields[1] as String,
      message: fields[2] as String,
      error: fields[3] as String?,
      time: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, AppLogRecord obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.level)
      ..writeByte(1)
      ..write(obj.loggerName)
      ..writeByte(2)
      ..write(obj.message)
      ..writeByte(3)
      ..write(obj.error)
      ..writeByte(4)
      ..write(obj.time);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppLogRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
