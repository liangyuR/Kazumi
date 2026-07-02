import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/source/source_binding.dart';

part 'download_module.g.dart';

@HiveType(typeId: 7)
class DownloadRecord {
  @HiveField(0)
  int bangumiId;

  @HiveField(1)
  String bangumiName;

  @HiveField(2)
  String bangumiCover;

  @HiveField(3)
  String pluginName;

  @HiveField(4)
  Map<int, DownloadEpisode> episodes;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6, defaultValue: '')
  String sourceBindingKey;

  @HiveField(7, defaultValue: '')
  String sourceTitle;

  @HiveField(8, defaultValue: '')
  String sourceUrl;

  @HiveField(9, defaultValue: 0)
  int sourceConfirmedAt;

  @HiveField(10, defaultValue: SourceConfirmationKind.manual)
  String sourceConfirmationKind;

  String get key => scopedKey(
        pluginName,
        bangumiId,
        sourceBindingKey: sourceBindingKey,
      );

  String get legacyKey => scopedKey(pluginName, bangumiId);

  DownloadRecord(
    this.bangumiId,
    this.bangumiName,
    this.bangumiCover,
    this.pluginName,
    this.episodes,
    this.createdAt, {
    this.sourceBindingKey = '',
    this.sourceTitle = '',
    this.sourceUrl = '',
    this.sourceConfirmedAt = 0,
    this.sourceConfirmationKind = SourceConfirmationKind.manual,
  });

  static String scopedKey(
    String pluginName,
    int bangumiId, {
    String sourceBindingKey = '',
  }) {
    final base = '${pluginName}_$bangumiId';
    final sourceKey = sourceBindingKey.trim();
    if (sourceKey.isEmpty) {
      return base;
    }
    return '$base::source:${Uri.encodeComponent(sourceKey)}';
  }
}

const int _maxDownloadKey = 0x7fffffff;

/// 新下载记录的 Hive map key。
///
/// `DownloadRecord.episodes` 的 key 仅作为本地下载任务/目录/缓存定位 key。
/// 新记录必须由 stableId 派生，避免同一个 ordinal 的不同集互相覆盖。
int downloadKeyForEpisodeIdentity(
  DownloadRecord record, {
  required int road,
  required String roadId,
  required String stableId,
}) {
  final id = stableId.trim();
  if (id.isEmpty) {
    throw ArgumentError.value(
      stableId,
      'stableId',
      'Download key requires a stable episode identity.',
    );
  }
  var key = stableDownloadKey(_stableDownloadScopedId(
    id,
    sourceBindingKey: record.sourceBindingKey,
    road: road,
    roadId: roadId,
  ));
  while (true) {
    final existing = record.episodes[key];
    if (existing == null ||
        (existing.stableId == id &&
            _sameRoadIdentity(existing, road, roadId))) {
      return key;
    }
    key = key == _maxDownloadKey ? 1 : key + 1;
  }
}

String _stableDownloadScopedId(
  String stableId, {
  required String sourceBindingKey,
  required int road,
  required String roadId,
}) {
  final scopedRoad = roadId.trim().isNotEmpty ? roadId.trim() : '$road';
  final sourceKey = sourceBindingKey.trim();
  if (sourceKey.isEmpty) {
    return '$scopedRoad\n$stableId';
  }
  return '$sourceKey\n$scopedRoad\n$stableId';
}

int stableDownloadKey(String stableId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in stableId.trim().codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & _maxDownloadKey;
  }
  return hash == 0 ? 1 : hash;
}

MapEntry<int, DownloadEpisode>? downloadEpisodeEntryByStableId(
  DownloadRecord record,
  String stableId, {
  required int road,
  String roadId = '',
}) {
  final id = stableId.trim();
  if (id.isEmpty) {
    return null;
  }
  for (final entry in record.episodes.entries) {
    if (entry.value.stableId == id &&
        _sameRoadIdentity(entry.value, road, roadId)) {
      return entry;
    }
  }
  return null;
}

DownloadEpisode? downloadedEpisodeForHistoryPlayback(
  List<DownloadEpisode> episodes, {
  required String stableId,
  int? preferredRoad,
  String preferredRoadId = '',
}) {
  final id = stableId.trim();
  if (id.isEmpty) {
    return null;
  }
  for (final episode in episodes) {
    if (episode.stableId != id) {
      continue;
    }
    final scopedRoadId = preferredRoadId.trim();
    if (scopedRoadId.isNotEmpty) {
      if (episode.roadId == scopedRoadId) {
        return episode;
      }
      continue;
    }
    if (preferredRoad != null) {
      if (episode.road == preferredRoad) {
        return episode;
      }
      continue;
    }
  }
  if (preferredRoadId.trim().isNotEmpty || preferredRoad != null) {
    return null;
  }
  final stableMatches =
      episodes.where((episode) => episode.stableId == id).toList();
  return stableMatches.length == 1 ? stableMatches.single : null;
}

int compareDownloadEpisodeOrder(DownloadEpisode a, DownloadEpisode b) {
  final aOrdinal = a.ordinal;
  final bOrdinal = b.ordinal;
  if (aOrdinal != null && bOrdinal != null) {
    final compare = aOrdinal.compareTo(bOrdinal);
    if (compare != 0) {
      return compare;
    }
  } else if (aOrdinal != null) {
    return -1;
  } else if (bOrdinal != null) {
    return 1;
  }
  final nameCompare = a.episodeName.compareTo(b.episodeName);
  if (nameCompare != 0) {
    return nameCompare;
  }
  return a.stableId.compareTo(b.stableId);
}

String downloadEpisodeDisplayName(
  DownloadEpisode episode, {
  int? fallbackKey,
}) {
  if (episode.episodeName.isNotEmpty) {
    return episode.episodeName;
  }
  final ordinal = episode.ordinal;
  if (ordinal != null && ordinal > 0) {
    return '第$ordinal集';
  }
  if (fallbackKey != null) {
    return '下载项$fallbackKey';
  }
  return '未命名剧集';
}

bool _sameRoadIdentity(DownloadEpisode episode, int road, String roadId) {
  final id = roadId.trim();
  if (id.isNotEmpty) {
    return episode.roadId == id;
  }
  return episode.road == road;
}

@HiveType(typeId: 8)
class DownloadEpisode {
  /// 订阅规则产出的集序数，仅用于排序、展示和弹幕集号；不参与身份匹配。
  @HiveField(0)
  int? ordinal;

  @HiveField(1)
  String episodeName;

  @HiveField(2)
  int road;

  /// 0=pending 1=resolving 2=downloading 3=completed 4=failed 5=paused
  @HiveField(3)
  int status;

  @HiveField(4)
  double progressPercent;

  @HiveField(5)
  int totalSegments;

  @HiveField(6)
  int downloadedSegments;

  @HiveField(7)
  String localM3u8Path;

  @HiveField(8)
  String downloadDirectory;

  @HiveField(9)
  String networkM3u8Url;

  @HiveField(10)
  DateTime? completedAt;

  @HiveField(11, defaultValue: '')
  String errorMessage;

  @HiveField(12, defaultValue: 0)
  int totalBytes;

  @HiveField(13, defaultValue: '')
  String episodePageUrl;

  /// 缓存的弹幕数据 (JSON 字符串格式)
  @HiveField(14, defaultValue: '')
  String danmakuData;

  /// DanDanPlay 番剧 ID (用于弹幕查询缓存)
  @HiveField(15, defaultValue: 0)
  int danDanBangumiID;

  /// 订阅规则产出的稳定集身份；用于下载查重与在线/离线身份互通。
  @HiveField(16, defaultValue: '')
  String stableId;

  /// 订阅规则产出的稳定线路身份；用于下载查重与在线/离线身份互通。
  @HiveField(17, defaultValue: '')
  String roadId;

  DownloadEpisode(
    this.ordinal,
    this.episodeName,
    this.road,
    this.status,
    this.progressPercent,
    this.totalSegments,
    this.downloadedSegments,
    this.localM3u8Path,
    this.downloadDirectory,
    this.networkM3u8Url,
    this.completedAt,
    this.errorMessage,
    this.totalBytes,
    this.episodePageUrl, {
    this.danmakuData = '',
    this.danDanBangumiID = 0,
    this.stableId = '',
    this.roadId = '',
  });
}

class DownloadStatus {
  static const int pending = 0;
  static const int resolving = 1;
  static const int downloading = 2;
  static const int completed = 3;
  static const int failed = 4;
  static const int paused = 5;
}
