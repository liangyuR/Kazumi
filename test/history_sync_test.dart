import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/history/history_sync.dart';
import 'package:kazumi/services/sync/history_sync_service.dart';

void main() {
  group('HistorySyncDevice', () {
    test('generates stable UUID-shaped identifiers', () {
      final first = HistorySyncDevice.generateDeviceId();
      final second = HistorySyncDevice.generateDeviceId();

      expect(first, isNot(second));
      expect(
        first,
        matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )),
      );
    });
  });

  group('HistorySyncMerger', () {
    test('merges progress per episode instead of replacing whole history', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          ..._upsertPair(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 10 * 1000,
          ),
          ..._upsertPair(
            deviceId: 'device-b',
            seq: 1,
            updatedAt: 2000,
            episode: 2,
            progressMs: 20 * 1000,
          ),
        ],
      );

      final history = merged.histories.single;
      expect(history.lastWatchEpisode, 2);
      expect(_progressByEpisode(history, 1).progress.inSeconds, 10);
      expect(_progressByEpisode(history, 2).progress.inSeconds, 20);
    });

    test('clearAll prevents older events from being resurrected', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          ..._upsertPair(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 10,
          ),
          HistorySyncEvent.clearAll(
            deviceId: 'device-b',
            seq: 1,
            updatedAt: 2000,
          ),
          ..._upsertPair(
            deviceId: 'device-a',
            seq: 2,
            updatedAt: 1500,
            episode: 2,
            progressMs: 20,
          ),
          ..._upsertPair(
            deviceId: 'device-c',
            seq: 1,
            updatedAt: 3000,
            episode: 3,
            progressMs: 30,
          ),
        ],
      );

      expect(merged.histories, hasLength(1));
      expect(merged.histories.single.lastWatchEpisode, 3);
      expect(merged.histories.single.progresses.keys, [
        historyProgressKey(stableId: 'episode-3', episode: 3, roadId: 'road-0')
      ]);
      expect(merged.clearVersion, isNotNull);
    });

    test('deleteHistory blocks older upserts but allows newer watches', () {
      final entityKey = History.getKey('plugin', _item(1));
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          ..._upsertPair(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 10,
          ),
          HistorySyncEvent.deleteHistory(
            deviceId: 'device-b',
            seq: 1,
            entityKey: entityKey,
            updatedAt: 2000,
          ),
          ..._upsertPair(
            deviceId: 'device-a',
            seq: 2,
            updatedAt: 1500,
            episode: 2,
            progressMs: 20,
          ),
          ..._upsertPair(
            deviceId: 'device-a',
            seq: 3,
            updatedAt: 2500,
            episode: 3,
            progressMs: 30,
          ),
        ],
      );

      expect(merged.histories, hasLength(1));
      expect(merged.histories.single.progresses.keys, [
        historyProgressKey(stableId: 'episode-3', episode: 3, roadId: 'road-0')
      ]);
      expect(merged.deletedVersions, isEmpty);
    });

    test('ignores upserts without stable episode identity', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          HistorySyncEvent(
            eventId: 'device-a:1',
            deviceId: 'device-a',
            seq: 1,
            op: HistorySyncOp.upsertProgress,
            updatedAt: 1000,
            entityKey: History.getKey('plugin', _item(1)),
            bangumiItem: _item(1),
            adapterName: 'plugin',
            episode: 1,
            road: 0,
            progressMs: 10 * 1000,
          ),
          HistorySyncEvent(
            eventId: 'device-a:2',
            deviceId: 'device-a',
            seq: 2,
            op: HistorySyncOp.upsertWatchState,
            updatedAt: 1000,
            entityKey: History.getKey('plugin', _item(1)),
            bangumiItem: _item(1),
            adapterName: 'plugin',
            episode: 1,
            carriesWatchState: true,
          ),
        ],
      );

      expect(merged.histories, isEmpty);
    });

    test('uses deterministic tie-breakers when timestamps are equal', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 10,
          ),
          _upsert(
            deviceId: 'device-b',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 20,
          ),
        ],
      );

      expect(
        _progressByEpisode(merged.histories.single, 1).progress.inMilliseconds,
        20,
      );
    });

    test('preserves playback entry metadata when merging progress', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 10 * 1000,
            entryKind: HistoryEntryKind.offline,
            episodePageUrl: '/episode/1',
          ),
        ],
      );

      final history = merged.histories.single;
      expect(history.entryKind, HistoryEntryKind.offline);
      expect(history.episodePageUrl, '/episode/1');
      expect(_progressByEpisode(history, 1).episodePageUrl, '/episode/1');
    });

    test('keeps online and offline progress separate for the same episode', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 10 * 1000,
            entryKind: HistoryEntryKind.online,
            episodePageUrl: '/online/1',
          ),
          _upsert(
            deviceId: 'device-b',
            seq: 1,
            updatedAt: 2000,
            episode: 1,
            progressMs: 20 * 1000,
            entryKind: HistoryEntryKind.offline,
            episodePageUrl: '/offline/1',
          ),
        ],
      );

      expect(merged.histories, hasLength(2));
      final online = merged.histories.singleWhere(
        (history) => history.entryKind == HistoryEntryKind.online,
      );
      final offline = merged.histories.singleWhere(
        (history) => history.entryKind == HistoryEntryKind.offline,
      );
      expect(online.key, History.getKey('plugin', _item(1)));
      expect(
        offline.key,
        History.getKey(
          'plugin',
          _item(1),
          entryKind: HistoryEntryKind.offline,
        ),
      );
      expect(_progressByEpisode(online, 1).progress.inSeconds, 10);
      expect(_progressByEpisode(offline, 1).progress.inSeconds, 20);
    });

    test('matches progress by stableId and roadId when page url changes', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 2,
            progressMs: 10 * 1000,
            episodePageUrl: 'https://old.example.com/play/1',
            stableId: '/play/1',
            roadId: 'road-main',
          ),
          _upsert(
            deviceId: 'device-b',
            seq: 1,
            updatedAt: 2000,
            episode: 1,
            progressMs: 20 * 1000,
            episodePageUrl: 'https://new.example.com/play/1',
            stableId: '/play/1',
            roadId: 'road-main',
          ),
        ],
      );

      final progress = merged.histories.single.progresses.values.single;
      expect(progress.episode, 1);
      expect(progress.stableId, '/play/1');
      expect(progress.roadId, 'road-main');
      expect(progress.episodePageUrl, 'https://new.example.com/play/1');
      expect(progress.progress.inSeconds, 20);
    });

    test('keeps different stableIds separate even when page url matches', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 10 * 1000,
            episodePageUrl: '/shared',
            stableId: 'source-a',
            roadId: 'road-main',
          ),
          _upsert(
            deviceId: 'device-b',
            seq: 1,
            updatedAt: 2000,
            episode: 1,
            progressMs: 20 * 1000,
            episodePageUrl: '/shared',
            stableId: 'source-b',
            roadId: 'road-main',
          ),
        ],
      );

      final progresses = merged.histories.single.progresses.values;
      expect(progresses, hasLength(2));
      expect(
        progresses
            .singleWhere((progress) => progress.stableId == 'source-a')
            .progress
            .inSeconds,
        10,
      );
      expect(
        progresses
            .singleWhere((progress) => progress.stableId == 'source-b')
            .progress
            .inSeconds,
        20,
      );
    });

    test('keeps the same stableId separate by roadId', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            road: 0,
            progressMs: 10 * 1000,
            episodePageUrl: '/road-0/shared',
            stableId: 'shared-episode',
            roadId: 'source-a',
          ),
          _upsert(
            deviceId: 'device-b',
            seq: 1,
            updatedAt: 2000,
            episode: 1,
            road: 1,
            progressMs: 20 * 1000,
            episodePageUrl: '/road-1/shared',
            stableId: 'shared-episode',
            roadId: 'source-b',
          ),
        ],
      );

      final progresses = merged.histories.single.progresses.values;
      expect(progresses, hasLength(2));
      expect(
        progresses
            .singleWhere((progress) => progress.roadId == 'source-a')
            .progress
            .inSeconds,
        10,
      );
      expect(
        progresses
            .singleWhere((progress) => progress.roadId == 'source-b')
            .progress
            .inSeconds,
        20,
      );
    });

    test('does not match by page url when stableId differs', () {
      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.empty(),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 1000,
            episode: 1,
            progressMs: 10 * 1000,
            episodePageUrl: '/shared',
            stableId: 'source-a',
            roadId: 'road-main',
          ),
          _upsert(
            deviceId: 'device-b',
            seq: 1,
            updatedAt: 2000,
            episode: 1,
            progressMs: 20 * 1000,
            episodePageUrl: '/shared',
            stableId: 'source-b',
            roadId: 'road-main',
          ),
        ],
      );

      final progresses = merged.histories.single.progresses.values;
      expect(progresses, hasLength(2));
      expect(
        progresses
            .singleWhere((progress) => progress.stableId == 'source-a')
            .progress
            .inSeconds,
        10,
      );
      expect(
        progresses
            .singleWhere((progress) => progress.stableId == 'source-b')
            .progress
            .inSeconds,
        20,
      );
    });

    test('keeps watch state when local-state progress events share a timestamp',
        () {
      final history = History(
        _item(1),
        11,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.com/video',
        'EP11',
        stableId: 'episode-11',
        roadId: 'road-0',
      );
      _putProgress(
        history,
        Progress(6, 0, 6 * 1000, stableId: 'episode-6', roadId: 'road-0'),
      );
      _putProgress(
        history,
        Progress(11, 0, 11 * 1000, stableId: 'episode-11', roadId: 'road-0'),
      );

      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.fromHistories([history]),
        events: [
          _localStateUpsert(
            history: history,
            episode: 11,
            progressMs: 11 * 1000,
          ),
          _localStateUpsert(
            history: history,
            episode: 6,
            progressMs: 6 * 1000,
          ),
        ],
      );

      final mergedHistory = merged.histories.single;
      expect(mergedHistory.lastWatchEpisode, 11);
      expect(mergedHistory.lastWatchEpisodeName, 'EP11');
      expect(_progressByEpisode(mergedHistory, 6).progress.inSeconds, 6);
      expect(_progressByEpisode(mergedHistory, 11).progress.inSeconds, 11);
    });

    test('upsertProgress does not replace the latest watch state', () {
      final history = History(
        _item(1),
        5,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.com/video',
        'EP5',
        stableId: 'episode-5',
        roadId: 'road-0',
      );
      _putProgress(
        history,
        Progress(5, 0, 5 * 1000, stableId: 'episode-5', roadId: 'road-0'),
      );

      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.fromHistories([history]),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 2000,
            episode: 7,
            progressMs: 7 * 1000,
          ),
        ],
      );

      final mergedHistory = merged.histories.single;
      expect(mergedHistory.lastWatchEpisode, 5);
      expect(mergedHistory.lastWatchEpisodeName, 'EP5');
      expect(_progressByEpisode(mergedHistory, 7).progress.inSeconds, 7);
    });

    test('upsertProgress clears stale progress page url when payload has none',
        () {
      final history = History(
        _item(1),
        5,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.com/video',
        'EP5',
        episodePageUrl: '/episode/5',
        stableId: 'episode-5',
        roadId: 'road-0',
      );
      _putProgress(
        history,
        Progress(
          5,
          0,
          5 * 1000,
          episodePageUrl: '/episode/5',
          stableId: 'episode-5',
          roadId: 'road-0',
        ),
      );

      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.fromHistories([history]),
        events: [
          _upsert(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 2000,
            episode: 5,
            progressMs: 7 * 1000,
          ),
        ],
      );

      final progress = _progressByEpisode(merged.histories.single, 5);
      expect(progress.progress.inSeconds, 7);
      expect(progress.episodePageUrl, isEmpty);
    });

    test('upsertWatchState updates latest episode metadata', () {
      final history = History(
        _item(1),
        5,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.com/video',
        'EP5',
        stableId: 'episode-5',
        roadId: 'road-0',
      );
      _putProgress(
        history,
        Progress(5, 0, 5 * 1000, stableId: 'episode-5', roadId: 'road-0'),
      );

      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.fromHistories([history]),
        events: [
          _watchState(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 2000,
            episode: 7,
            stableId: 'episode-7',
          ),
        ],
      );

      final mergedHistory = merged.histories.single;
      expect(mergedHistory.lastWatchEpisode, 7);
      expect(mergedHistory.lastWatchTime.millisecondsSinceEpoch, 2000);
      expect(mergedHistory.lastSrc, 'https://example.com/video');
      expect(mergedHistory.lastWatchEpisodeName, 'EP7');
      expect(mergedHistory.stableId, 'episode-7');
    });

    test('upsertWatchState clears stale page url when latest watch has none',
        () {
      final history = History(
        _item(1),
        5,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        'https://example.com/video',
        'EP5',
        episodePageUrl: '/episode/5',
        stableId: 'episode-5',
        roadId: 'road-0',
      );
      _putProgress(
        history,
        Progress(
          5,
          0,
          5 * 1000,
          episodePageUrl: '/episode/5',
          stableId: 'episode-5',
          roadId: 'road-0',
        ),
      );

      final merged = HistorySyncMerger.merge(
        snapshot: HistorySyncSnapshot.fromHistories([history]),
        events: [
          _watchState(
            deviceId: 'device-a',
            seq: 1,
            updatedAt: 2000,
            episode: 7,
          ),
        ],
      );

      final mergedHistory = merged.histories.single;
      expect(mergedHistory.lastWatchEpisode, 7);
      expect(mergedHistory.episodePageUrl, isEmpty);
    });
  });

  group('HistorySyncCodec', () {
    test('round-trips progress identity', () {
      final progress = Progress(
        2,
        1,
        30 * 1000,
        updatedAtMs: 4000,
        episodePageUrl: '/episode/2',
        stableId: 'episode-2',
      );

      final restored = HistorySyncCodec.progressFromJson(
        HistorySyncCodec.progressToJson(progress),
      );

      expect(restored.episodePageUrl, '/episode/2');
      expect(restored.stableId, 'episode-2');
      expect(restored.progress.inSeconds, 30);
    });

    test('round-trips events through json lines', () {
      final events = [
        _upsert(
          deviceId: 'device-a',
          seq: 1,
          updatedAt: 1000,
          episode: 1,
          progressMs: 10,
          episodePageUrl: '/episode/1',
          stableId: 'episode-1',
        ),
        _watchState(
          deviceId: 'device-a',
          seq: 2,
          updatedAt: 1000,
          episode: 1,
        ),
        HistorySyncEvent.clearAll(
          deviceId: 'device-a',
          seq: 3,
          updatedAt: 2000,
        ),
      ];

      final lines = HistorySyncCodec.eventsToJsonLines(events);
      final restored = HistorySyncCodec.eventsFromJsonLines(lines);

      expect(restored.map((event) => event.eventId),
          ['device-a:1', 'device-a:2', 'device-a:3']);
      expect(restored.map((event) => event.op), [
        HistorySyncOp.upsertProgress,
        HistorySyncOp.upsertWatchState,
        HistorySyncOp.clearAll,
      ]);
      expect(restored.first.bangumiItem!.id, 1);
      expect(restored.first.episodePageUrl, '/episode/1');
      expect(restored.first.stableId, 'episode-1');
    });
  });

  group('HistorySyncService', () {
    test('builds local state events with entry metadata and progress time', () {
      final history = History(
        _item(1),
        1,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        '',
        'EP1',
        entryKind: HistoryEntryKind.offline,
        episodePageUrl: '/offline/1',
        stableId: 'offline-1',
        roadId: 'offline-road',
      );
      _putProgress(
        history,
        Progress(
          1,
          2,
          20 * 1000,
          updatedAtMs: 2500,
          episodePageUrl: '/offline/progress-1',
          stableId: 'offline-progress-1',
          roadId: 'offline-road',
        ),
      );

      final events =
          HistorySyncService.buildStateEventsFromHistories([history]);

      expect(events, hasLength(2));
      final progressEvent = events.singleWhere(
        (event) => event.op == HistorySyncOp.upsertProgress,
      );
      final watchStateEvent = events.singleWhere(
        (event) => event.op == HistorySyncOp.upsertWatchState,
      );
      expect(progressEvent.entityKey, history.key);
      expect(progressEvent.entryKind, HistoryEntryKind.offline);
      expect(progressEvent.episodePageUrl, '/offline/progress-1');
      expect(progressEvent.stableId, 'offline-progress-1');
      expect(progressEvent.updatedAt, 2500);
      expect(progressEvent.progressMs, 20 * 1000);
      expect(watchStateEvent.entryKind, HistoryEntryKind.offline);
      expect(watchStateEvent.episodePageUrl, '/offline/1');
      expect(watchStateEvent.stableId, 'offline-1');
      expect(watchStateEvent.carriesWatchState, isTrue);
    });

    test('skips local histories without stable episode identity', () {
      final history = History(
        _item(1),
        1,
        'plugin',
        DateTime.fromMillisecondsSinceEpoch(1000),
        '',
        'EP1',
      );

      final events =
          HistorySyncService.buildStateEventsFromHistories([history]);

      expect(events, isEmpty);
    });
  });
}

HistorySyncEvent _localStateUpsert({
  required History history,
  required int episode,
  required int progressMs,
}) {
  return HistorySyncEvent(
    eventId: 'local-state:${history.key}:$episode:0',
    deviceId: 'local-state',
    seq: 0,
    op: HistorySyncOp.upsertProgress,
    updatedAt: history.lastWatchTime.millisecondsSinceEpoch,
    entityKey: history.key,
    bangumiItem: history.bangumiItem,
    adapterName: history.adapterName,
    episode: episode,
    road: 0,
    progressMs: progressMs,
    lastSrc: history.lastSrc,
    lastWatchEpisodeName: history.lastWatchEpisodeName,
    stableId: _progressByEpisode(history, episode).stableId,
    roadId: _progressByEpisode(history, episode).roadId,
  );
}

HistorySyncEvent _upsert({
  required String deviceId,
  required int seq,
  required int updatedAt,
  required int episode,
  required int progressMs,
  int road = 0,
  String entryKind = HistoryEntryKind.online,
  String episodePageUrl = '',
  String stableId = '',
  String roadId = '',
}) {
  final resolvedStableId = stableId.isEmpty ? 'episode-$episode' : stableId;
  final resolvedRoadId = roadId.isEmpty ? 'road-$road' : roadId;
  final history = History(
    _item(1),
    episode,
    'plugin',
    DateTime.fromMillisecondsSinceEpoch(updatedAt),
    'https://example.com/video',
    'EP$episode',
    entryKind: entryKind,
    episodePageUrl: episodePageUrl,
    stableId: resolvedStableId,
    roadId: resolvedRoadId,
  );
  _putProgress(
    history,
    Progress(
      episode,
      road,
      progressMs,
      updatedAtMs: updatedAt,
      episodePageUrl: episodePageUrl,
      stableId: resolvedStableId,
      roadId: resolvedRoadId,
    ),
  );
  return HistorySyncEvent.upsertProgress(
    deviceId: deviceId,
    seq: seq,
    history: history,
    episode: episode,
    road: road,
    progressMs: progressMs,
    updatedAt: updatedAt,
    episodePageUrl: episodePageUrl,
    stableId: resolvedStableId,
    roadId: resolvedRoadId,
  );
}

HistorySyncEvent _watchState({
  required String deviceId,
  required int seq,
  required int updatedAt,
  required int episode,
  String stableId = '',
  String roadId = '',
}) {
  final resolvedStableId = stableId.isEmpty ? 'episode-$episode' : stableId;
  final resolvedRoadId = roadId.isEmpty ? 'road-0' : roadId;
  final history = History(
    _item(1),
    episode,
    'plugin',
    DateTime.fromMillisecondsSinceEpoch(updatedAt),
    'https://example.com/video',
    'EP$episode',
    stableId: resolvedStableId,
    roadId: resolvedRoadId,
  );
  return HistorySyncEvent.upsertWatchState(
    deviceId: deviceId,
    seq: seq,
    history: history,
    episode: episode,
    updatedAt: updatedAt,
  );
}

List<HistorySyncEvent> _upsertPair({
  required String deviceId,
  required int seq,
  required int updatedAt,
  required int episode,
  required int progressMs,
}) {
  return [
    _upsert(
      deviceId: deviceId,
      seq: seq,
      updatedAt: updatedAt,
      episode: episode,
      progressMs: progressMs,
    ),
    _watchState(
      deviceId: deviceId,
      seq: seq + 1,
      updatedAt: updatedAt,
      episode: episode,
    ),
  ];
}

void _putProgress(History history, Progress progress) {
  history.progresses[historyProgressKey(
    stableId: progress.stableId,
    episode: progress.episode,
    road: progress.road,
    roadId: progress.roadId,
  )] = progress;
}

Progress _progressByEpisode(History history, int episode) {
  return history.progresses.values
      .singleWhere((progress) => progress.episode == episode);
}

BangumiItem _item(int id) {
  return BangumiItem(
    id: id,
    type: 2,
    name: 'subject $id',
    nameCn: '条目 $id',
    summary: '',
    airDate: '2026-01-01',
    airWeekday: 4,
    rank: 0,
    images: const {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    },
    tags: const <BangumiTag>[],
    alias: const [],
    ratingScore: 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}
