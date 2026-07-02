class PlaybackInitParams {
  final String videoUrl;
  final int offset;
  final bool isLocalPlayback;
  final int bangumiId;
  final String pluginName;
  final int episode;
  final int danmakuEpisodeNumber;
  final String pageUrl;
  final String stableId;
  final String roadId;
  final String sourceBindingKey;

  /// 集数排序号，语义同 EpisodeRef.sortNumber（优先规则 ordinal，缺失时只作展示降级）。
  final int? sortNumber;
  final Map<String, String> httpHeaders;
  final bool adBlockerEnabled;
  final String episodeTitle;
  final String referer;
  final int currentRoad;
  final int? downloadRoad;
  final String? coverUrl;
  final String? bangumiName;

  const PlaybackInitParams({
    required this.videoUrl,
    required this.offset,
    required this.isLocalPlayback,
    required this.bangumiId,
    required this.pluginName,
    required this.episode,
    required this.danmakuEpisodeNumber,
    required this.httpHeaders,
    required this.adBlockerEnabled,
    required this.episodeTitle,
    required this.referer,
    required this.currentRoad,
    this.downloadRoad,
    this.pageUrl = '',
    this.stableId = '',
    this.roadId = '',
    this.sourceBindingKey = '',
    this.sortNumber,
    this.coverUrl,
    this.bangumiName,
  });
}

class SyncPlayEpisodeIdentity {
  const SyncPlayEpisodeIdentity({
    required this.bangumiId,
    this.road,
    this.roadId,
    this.episode,
    this.stableId = '',
  });

  final int bangumiId;
  final int? road;
  final String? roadId;
  final int? episode;
  final String stableId;

  bool get hasStableId => stableId.isNotEmpty;

  bool targetsStableEpisode({
    required String currentStableId,
    required String currentRoadId,
    required int currentRoad,
  }) {
    if (!hasStableId) {
      return false;
    }
    final scopedRoadId = roadId?.trim() ?? '';
    if (scopedRoadId.isNotEmpty) {
      return stableId == currentStableId && scopedRoadId == currentRoadId;
    }
    return stableId == currentStableId && (road ?? currentRoad) == currentRoad;
  }

  static String fileNameFor({
    required int bangumiId,
    required int road,
    required int episode,
    required String stableId,
    String roadId = '',
  }) {
    final id = stableId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        stableId,
        'stableId',
        'SyncPlay file names require a stable episode identity.',
      );
    }
    final scopedRoadId = roadId.trim();
    if (scopedRoadId.isNotEmpty) {
      return 'kazumi-v3:$bangumiId:${Uri.encodeComponent(scopedRoadId)}:${Uri.encodeComponent(id)}';
    }
    return 'kazumi-v2:$bangumiId:$road:${Uri.encodeComponent(id)}';
  }

  static SyncPlayEpisodeIdentity? parse(String name) {
    final roadIdMatch = RegExp(r'^kazumi-v3:(\d+):(.+):(.+)$').firstMatch(name);
    if (roadIdMatch != null) {
      try {
        return SyncPlayEpisodeIdentity(
          bangumiId: int.parse(roadIdMatch.group(1)!),
          roadId: Uri.decodeComponent(roadIdMatch.group(2)!),
          stableId: Uri.decodeComponent(roadIdMatch.group(3)!),
        );
      } catch (_) {
        return null;
      }
    }

    final stableMatch =
        RegExp(r'^kazumi-v2:(\d+):(-?\d+):(.+)$').firstMatch(name);
    if (stableMatch != null) {
      try {
        return SyncPlayEpisodeIdentity(
          bangumiId: int.parse(stableMatch.group(1)!),
          road: int.parse(stableMatch.group(2)!),
          stableId: Uri.decodeComponent(stableMatch.group(3)!),
        );
      } catch (_) {
        return null;
      }
    }

    final legacyMatch = RegExp(r'^(\d+)\[(\d+)\]$').firstMatch(name);
    if (legacyMatch == null) {
      return null;
    }
    try {
      return SyncPlayEpisodeIdentity(
        bangumiId: int.parse(legacyMatch.group(1)!),
        episode: int.parse(legacyMatch.group(2)!),
      );
    } catch (_) {
      return null;
    }
  }
}

enum DanmakuDestination {
  chatRoom,
  remoteDanmaku,
}

class SyncPlayChatMessage {
  final String username;
  final String message;
  final bool fromRemote;
  final DateTime time;

  SyncPlayChatMessage({
    required this.username,
    required this.message,
    this.fromRemote = true,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}
