import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/source/source_binding.dart';
import 'package:kazumi/services/sync/history_sync_service.dart';
import 'package:kazumi/services/logging/logger.dart';

typedef HistoryProgressSyncAppender = Future<void> Function({
  required History history,
  required int episode,
  required int road,
  required int progressMs,
  required int updatedAt,
  required String episodePageUrl,
  required String stableId,
  required String roadId,
});

typedef HistoryDeleteSyncAppender = Future<void> Function(History history);

typedef HistoryClearSyncAppender = Future<void> Function();

/// 历史记录数据访问接口
///
/// 提供观看历史相关的数据访问抽象
abstract class IHistoryRepository {
  /// 获取所有历史记录（按时间倒序）
  List<History> getAllHistories();

  /// 获取特定番剧的历史记录
  ///
  /// [adapterName] 适配器名称
  /// [bangumiItem] 番剧信息
  /// 返回历史记录，不存在返回null
  History? getHistory(
    String adapterName,
    BangumiItem bangumiItem, {
    String entryKind = HistoryEntryKind.online,
    String sourceBindingKey = '',
  });

  /// 更新或创建历史记录
  ///
  /// [identity] 播放历史身份
  /// [progress] 观看进度
  Future<void> updateHistory({
    required PlaybackHistoryIdentity identity,
    required Duration progress,
  });

  /// 获取上次观看的进度
  ///
  /// [bangumiItem] 番剧信息
  /// [adapterName] 适配器名称
  /// 返回观看进度，不存在返回null
  Progress? getLastWatchingProgress(
    BangumiItem bangumiItem,
    String adapterName, {
    String entryKind = HistoryEntryKind.online,
    String sourceBindingKey = '',
  });

  /// 查找特定集数的观看进度
  ///
  /// [bangumiItem] 番剧信息
  /// [adapterName] 适配器名称
  /// [episode] 集数
  /// 返回观看进度，不存在返回null
  Progress? findProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    int? road,
    String entryKind = HistoryEntryKind.online,
    String stableId = '',
    String roadId = '',
    String sourceBindingKey = '',
  });

  /// 删除历史记录
  ///
  /// [history] 要删除的历史记录
  Future<void> deleteHistory(History history);

  /// 清空特定集数的观看进度
  ///
  /// [bangumiItem] 番剧信息
  /// [adapterName] 适配器名称
  /// [episode] 集数
  Future<void> clearProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    int? road,
    String entryKind = HistoryEntryKind.online,
    String stableId = '',
    String roadId = '',
    String sourceBindingKey = '',
  });

  /// 清空所有历史记录
  Future<void> clearAllHistories();

  /// 获取隐私模式设置
  bool getPrivateMode();
}

/// 历史记录数据访问实现类
///
/// 基于Hive实现的历史记录数据访问层
class HistoryRepository implements IHistoryRepository {
  HistoryRepository({
    Box<History>? historiesBox,
    bool Function()? privateModeReader,
    HistoryProgressSyncAppender? progressSyncAppender,
    HistoryDeleteSyncAppender? deleteSyncAppender,
    HistoryClearSyncAppender? clearSyncAppender,
  })  : _historiesBox = historiesBox ?? GStorage.histories,
        _privateModeReader = privateModeReader ??
            (() => GStorage.getSetting(SettingsKeys.privateMode)),
        _progressSyncAppender = progressSyncAppender ?? _appendProgressSync,
        _deleteSyncAppender = deleteSyncAppender ?? _appendDeleteSync,
        _clearSyncAppender = clearSyncAppender ?? _appendClearSync;

  final Box<History> _historiesBox;
  final bool Function() _privateModeReader;
  final HistoryProgressSyncAppender _progressSyncAppender;
  final HistoryDeleteSyncAppender _deleteSyncAppender;
  final HistoryClearSyncAppender _clearSyncAppender;

  static Future<void> _appendProgressSync({
    required History history,
    required int episode,
    required int road,
    required int progressMs,
    required int updatedAt,
    required String episodePageUrl,
    required String stableId,
    required String roadId,
  }) async {
    final historySyncService = HistorySyncService();
    await historySyncService.appendSafely(
      () => historySyncService.appendUpsertProgress(
        history: history,
        episode: episode,
        road: road,
        progressMs: progressMs,
        updatedAt: updatedAt,
        episodePageUrl: episodePageUrl,
        stableId: stableId,
        roadId: roadId,
      ),
    );
  }

  static Future<void> _appendDeleteSync(History history) async {
    final historySyncService = HistorySyncService();
    await historySyncService.appendSafely(
      () => historySyncService.appendDeleteHistory(history),
    );
  }

  static Future<void> _appendClearSync() async {
    final historySyncService = HistorySyncService();
    await historySyncService.appendSafely(
      () => historySyncService.appendClearAll(),
    );
  }

  @override
  List<History> getAllHistories() {
    try {
      final byKey = <String, History>{};
      for (final history in _historiesBox.values) {
        history.entryKind = HistoryEntryKind.normalize(history.entryKind);
        history.sourceConfirmationKind =
            SourceConfirmationKind.normalize(history.sourceConfirmationKind);
        if (history.stableId.trim().isEmpty) {
          continue;
        }
        final existing = byKey[history.key];
        if (existing == null ||
            existing.lastWatchTime.isBefore(history.lastWatchTime)) {
          byKey[history.key] = history;
        }
      }
      var histories = byKey.values.toList();
      histories.sort(
        (a, b) =>
            b.lastWatchTime.millisecondsSinceEpoch -
            a.lastWatchTime.millisecondsSinceEpoch,
      );
      return histories;
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: get all histories failed',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  @override
  History? getHistory(
    String adapterName,
    BangumiItem bangumiItem, {
    String entryKind = HistoryEntryKind.online,
    String sourceBindingKey = '',
  }) {
    try {
      return _findHistory(
        adapterName,
        bangumiItem,
        entryKind,
        sourceBindingKey: sourceBindingKey,
      );
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: get history failed. bangumi=${bangumiItem.name}',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<void> updateHistory({
    required PlaybackHistoryIdentity identity,
    required Duration progress,
  }) async {
    try {
      if (!identity.canRecord) {
        return;
      }
      // 检查隐私模式
      if (getPrivateMode()) {
        return;
      }

      final episode = identity.episodeNumber;
      final adapterName = identity.pluginName;
      final bangumiItem = identity.bangumiItem;

      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;

      // 获取或创建历史记录。带 source binding 的确认写入可以把旧 legacy
      // bucket 提升到 scoped key，但不会按 URL 批量猜测迁移。
      var history = _findHistory(
        adapterName,
        bangumiItem,
        identity.entryKind,
        sourceBindingKey: identity.sourceBindingKey,
      );
      String? promotedLegacyKey;
      History? promotedLegacySnapshot;
      if (history == null && identity.sourceBindingKey.trim().isNotEmpty) {
        final legacyHistory = _findHistory(
          adapterName,
          bangumiItem,
          identity.entryKind,
        );
        if (legacyHistory != null) {
          promotedLegacyKey = legacyHistory.key;
          promotedLegacySnapshot = _snapshotHistory(legacyHistory);
          history = legacyHistory;
        }
      }
      history ??= History(
        bangumiItem,
        episode,
        adapterName,
        now,
        identity.onlineBangumiSrc,
        identity.episodeTitle,
        entryKind: identity.entryKind,
        episodePageUrl: identity.episodePageUrl,
        stableId: identity.stableId,
        roadId: identity.roadId,
        sourceBindingKey: identity.sourceBindingKey,
        sourceTitle: identity.sourceTitle,
        sourceUrl: identity.sourceUrl,
        sourceConfirmedAt: identity.sourceConfirmedAt,
        sourceConfirmationKind: identity.sourceConfirmationKind,
      );

      // 更新历史记录
      history.lastWatchEpisode = episode;
      history.lastWatchTime = now;
      history.entryKind = HistoryEntryKind.normalize(identity.entryKind);
      if (identity.onlineBangumiSrc.isNotEmpty) {
        history.lastSrc = identity.onlineBangumiSrc;
      }
      if (identity.episodeTitle.isNotEmpty) {
        history.lastWatchEpisodeName = identity.episodeTitle;
      }
      history.episodePageUrl = identity.episodePageUrl;
      history.stableId = identity.stableId;
      history.roadId = identity.roadId;
      if (identity.sourceBindingKey.trim().isNotEmpty) {
        history.sourceBindingKey = identity.sourceBindingKey;
        if (identity.sourceTitle.isNotEmpty) {
          history.sourceTitle = identity.sourceTitle;
        }
        if (identity.sourceUrl.isNotEmpty) {
          history.sourceUrl = identity.sourceUrl;
        }
        if (identity.sourceConfirmedAt > 0) {
          history.sourceConfirmedAt = identity.sourceConfirmedAt;
        }
        history.sourceConfirmationKind =
            SourceConfirmationKind.normalize(identity.sourceConfirmationKind);
      }

      // 更新观看进度
      final progressMatch = _HistoryEpisodeMatcher.find(
        history,
        episode: episode,
        road: identity.road,
        roadId: identity.roadId,
        stableId: identity.stableId,
        allowStableIdOnlyFallback: false,
      );
      final progressBucket = progressMatch?.bucket ??
          _HistoryEpisodeMatcher.bucketForNewProgress(
            history,
            episode: episode,
            road: identity.road,
            roadId: identity.roadId,
            stableId: identity.stableId,
          );
      final prog = progressMatch?.progress ??
          Progress(
            episode,
            identity.road,
            progress.inMilliseconds,
            updatedAtMs: nowMs,
            episodePageUrl: identity.episodePageUrl,
            stableId: identity.stableId,
            roadId: identity.roadId,
          );
      prog.episode = episode;
      prog.road = identity.road;
      prog.progress = progress;
      prog.updatedAtMs = nowMs;
      prog.episodePageUrl = identity.episodePageUrl;
      prog.stableId = identity.stableId;
      prog.roadId = identity.roadId;
      history.progresses[progressBucket] = prog;

      // 保存到存储
      await _historiesBox.put(history.key, history);
      if (promotedLegacyKey != null && promotedLegacyKey != history.key) {
        await _historiesBox.delete(promotedLegacyKey);
        if (promotedLegacySnapshot != null) {
          await _deleteSyncAppender(promotedLegacySnapshot);
        }
      }
      await _progressSyncAppender(
        history: history,
        episode: episode,
        road: identity.road,
        progressMs: progress.inMilliseconds,
        updatedAt: nowMs,
        episodePageUrl: prog.episodePageUrl,
        stableId: prog.stableId,
        roadId: prog.roadId,
      );
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: update history failed. bangumi=${identity.bangumiItem.name}, episode=${identity.episodeNumber}',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Progress? getLastWatchingProgress(
    BangumiItem bangumiItem,
    String adapterName, {
    String entryKind = HistoryEntryKind.online,
    String sourceBindingKey = '',
  }) {
    try {
      final history = _findHistory(
        adapterName,
        bangumiItem,
        entryKind,
        sourceBindingKey: sourceBindingKey,
      );
      if (history == null) {
        return null;
      }
      final progressMatch = _HistoryEpisodeMatcher.find(
        history,
        episode: history.lastWatchEpisode,
        roadId: history.roadId,
        stableId: history.stableId,
      );
      return progressMatch?.progress;
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: get last watching progress failed. bangumi=${bangumiItem.name}',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Progress? findProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    int? road,
    String entryKind = HistoryEntryKind.online,
    String stableId = '',
    String roadId = '',
    String sourceBindingKey = '',
  }) {
    try {
      final history = _findHistory(
        adapterName,
        bangumiItem,
        entryKind,
        sourceBindingKey: sourceBindingKey,
      );
      if (history == null) {
        return null;
      }
      final progressMatch = _HistoryEpisodeMatcher.find(
        history,
        episode: episode,
        road: road,
        roadId: roadId,
        stableId: stableId,
        allowStableIdOnlyFallback: road == null,
      );
      return progressMatch?.progress;
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: find progress failed. bangumi=${bangumiItem.name}, episode=$episode',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<void> deleteHistory(History history) async {
    try {
      await _historiesBox.delete(history.key);
      await _deleteSyncAppender(history);
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: delete history failed. bangumi=${history.bangumiItem.name}',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> clearProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    int? road,
    String entryKind = HistoryEntryKind.online,
    String stableId = '',
    String roadId = '',
    String sourceBindingKey = '',
  }) async {
    try {
      final history = _findHistory(
        adapterName,
        bangumiItem,
        entryKind,
        sourceBindingKey: sourceBindingKey,
      );
      final progressMatch = history == null
          ? null
          : _HistoryEpisodeMatcher.find(
              history,
              episode: episode,
              road: road,
              roadId: roadId,
              stableId: stableId,
              allowStableIdOnlyFallback: road == null,
            );
      if (history != null && progressMatch != null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        progressMatch.progress.progress = Duration.zero;
        progressMatch.progress.updatedAtMs = nowMs;
        history.progresses[progressMatch.bucket] = progressMatch.progress;
        await _historiesBox.put(history.key, history);
        await _progressSyncAppender(
          history: history,
          episode: progressMatch.progress.episode,
          road: progressMatch.progress.road,
          progressMs: 0,
          updatedAt: nowMs,
          episodePageUrl: progressMatch.progress.episodePageUrl,
          stableId: progressMatch.progress.stableId,
          roadId: progressMatch.progress.roadId,
        );
      }
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: clear progress failed. bangumi=${bangumiItem.name}, episode=$episode',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> clearAllHistories() async {
    try {
      await _historiesBox.clear();
      await _clearSyncAppender();
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: clear all histories failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  bool getPrivateMode() {
    try {
      return _privateModeReader();
    } catch (e, stackTrace) {
      KazumiLogger().e(
        'GStorage: get private mode setting failed, using default false',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  History? _findHistory(
      String adapterName, BangumiItem bangumiItem, String entryKind,
      {String sourceBindingKey = ''}) {
    final normalizedEntryKind = HistoryEntryKind.normalize(entryKind);
    final history = _historiesBox.get(
      History.getKey(
        adapterName,
        bangumiItem,
        entryKind: normalizedEntryKind,
        sourceBindingKey: sourceBindingKey,
      ),
    );
    return history?.stableId.trim().isEmpty == true ? null : history;
  }
}

History _snapshotHistory(History source) {
  return History(
    source.bangumiItem,
    source.lastWatchEpisode,
    source.adapterName,
    source.lastWatchTime,
    source.lastSrc,
    source.lastWatchEpisodeName,
    entryKind: source.entryKind,
    episodePageUrl: source.episodePageUrl,
    stableId: source.stableId,
    roadId: source.roadId,
    sourceBindingKey: source.sourceBindingKey,
    sourceTitle: source.sourceTitle,
    sourceUrl: source.sourceUrl,
    sourceConfirmedAt: source.sourceConfirmedAt,
    sourceConfirmationKind: source.sourceConfirmationKind,
  )..progresses = Map<String, Progress>.from(source.progresses);
}

class _HistoryEpisodeMatch {
  const _HistoryEpisodeMatch({
    required this.bucket,
    required this.progress,
  });

  final String bucket;
  final Progress progress;
}

class _HistoryEpisodeMatcher {
  /// 历史进度匹配，优先级：
  /// 1. [stableId] + [roadId]（规则产出的稳定集身份与稳定线路身份）；
  /// 2. [stableId] + [road]（临时兼容尚未带 roadId 的调用点）；
  /// 3. [stableId] 唯一命中（仅在调用方允许且没有线路信息时使用）。
  static _HistoryEpisodeMatch? find(
    History history, {
    required int episode,
    int? road,
    String roadId = '',
    String stableId = '',
    bool allowStableIdOnlyFallback = true,
  }) {
    final id = stableId.trim();
    if (id.isEmpty) {
      return null;
    }

    final scopedRoadId = roadId.trim();
    final stableMatches = <MapEntry<String, Progress>>[];
    for (final entry in history.progresses.entries) {
      final progress = entry.value;
      if (progress.stableId != id) {
        continue;
      }
      if (scopedRoadId.isNotEmpty && progress.roadId == scopedRoadId) {
        return _HistoryEpisodeMatch(
          bucket: entry.key,
          progress: entry.value,
        );
      }
      if (scopedRoadId.isEmpty && road != null && progress.road == road) {
        return _HistoryEpisodeMatch(
          bucket: entry.key,
          progress: entry.value,
        );
      }
      stableMatches.add(entry);
    }

    if (allowStableIdOnlyFallback &&
        scopedRoadId.isEmpty &&
        road == null &&
        stableMatches.length == 1) {
      final entry = stableMatches.single;
      return _HistoryEpisodeMatch(
        bucket: entry.key,
        progress: entry.value,
      );
    }
    return null;
  }

  static String bucketForNewProgress(
    History history, {
    required int episode,
    int? road,
    String roadId = '',
    required String stableId,
  }) {
    return historyProgressKey(
      stableId: stableId,
      episode: episode,
      road: road,
      roadId: roadId,
    );
  }

  _HistoryEpisodeMatcher._();
}
