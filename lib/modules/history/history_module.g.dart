// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_module.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HistoryAdapter extends TypeAdapter<History> {
  @override
  final typeId = 1;

  @override
  History read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return History(
      fields[3] as BangumiItem,
      (fields[1] as num).toInt(),
      fields[2] as String,
      fields[4] as DateTime,
      fields[5] as String,
      fields[6] == null ? '' : fields[6] as String,
      entryKind: fields[7] == null ? 'online' : fields[7] as String,
      episodePageUrl: fields[8] == null ? '' : fields[8] as String,
      stableId: fields[9] == null ? '' : fields[9] as String,
      roadId: fields[10] == null ? '' : fields[10] as String,
      sourceBindingKey: fields[11] == null ? '' : fields[11] as String,
      sourceTitle: fields[12] == null ? '' : fields[12] as String,
      sourceUrl: fields[13] == null ? '' : fields[13] as String,
      sourceConfirmedAt: fields[14] == null ? 0 : (fields[14] as num).toInt(),
      sourceConfirmationKind:
          fields[15] == null ? 'manual' : fields[15] as String,
    )..progresses = (fields[0] as Map).cast<String, Progress>();
  }

  @override
  void write(BinaryWriter writer, History obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.progresses)
      ..writeByte(1)
      ..write(obj.lastWatchEpisode)
      ..writeByte(2)
      ..write(obj.adapterName)
      ..writeByte(3)
      ..write(obj.bangumiItem)
      ..writeByte(4)
      ..write(obj.lastWatchTime)
      ..writeByte(5)
      ..write(obj.lastSrc)
      ..writeByte(6)
      ..write(obj.lastWatchEpisodeName)
      ..writeByte(7)
      ..write(obj.entryKind)
      ..writeByte(8)
      ..write(obj.episodePageUrl)
      ..writeByte(9)
      ..write(obj.stableId)
      ..writeByte(10)
      ..write(obj.roadId)
      ..writeByte(11)
      ..write(obj.sourceBindingKey)
      ..writeByte(12)
      ..write(obj.sourceTitle)
      ..writeByte(13)
      ..write(obj.sourceUrl)
      ..writeByte(14)
      ..write(obj.sourceConfirmedAt)
      ..writeByte(15)
      ..write(obj.sourceConfirmationKind);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ProgressAdapter extends TypeAdapter<Progress> {
  @override
  final typeId = 2;

  @override
  Progress read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Progress(
      (fields[0] as num).toInt(),
      (fields[1] as num).toInt(),
      (fields[2] as num).toInt(),
      updatedAtMs: fields[3] == null ? 0 : (fields[3] as num).toInt(),
      episodePageUrl: fields[4] == null ? '' : fields[4] as String,
      stableId: fields[5] == null ? '' : fields[5] as String,
      roadId: fields[6] == null ? '' : fields[6] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Progress obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.episode)
      ..writeByte(1)
      ..write(obj.road)
      ..writeByte(2)
      ..write(obj._progressInMilli)
      ..writeByte(3)
      ..write(obj.updatedAtMs)
      ..writeByte(4)
      ..write(obj.episodePageUrl)
      ..writeByte(5)
      ..write(obj.stableId)
      ..writeByte(6)
      ..write(obj.roadId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
