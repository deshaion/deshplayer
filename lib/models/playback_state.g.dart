// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playback_state.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlaybackStateAdapter extends TypeAdapter<PlaybackState> {
  @override
  final int typeId = 2;

  @override
  PlaybackState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlaybackState(
      playlistId: fields[0] as String,
      currentTrackId: fields[1] as String?,
      position: fields[2] as Duration,
      accumulatedTime:
          fields[3] == null ? Duration.zero : fields[3] as Duration,
      statsRecorded: fields[4] == null ? false : fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, PlaybackState obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.playlistId)
      ..writeByte(1)
      ..write(obj.currentTrackId)
      ..writeByte(2)
      ..write(obj.position)
      ..writeByte(3)
      ..write(obj.accumulatedTime)
      ..writeByte(4)
      ..write(obj.statsRecorded);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
