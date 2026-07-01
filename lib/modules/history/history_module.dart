import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';

part 'history_module.g.dart';

class HistoryEntryKind {
  static const String online = 'online';
  static const String offline = 'offline';

  static String normalize(String value) {
    return value == offline ? offline : online;
  }

  HistoryEntryKind._();
}

class PlaybackHistoryIdentity {
  const PlaybackHistoryIdentity({
    required this.bangumiItem,
    required this.pluginName,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.road,
    required this.entryKind,
    this.onlineBangumiSrc = '',
    this.episodePageUrl = '',
    this.stableId = '',
    this.roadId = '',
  });

  final BangumiItem bangumiItem;
  final String pluginName;
  final int episodeNumber;
  final String episodeTitle;
  final int road;
  final String entryKind;
  final String onlineBangumiSrc;
  final String episodePageUrl;

  /// 订阅规则产出的稳定身份（与域名/顺序无关），历史进度匹配主键。
  final String stableId;

  /// 订阅规则产出的稳定线路身份，用于消除 roadList 数组下标重排带来的歧义。
  final String roadId;

  bool get canRecord =>
      pluginName.isNotEmpty && episodeNumber > 0 && stableId.trim().isNotEmpty;

  factory PlaybackHistoryIdentity.online({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required String episodeTitle,
    required int road,
    required String onlineBangumiSrc,
    required String episodePageUrl,
    String stableId = '',
    String roadId = '',
  }) {
    return PlaybackHistoryIdentity(
      bangumiItem: bangumiItem,
      pluginName: pluginName,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      road: road,
      entryKind: HistoryEntryKind.online,
      onlineBangumiSrc: onlineBangumiSrc,
      episodePageUrl: episodePageUrl,
      stableId: stableId,
      roadId: roadId,
    );
  }

  factory PlaybackHistoryIdentity.offline({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required String episodeTitle,
    required int road,
    required String episodePageUrl,
    String stableId = '',
    String roadId = '',
  }) {
    return PlaybackHistoryIdentity(
      bangumiItem: bangumiItem,
      pluginName: pluginName,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      road: road,
      entryKind: HistoryEntryKind.offline,
      episodePageUrl: episodePageUrl,
      stableId: stableId,
      roadId: roadId,
    );
  }
}

@HiveType(typeId: 1)
class History {
  @HiveField(0)
  Map<String, Progress> progresses = {};

  @HiveField(1)
  int lastWatchEpisode;

  @HiveField(2)
  String adapterName;

  @HiveField(3)
  BangumiItem bangumiItem;

  @HiveField(4)
  DateTime lastWatchTime;

  @HiveField(5)
  String lastSrc;

  @HiveField(6, defaultValue: '')
  String lastWatchEpisodeName;

  @HiveField(7, defaultValue: HistoryEntryKind.online)
  String entryKind;

  @HiveField(8, defaultValue: '')
  String episodePageUrl;

  @HiveField(9, defaultValue: '')
  String stableId;

  @HiveField(10, defaultValue: '')
  String roadId;

  String get key => scopedKey(adapterName, bangumiItem, entryKind);

  History(
    this.bangumiItem,
    this.lastWatchEpisode,
    this.adapterName,
    this.lastWatchTime,
    this.lastSrc,
    this.lastWatchEpisodeName, {
    this.entryKind = HistoryEntryKind.online,
    this.episodePageUrl = '',
    this.stableId = '',
    this.roadId = '',
  });

  static String baseKey(String n, BangumiItem s) => n + s.id.toString();

  static String scopedKey(String n, BangumiItem s, String entryKind) {
    return '${baseKey(n, s)}::${HistoryEntryKind.normalize(entryKind)}';
  }

  static String getKey(
    String n,
    BangumiItem s, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return scopedKey(n, s, entryKind);
  }

  @override
  String toString() {
    return 'Adapter: $adapterName, anime: ${bangumiItem.name}';
  }
}

String historyProgressKey({
  required String stableId,
  required int episode,
  int? road,
  String roadId = '',
}) {
  final id = stableId.trim();
  if (id.isEmpty) {
    throw ArgumentError.value(
      stableId,
      'stableId',
      'History progress key requires a stable episode identity.',
    );
  }
  final scopedRoadId = roadId.trim();
  if (scopedRoadId.isNotEmpty) {
    return 'roadId:$scopedRoadId\nstableId:$id';
  }
  if (road != null) {
    return 'road:$road\nstableId:$id';
  }
  return 'stableId:$id';
}

@HiveType(typeId: 2)
class Progress {
  @HiveField(0)
  int episode;

  @HiveField(1)
  int road;

  @HiveField(2)
  int _progressInMilli;

  @HiveField(3, defaultValue: 0)
  int updatedAtMs;

  @HiveField(4, defaultValue: '')
  String episodePageUrl;

  /// 订阅规则产出的稳定身份（与域名/顺序无关），作为历史进度匹配主键。
  @HiveField(5, defaultValue: '')
  String stableId;

  /// 订阅规则产出的稳定线路身份。持久匹配优先使用 [stableId] + [roadId]。
  @HiveField(6, defaultValue: '')
  String roadId;

  Duration get progress => Duration(milliseconds: _progressInMilli);

  set progress(Duration d) => _progressInMilli = d.inMilliseconds;

  Progress(
    this.episode,
    this.road,
    this._progressInMilli, {
    this.updatedAtMs = 0,
    this.episodePageUrl = '',
    this.stableId = '',
    this.roadId = '',
  });

  int effectiveUpdatedAtMs(DateTime fallback) {
    return updatedAtMs > 0 ? updatedAtMs : fallback.millisecondsSinceEpoch;
  }

  @override
  String toString() {
    return 'Episode ${episode.toString()}, progress $progress';
  }
}
