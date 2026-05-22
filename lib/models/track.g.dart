// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TrackAdapter extends TypeAdapter<Track> {
  @override
  final int typeId = 0;

  @override
  Track read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Track(
      id: fields[0] as String,
      cloudPath: fields[1] as String,
      localCachePath: fields[2] as String?,
      title: fields[3] as String?,
      artist: fields[4] as String?,
      duration: fields[5] as Duration,
      fileSize: fields[6] as int?,
      lastAccessed: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Track obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.cloudPath)
      ..writeByte(2)
      ..write(obj.localCachePath)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.artist)
      ..writeByte(5)
      ..write(obj.duration)
      ..writeByte(6)
      ..write(obj.fileSize)
      ..writeByte(7)
      ..write(obj.lastAccessed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
