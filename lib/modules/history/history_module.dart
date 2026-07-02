import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/source/source_binding.dart';

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
    this.sourceBindingKey = '',
    this.sourceTitle = '',
    this.sourceUrl = '',
    this.sourceConfirmedAt = 0,
    this.sourceConfirmationKind = SourceConfirmationKind.manual,
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

  /// 用户确认过的源站资源绑定。它定义 [stableId] / [roadId] 的上层作用域。
  final String sourceBindingKey;
  final String sourceTitle;
  final String sourceUrl;
  final int sourceConfirmedAt;
  final String sourceConfirmationKind;

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
    SourceBinding? sourceBinding,
    String sourceBindingKey = '',
    String sourceTitle = '',
    String sourceUrl = '',
    int sourceConfirmedAt = 0,
    String sourceConfirmationKind = SourceConfirmationKind.manual,
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
      sourceBindingKey: sourceBinding?.sourceBindingKey ?? sourceBindingKey,
      sourceTitle: sourceBinding?.sourceTitle ?? sourceTitle,
      sourceUrl: sourceBinding?.sourceUrl ?? sourceUrl,
      sourceConfirmedAt: sourceBinding?.confirmedAt ?? sourceConfirmedAt,
      sourceConfirmationKind: SourceConfirmationKind.normalize(
        sourceBinding?.confirmationKind ?? sourceConfirmationKind,
      ),
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
    SourceBinding? sourceBinding,
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
      sourceBindingKey: sourceBinding?.sourceBindingKey ?? '',
      sourceTitle: sourceBinding?.sourceTitle ?? '',
      sourceUrl: sourceBinding?.sourceUrl ?? '',
      sourceConfirmedAt: sourceBinding?.confirmedAt ?? 0,
      sourceConfirmationKind: SourceConfirmationKind.normalize(
        sourceBinding?.confirmationKind ?? SourceConfirmationKind.manual,
      ),
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

  @HiveField(11, defaultValue: '')
  String sourceBindingKey;

  @HiveField(12, defaultValue: '')
  String sourceTitle;

  @HiveField(13, defaultValue: '')
  String sourceUrl;

  @HiveField(14, defaultValue: 0)
  int sourceConfirmedAt;

  @HiveField(15, defaultValue: SourceConfirmationKind.manual)
  String sourceConfirmationKind;

  String get key => scopedKey(
        adapterName,
        bangumiItem,
        entryKind,
        sourceBindingKey: sourceBindingKey,
      );

  String get legacyKey => scopedKey(adapterName, bangumiItem, entryKind);

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
    this.sourceBindingKey = '',
    this.sourceTitle = '',
    this.sourceUrl = '',
    this.sourceConfirmedAt = 0,
    this.sourceConfirmationKind = SourceConfirmationKind.manual,
  });

  static String baseKey(String n, BangumiItem s) => n + s.id.toString();

  static String scopedKey(
    String n,
    BangumiItem s,
    String entryKind, {
    String sourceBindingKey = '',
  }) {
    final base = '${baseKey(n, s)}::${HistoryEntryKind.normalize(entryKind)}';
    final sourceKey = sourceBindingKey.trim();
    if (sourceKey.isEmpty) {
      return base;
    }
    return '$base::source:${Uri.encodeComponent(sourceKey)}';
  }

  static String getKey(
    String n,
    BangumiItem s, {
    String entryKind = HistoryEntryKind.online,
    String sourceBindingKey = '',
  }) {
    return scopedKey(
      n,
      s,
      entryKind,
      sourceBindingKey: sourceBindingKey,
    );
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
