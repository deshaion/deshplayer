// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 3;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      maxCacheSizeBytes: fields[0] as int,
      localMusicCacheFolder: fields[1] as String?,
      shuffle: fields[2] as bool,
      repeatMode: fields[3] as int,
      volume: fields[4] as double,
      lastActivePlaylistId: fields[5] as String?,
      cloudStatsFolder: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.maxCacheSizeBytes)
      ..writeByte(1)
      ..write(obj.localMusicCacheFolder)
      ..writeByte(2)
      ..write(obj.shuffle)
      ..writeByte(3)
      ..write(obj.repeatMode)
      ..writeByte(4)
      ..write(obj.volume)
      ..writeByte(5)
      ..write(obj.lastActivePlaylistId)
      ..writeByte(6)
      ..write(obj.cloudStatsFolder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
